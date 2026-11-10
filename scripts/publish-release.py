#!/usr/bin/env python3
"""Resume verified draft uploads and publish only after checking every uploaded hash."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


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


def release_tag(version, tag=None, build=None):
    if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('The release tag needs a stable version.')
    standard = 'v' + version
    if tag is None or tag == standard:
        return standard
    if build is not None and re.fullmatch(r'[1-9][0-9]*', build) and tag == standard + '-build.' + build:
        return tag
    raise ValueError('The release tag does not match its version and build.')


def publish(source, repository, version, assets, manifest, notes, command=gh, *, tag=None, build=None):
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
    tag = release_tag(version, tag, build)
    check_tag(command, repository, tag, source)

    def find_release():
        releases = api_list(command, f'repos/{repository}/releases?per_page=100')
        matches = [item for item in releases if item['tag_name'] == tag]
        if len(matches) > 1:
            raise ValueError('More than one release uses this tag.')
        if matches:
            return matches[0]
        return None

    release = find_release()
    if release is not None and not release['draft']:
        if release['prerelease'] or release['target_commitish'] != source:
            raise ValueError('Public releases are never changed. The existing release differs from the tested source.')
        check_tag(command, repository, tag, source, required=True)
        existing = api_list(command, f'repos/{repository}/releases/{release["id"]}/assets?per_page=100')
        check_uploaded(existing, manifest, complete=True)
        return release['html_url']
    if release is None:
        # Use the creation response. A release list can briefly omit a newly created draft.
        with tempfile.TemporaryDirectory() as temporary:
            request = Path(temporary) / 'release.json'
            request.write_text(json.dumps({'tag_name': tag, 'target_commitish': source, 'name': 'AlphaSync ' + version,
                                           'draft': True, 'prerelease': False, 'body': notes.read_text()}))
            release = json.loads(command('api', '--method', 'POST', f'repos/{repository}/releases', '--input', str(request)))
    release_id = release['id']
    check_draft(release, tag, source)

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
    settings = dict(re.findall(r'^(MARKETING_VERSION|CURRENT_PROJECT_VERSION|AS_RELEASE_CHANNEL|AS_RELEASE_TAG) = (.+)$',
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
    print('Published ' + publish(source, repository, version, assets, manifest, notes,
                                tag=settings.get('AS_RELEASE_TAG'), build=settings['CURRENT_PROJECT_VERSION']))


if __name__ == '__main__':
    main()
