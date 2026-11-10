#!/usr/bin/env python3
"""Check release-list retirement with disposable records and no GitHub mutations."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('retirement', ROOT / 'scripts/retire-releases.py')
retirement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retirement)
SOURCE, LEGACY_SOURCE = 'a' * 40, 'b' * 40


def release(identifier, tag, source, count):
    return {'id': identifier, 'tag_name': tag, 'target_commitish': source, 'draft': False, 'prerelease': False,
            'assets': [{'name': f'{tag}-{index}.zip', 'size': 100 + index, 'digest': 'sha256:' + 'c' * 64,
                        'state': 'uploaded'} for index in range(count)]}


class FakeGitHub:
    def __init__(self):
        self.releases = {item['tag_name']: item for item in [release(10, 'v2.0.2', SOURCE, 12),
            release(9, 'v1.5.1', LEGACY_SOURCE, 6), release(8, 'v2.0', 'd' * 40, 12), release(7, 'v1.5', 'e' * 40, 6)]}
        self.tags = {tag: {'type': 'commit', 'sha': item['target_commitish']} for tag, item in self.releases.items()}
        self.deleted = []
        self.latest = 'v2.0.2'

    def __call__(self, *args):
        if args[:3] == ('api', '--method', 'DELETE'):
            endpoint = args[-1]
            if '/git/' in endpoint:
                raise AssertionError('A source tag was deleted.')
            identifier = int(endpoint.rsplit('/', 1)[1])
            tag = next(tag for tag, item in self.releases.items() if item['id'] == identifier)
            del self.releases[tag]
            self.deleted.append(tag)
            return ''
        if args[:2] == ('api', '--paginate'):
            endpoint = args[-1]
            if '/git/matching-refs/tags/' in endpoint:
                prefix = endpoint.split('/tags/')[1]
                return json.dumps([[{'ref': 'refs/tags/' + tag, 'object': target}
                                    for tag, target in self.tags.items() if tag.startswith(prefix)]])
            if endpoint.endswith('/releases?per_page=100'):
                return json.dumps([list(self.releases.values())])
            if '/assets?' in endpoint:
                identifier = int(endpoint.split('/releases/')[1].split('/')[0])
                return json.dumps([next(item['assets'] for item in self.releases.values() if item['id'] == identifier)])
        if args[0] == 'api':
            if args[1].endswith('/latest'):
                return json.dumps(self.releases[self.latest])
            identifier = int(args[1].rsplit('/', 1)[1])
            return json.dumps(next(item for item in self.releases.values() if item['id'] == identifier))
        raise AssertionError(args)


class RetirementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.record = Path(self.temporary.name) / 'record.json'
        self.github = FakeGitHub()
        self.plan = {'version': '2.0.2', 'legacy_source': LEGACY_SOURCE,
                     'legacy': retirement.fingerprint(self.github.releases['v1.5.1']),
                     'retire': [retirement.fingerprint(self.github.releases[tag]) for tag in ('v2.0', 'v1.5')]}
        self.manifest = {item['name']: {'size': item['size'], 'sha256': item['digest'][7:]}
                         for item in self.github.releases['v2.0.2']['assets']}

    def retire(self):
        return retirement.retire(self.plan, 'example/alphasync', SOURCE, self.manifest, self.record, self.github)

    def rejected(self, reason):
        with self.assertRaisesRegex(ValueError, reason):
            self.retire()
        self.assertEqual(self.github.deleted, [])

    def test_only_reviewed_old_listings_are_removed_and_all_tags_survive(self):
        tags = copy.deepcopy(self.github.tags)
        legacy = copy.deepcopy(self.github.releases['v1.5.1'])
        self.assertEqual(self.retire(), ['v1.5.1', 'v2.0.2'])
        self.assertEqual(set(self.github.deleted), {'v2.0', 'v1.5'})
        self.assertEqual(self.github.tags, tags)
        self.assertEqual(self.github.releases['v1.5.1'], legacy)
        self.assertEqual(len(json.loads(self.record.read_text())['retired']), 2)

    def test_partial_retirement_can_resume(self):
        del self.github.releases['v2.0']
        self.assertEqual(self.retire(), ['v1.5.1', 'v2.0.2'])
        self.assertEqual(self.github.deleted, ['v1.5'])

    def test_a_reissue_retires_the_previous_build_after_verifying_the_new_tag(self):
        self.github.releases['v2.0.2']['target_commitish'] = 'f' * 40
        self.github.tags['v2.0.2']['sha'] = 'f' * 40
        self.plan['retire'].append(retirement.fingerprint(self.github.releases['v2.0.2']))
        tag = 'v2.0.2-build.152'
        self.plan.update(release_tag=tag, build='152')
        self.github.releases[tag] = release(11, tag, SOURCE, 12)
        self.github.tags[tag] = {'type': 'commit', 'sha': SOURCE}
        self.github.latest = tag
        self.manifest = {item['name']: {'size': item['size'], 'sha256': item['digest'][7:]}
                         for item in self.github.releases[tag]['assets']}
        tags = copy.deepcopy(self.github.tags)
        self.assertEqual(self.retire(), ['v1.5.1', tag])
        self.assertIn('v2.0.2', self.github.deleted)
        self.assertEqual(self.github.tags, tags)

    def test_a_reissue_tag_for_another_build_prevents_every_deletion(self):
        self.plan.update(release_tag='v2.0.2-build.151', build='152')
        self.rejected('version and build')

    def test_incomplete_modern_release_prevents_every_deletion(self):
        self.github.releases['v2.0.2']['assets'].pop()
        self.rejected('asset list')

    def test_changed_legacy_asset_prevents_every_deletion(self):
        self.github.releases['v1.5.1']['assets'][0]['size'] += 1
        self.rejected('legacy release changed')

    def test_changed_old_asset_prevents_every_deletion(self):
        self.github.releases['v1.5']['assets'][0]['digest'] = 'sha256:' + 'f' * 64
        self.rejected('changed after review')

    def test_unreviewed_public_release_prevents_every_deletion(self):
        self.github.releases['v3.0'] = release(20, 'v3.0', 'f' * 40, 12)
        self.rejected('public release list')

    def test_a_plan_cannot_retire_the_legacy_release(self):
        self.plan['retire'].append(self.plan['legacy'])
        self.rejected('protected')

    def test_a_different_latest_release_prevents_every_deletion(self):
        self.github.latest = 'v2.0'
        self.rejected('not the latest')


if __name__ == '__main__':
    unittest.main()
