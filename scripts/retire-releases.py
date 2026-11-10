#!/usr/bin/env python3
"""Apply an explicit retirement plan only after the new public release is verified."""
import importlib.util
import json
import os
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-release.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


def fingerprint(release):
    return {'id': release['id'], 'tag_name': release['tag_name'], 'target_commitish': release['target_commitish'],
            'assets': {item['name']: {key: item.get(key) for key in ('size', 'digest', 'state')}
                       for item in release['assets']}}


def retire(plan, repository, source, manifest, record, command=publisher.gh):
    version = plan['version']
    if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('The retirement plan needs a stable version.')
    current_tag = 'v' + version
    if len(manifest) != 12:
        raise ValueError('All twelve verified modern assets are required before retirement.')
    keep = {current_tag, 'v1.5.1'}
    expected = {item['tag_name']: item for item in plan['retire']}
    if len(expected) != len(plan['retire']) or set(expected) & keep:
        raise ValueError('The retirement plan includes a protected or duplicate release.')
    if any(not re.fullmatch(r'v[0-9]+\.[0-9]+(?:\.[0-9]+)?', tag) for tag in expected):
        raise ValueError('The retirement plan contains an invalid tag.')

    def releases():
        return publisher.api_list(command, f'repos/{repository}/releases?per_page=100')

    def hydrate(release):
        current = json.loads(command('api', f'repos/{repository}/releases/{release["id"]}'))
        current['assets'] = publisher.api_list(command, f'repos/{repository}/releases/{release["id"]}/assets?per_page=100')
        return current

    def public_state():
        public = [item for item in releases() if not item['draft']]
        actual = {item['tag_name']: item for item in public}
        if len(actual) != len(public) or not keep <= set(actual) or not set(actual) <= keep | set(expected):
            raise ValueError('The public release list differs from the reviewed retirement plan.')
        return {tag: hydrate(item) for tag, item in actual.items()}

    def verify_kept(actual):
        modern, legacy = actual[current_tag], actual['v1.5.1']
        if modern['prerelease'] or modern['target_commitish'] != source:
            raise ValueError('The modern release is not the tested stable source.')
        publisher.check_tag(command, repository, current_tag, source, required=True)
        publisher.check_uploaded(modern['assets'], manifest, complete=True)
        if legacy['prerelease'] or fingerprint(legacy) != plan['legacy']:
            raise ValueError('The preserved legacy release changed.')
        publisher.check_tag(command, repository, 'v1.5.1', plan['legacy_source'], required=True)
        latest = json.loads(command('api', f'repos/{repository}/releases/latest'))
        if latest['id'] != modern['id']:
            raise ValueError('The verified modern release is not the latest release.')

    def tag_object(tag):
        refs = publisher.api_list(command, f'repos/{repository}/git/matching-refs/tags/{tag}')
        item = next((item for item in refs if item['ref'] == 'refs/tags/' + tag), None)
        if item is None:
            raise ValueError('The source tag to preserve is missing: ' + tag)
        return {key: item['object'][key] for key in ('type', 'sha')}

    actual = public_state()
    verify_kept(actual)
    victims = {tag: item for tag, item in actual.items() if tag not in keep}
    tags = {}
    for tag, item in victims.items():
        if fingerprint(item) != expected[tag]:
            raise ValueError('A superseded release changed after review: ' + tag)
        tags[tag] = tag_object(tag)
    # Validate every candidate before the first deletion, and retain its public notes and hashes.
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(json.dumps({'source': source, 'keep': sorted(keep), 'retired': list(victims.values()),
                                  'preserved_tags': tags}, indent=2) + '\n')
    for tag, item in victims.items():
        if fingerprint(hydrate(item)) != expected[tag]:
            raise ValueError('A superseded release changed before removal: ' + tag)
        command('api', '--method', 'DELETE', f'repos/{repository}/releases/{item["id"]}')
        if tag_object(tag) != tags[tag]:
            raise ValueError('A preserved source tag changed: ' + tag)
    final = public_state()
    if set(final) != keep:
        raise ValueError('The public releases were not reduced to the two supported versions.')
    verify_kept(final)
    return sorted(final)


def main():
    settings = dict(re.findall(r'^(MARKETING_VERSION|AS_RELEASE_CHANNEL) = (.+)$',
                              Path('AlphaSync/Build/Version.xcconfig').read_text(), re.MULTILINE))
    version = settings['MARKETING_VERSION']
    if settings['AS_RELEASE_CHANNEL'] != 'stable' or not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Retirement needs the reviewed stable release.')
    plan = json.loads(Path(f'releases/{version}-retirement.json').read_text())
    if plan['version'] != version:
        raise ValueError('The retirement plan is for another release.')
    manifest = json.loads(Path('build/release-verification/assets.json').read_text())
    kept = retire(plan, os.environ['GH_REPO'], os.environ['GITHUB_SHA'], manifest,
                  Path('build/release-verification/retired-releases.json'))
    print('Supported public releases: ' + ', '.join(kept))


if __name__ == '__main__':
    main()
