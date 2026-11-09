#!/usr/bin/env python3
"""Resume verified draft uploads and publish only after checking every uploaded hash."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def api_list(command, endpoint):
    pages = json.loads(command('api', '--paginate', '--slurp', endpoint))
    return [item for page in pages for item in page]


def check_tag(command, repository, tag, source, required=False):
    refs = api_list(command, f'repos/{repository}/git/matching-refs/tags/{tag}')
    found = False
    for ref in refs:
        if ref['ref'] != 'refs/tags/' + tag:
            continue
        found = True
        target = ref['object']
        for _ in range(5):
            if target['type'] != 'tag':
                break
            target = json.loads(command('api', f'repos/{repository}/git/tags/' + target['sha']))['object']
        if target['type'] != 'commit' or target['sha'] != source:
            raise ValueError('The existing release tag points to another source commit.')
    if required and not found:
        raise ValueError('The published release tag could not be verified.')


def check_draft(release, tag, source):
    if release['tag_name'] != tag or not release['draft'] or release['prerelease'] or release.get('immutable', False):
        raise ValueError('Only an unpublished stable draft can be resumed. Public releases are never changed.')
    if release['target_commitish'] != source:
        raise ValueError('The draft does not refer to the tested source.')


def check_uploaded(items, manifest, complete=False):
    actual = {item['name']: item for item in items}
    if len(actual) != len(items) or not set(actual) <= set(manifest):
        raise ValueError('The uploaded asset list differs from the verified asset list.')
    uploaded, starters = set(), []
    for name, item in actual.items():
        # GitHub documents empty starter assets left by failed uploads as safe to delete.
        if not complete and item['state'] == 'starter' and item['size'] == 0:
            starters.append(item)
            continue
        expected = manifest[name]
        if item['state'] != 'uploaded' or item['size'] != expected['size'] or item.get('digest') != 'sha256:' + expected['sha256']:
            raise ValueError(f'The uploaded asset does not match its verified hash: {name}')
        uploaded.add(name)
    if complete and set(actual) != set(manifest):
        raise ValueError('The uploaded asset list differs from the verified asset list.')
    return uploaded, starters


def publish(source, repository, version, assets, manifest, notes, command=gh):
    if not re.fullmatch(r'[0-9a-f]{40}', source) or not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Publication needs an exact source commit and stable version.')
    if len(manifest) != 12 or set(manifest) != {path.name for path in assets.iterdir()}:
        raise ValueError('The verified release assets have changed.')
    for name, expected in manifest.items():
        path = assets / name
        if path.name != name or path.is_symlink() or not path.is_file():
            raise ValueError('The verified release asset is not a regular file: ' + name)
        if path.stat().st_size != expected['size'] or hashlib.sha256(path.read_bytes()).hexdigest() != expected['sha256']:
            raise ValueError('The verified release asset has changed: ' + name)
    tag = 'v' + version
    check_tag(command, repository, tag, source)

    def find_draft():
        releases = api_list(command, f'repos/{repository}/releases?per_page=100')
        matches = [item for item in releases if item['tag_name'] == tag]
        if len(matches) > 1:
            raise ValueError('More than one release uses this tag.')
        if matches:
            check_draft(matches[0], tag, source)
            return matches[0]
        return None

    release = find_draft()
    if release is None:
        command('release', 'create', tag, '--draft', '--target', source, '--title', 'AlphaSync ' + version,
                '--notes-file', str(notes))
        release = find_draft()
        if release is None:
            raise ValueError('The newly created draft could not be found.')
    release_id = release['id']

    def current_draft():
        current = json.loads(command('api', f'repos/{repository}/releases/{release_id}'))
        check_draft(current, tag, source)
        return current

    def asset_list():
        return api_list(command, f'repos/{repository}/releases/{release_id}/assets?per_page=100')

    current_draft()
    uploaded, starters = check_uploaded(asset_list(), manifest)
    for item in starters:
        current_draft()
        current = json.loads(command('api', f'repos/{repository}/releases/assets/{item["id"]}'))
        if current['name'] != item['name'] or current['state'] != 'starter' or current['size'] != 0:
            raise ValueError('An interrupted upload changed during verification. Retry after inspection.')
        command('api', '--method', 'DELETE', f'repos/{repository}/releases/assets/{item["id"]}')
    current_draft()
    command('release', 'edit', tag, '--title', 'AlphaSync ' + version, '--notes-file', str(notes))
    missing = sorted(set(manifest) - uploaded)
    if missing:
        command('release', 'upload', tag, *(str(assets / name) for name in missing))
    current_draft()
    check_uploaded(asset_list(), manifest, complete=True)
    check_tag(command, repository, tag, source)
    command('release', 'edit', tag, '--draft=false', '--latest')
    published = json.loads(command('api', f'repos/{repository}/releases/tags/{tag}'))
    if published['id'] != release_id or published['draft'] or published['prerelease'] or published['target_commitish'] != source:
        raise ValueError('The tested draft was not published as a stable release.')
    check_tag(command, repository, tag, source, required=True)
    return published['html_url']


def main():
    source = os.environ['GITHUB_SHA']
    repository = os.environ['GH_REPO']
    run_id = os.environ['GITHUB_RUN_ID']
    settings = dict(re.findall(r'^(MARKETING_VERSION|AS_RELEASE_CHANNEL) = (.+)$',
                              Path('AlphaSync/Build/Version.xcconfig').read_text(), re.MULTILINE))
    version = settings['MARKETING_VERSION']
    if settings['AS_RELEASE_CHANNEL'] != 'stable' or not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Only a reviewed stable version can be published.')
    assets = Path('build/release-assets')
    manifest = json.loads(Path('build/release-verification/assets.json').read_text())
    notes = Path('build/release-verification/notes.md')
    body = Path(f'releases/{version}.md').read_text()
    body += f'\n[Build and verification record](https://github.com/{repository}/actions/runs/{run_id}).\n'
    notes.write_text(body)
    print('Published ' + publish(source, repository, version, assets, manifest, notes))


if __name__ == '__main__':
    main()
