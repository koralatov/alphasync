#!/usr/bin/env python3
"""Exercise interrupted publication without contacting GitHub or uploading real files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('publisher', ROOT / 'scripts/publish-release.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
SOURCE = 'a' * 40
TAG = 'v2.0.1'
REPOSITORY = 'example/alphasync'


class FakeGitHub:
    def __init__(self, manifest):
        self.manifest = manifest
        self.release = None
        self.assets = []
        self.refs = []
        self.tags = {}
        self.mutations = []
        self.uploads = []
        self.interrupt_upload = False
        self.damage_upload = False
        self.move_tag_after_upload = False

    def draft(self):
        self.release = {'id': 42, 'tag_name': TAG, 'draft': True, 'prerelease': False, 'immutable': False,
                        'target_commitish': SOURCE, 'html_url': 'https://github.com/' + REPOSITORY + '/releases/tag/' + TAG}

    def asset(self, name):
        return {'id': len(self.assets) + 100, 'name': name, 'state': 'uploaded',
                'size': self.manifest[name]['size'], 'digest': 'sha256:' + self.manifest[name]['sha256']}

    def __call__(self, *args):
        if args[:2] == ('api', '--paginate'):
            endpoint = args[-1]
            if '/git/matching-refs/' in endpoint:
                return json.dumps([self.refs])
            if endpoint.endswith('/releases?per_page=100'):
                # Keep the matching draft on a later page to exercise pagination.
                other = {'tag_name': 'v0.1'}
                return json.dumps([[other], [self.release] if self.release else []])
            if endpoint.endswith('/assets?per_page=100'):
                return json.dumps([self.assets[:5], self.assets[5:]])
            raise AssertionError(args)
        if args[:3] == ('api', '--method', 'DELETE'):
            self.mutations.append(args)
            asset_id = int(args[-1].rsplit('/', 1)[1])
            self.assets = [item for item in self.assets if item['id'] != asset_id]
            return ''
        if args[0] == 'api':
            endpoint = args[1]
            if '/git/tags/' in endpoint:
                return json.dumps({'object': self.tags[endpoint.rsplit('/', 1)[1]]})
            if '/releases/assets/' in endpoint:
                asset_id = int(endpoint.rsplit('/', 1)[1])
                return json.dumps(next(item for item in self.assets if item['id'] == asset_id))
            if endpoint.endswith('/releases/42') or endpoint.endswith('/releases/tags/' + TAG):
                return json.dumps(self.release)
            raise AssertionError(args)
        self.mutations.append(args)
        if args[:2] == ('release', 'create'):
            if self.release:
                raise AssertionError('The existing draft was recreated.')
            self.draft()
        elif args[:2] == ('release', 'upload'):
            for path in args[3:]:
                name = Path(path).name
                if any(item['name'] == name for item in self.assets):
                    raise AssertionError('An existing asset was uploaded again.')
                self.uploads.append(name)
                self.assets.append(self.asset(name))
                if self.damage_upload:
                    self.assets[-1]['digest'] = 'sha256:' + '0' * 64
                if self.interrupt_upload:
                    self.interrupt_upload = False
                    raise subprocess.CalledProcessError(1, ['gh', *args])
            if self.move_tag_after_upload:
                self.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'commit', 'sha': 'b' * 40}}]
        elif args[:2] == ('release', 'edit'):
            if '--draft=false' in args:
                self.release.update(draft=False, immutable=True)
                self.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'commit', 'sha': SOURCE}}]
        else:
            raise AssertionError(args)
        return ''


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        self.manifest = {}
        for number in range(12):
            path = self.assets / f'asset-{number:02}.zip'
            path.write_bytes(f'Verified package {number}'.encode())
            self.manifest[path.name] = {'size': path.stat().st_size,
                                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        self.notes = self.root / 'notes.md'
        self.notes.write_text('Reviewed release notes.\n')
        self.github = FakeGitHub(self.manifest)

    def publish(self):
        return publisher.publish(SOURCE, REPOSITORY, '2.0.1', self.assets, self.manifest, self.notes, self.github)

    def rejected_before_mutation(self, reason):
        with self.assertRaisesRegex(ValueError, reason):
            self.publish()
        self.assertEqual(self.github.mutations, [])

    def assert_not_published(self):
        self.assertTrue(self.github.release['draft'])
        self.assertFalse(any('--draft=false' in args for args in self.github.mutations))

    def test_new_release_verifies_all_assets_before_publication(self):
        self.assertTrue(self.publish().endswith('/' + TAG))
        self.assertEqual(set(self.github.uploads), set(self.manifest))
        self.assertFalse(self.github.release['draft'])

    def test_interrupted_upload_resumes_without_replacing_completed_assets(self):
        self.github.interrupt_upload = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.publish()
        self.assert_not_published()
        self.assertEqual(len(self.github.assets), 1)
        self.publish()
        self.assertEqual(len(self.github.uploads), 12)
        self.assertEqual(len(set(self.github.uploads)), 12)
        self.assertEqual(sum(args[:2] == ('release', 'create') for args in self.github.mutations), 1)

    def test_complete_draft_needs_no_more_uploads(self):
        self.github.draft()
        self.github.assets = [self.github.asset(name) for name in self.manifest]
        self.publish()
        self.assertEqual(self.github.uploads, [])

    def test_incomplete_public_release_is_never_changed(self):
        self.github.draft()
        self.github.release['draft'] = False
        self.github.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'commit', 'sha': SOURCE}}]
        self.rejected_before_mutation('asset list')

    def test_matching_published_release_is_recognised_without_mutation(self):
        self.github.draft()
        self.github.release.update(draft=False, immutable=True)
        self.github.assets = [self.github.asset(name) for name in self.manifest]
        self.github.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'commit', 'sha': SOURCE}}]
        self.assertTrue(self.publish().endswith('/' + TAG))
        self.assertEqual(self.github.mutations, [])

    def test_public_release_from_another_source_is_never_changed(self):
        self.github.draft()
        self.github.release.update(draft=False, target_commitish='b' * 40)
        self.rejected_before_mutation('Public releases are never changed')

    def test_immutable_draft_is_never_changed(self):
        self.github.draft()
        self.github.release['immutable'] = True
        self.rejected_before_mutation('Public releases are never changed')

    def test_other_source_draft_is_never_changed(self):
        self.github.draft()
        self.github.release['target_commitish'] = 'b' * 40
        self.rejected_before_mutation('tested source')

    def test_different_uploaded_bytes_are_never_replaced(self):
        self.github.draft()
        item = self.github.asset(next(iter(self.manifest)))
        item['digest'] = 'sha256:' + 'b' * 64
        self.github.assets = [item]
        self.rejected_before_mutation('verified hash')

    def test_missing_uploaded_digest_is_rejected(self):
        self.github.draft()
        item = self.github.asset(next(iter(self.manifest)))
        del item['digest']
        self.github.assets = [item]
        self.rejected_before_mutation('verified hash')

    def test_unexpected_asset_is_never_deleted(self):
        self.github.draft()
        self.github.assets = [{'id': 100, 'name': 'unrecognised.zip', 'state': 'starter', 'size': 0}]
        self.rejected_before_mutation('asset list')

    def test_only_an_expected_empty_starter_is_removed(self):
        self.github.draft()
        names = list(self.manifest)
        self.github.assets = [self.github.asset(names[0])]
        self.github.assets.append({'id': 101, 'name': names[1], 'state': 'starter', 'size': 0})
        self.publish()
        deletions = [args for args in self.github.mutations if args[:3] == ('api', '--method', 'DELETE')]
        self.assertEqual(len(deletions), 1)
        self.assertTrue(deletions[0][-1].endswith('/101'))
        self.assertNotIn(names[0], self.github.uploads)
        self.assertIn(names[1], self.github.uploads)

    def test_nonempty_starter_is_never_deleted(self):
        self.github.draft()
        self.github.assets = [{'id': 101, 'name': next(iter(self.manifest)), 'state': 'starter', 'size': 1}]
        self.rejected_before_mutation('verified hash')

    def test_other_source_tag_is_rejected(self):
        self.github.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'tag', 'sha': 'c' * 40}}]
        self.github.tags['c' * 40] = {'type': 'commit', 'sha': 'b' * 40}
        self.rejected_before_mutation('another source')

    def test_annotated_matching_tag_is_accepted(self):
        self.github.refs = [{'ref': 'refs/tags/' + TAG, 'object': {'type': 'tag', 'sha': 'c' * 40}}]
        self.github.tags['c' * 40] = {'type': 'commit', 'sha': SOURCE}
        self.publish()

    def test_uploaded_hash_failure_leaves_a_draft(self):
        self.github.damage_upload = True
        with self.assertRaisesRegex(ValueError, 'verified hash'):
            self.publish()
        self.assert_not_published()

    def test_tag_moved_during_upload_prevents_publication(self):
        self.github.move_tag_after_upload = True
        with self.assertRaisesRegex(ValueError, 'another source'):
            self.publish()
        self.assert_not_published()

    def test_changed_local_asset_is_rejected_before_contacting_github(self):
        (self.assets / next(iter(self.manifest))).write_bytes(b'Changed after verification')
        self.rejected_before_mutation('asset has changed')


if __name__ == '__main__':
    unittest.main()
