#!/usr/bin/env python3
"""Upload verified assets to a draft, then publish only after checking uploaded hashes."""
import json
import os
from pathlib import Path
import re
import subprocess


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


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
    if len(manifest) != 12 or set(manifest) != {path.name for path in assets.iterdir()}:
        raise ValueError('The verified release assets have changed.')
    notes = Path('build/release-verification/notes.md')
    body = Path(f'releases/{version}.md').read_text()
    body += f'\n[Build and verification record](https://github.com/{repository}/actions/runs/{run_id}).\n'
    notes.write_text(body)
    tag = 'v' + version
    refs = json.loads(gh('api', f'repos/{repository}/git/matching-refs/tags/{tag}'))
    for ref in refs:
        if ref['ref'] == 'refs/tags/' + tag:
            target = ref['object']
            for _ in range(5):
                if target['type'] != 'tag':
                    break
                target = json.loads(gh('api', f'repos/{repository}/git/tags/' + target['sha']))['object']
            if target['type'] != 'commit' or target['sha'] != source:
                raise ValueError('The existing release tag points to another source commit.')
    # A failure leaves a draft for inspection. Never replace an existing public release.
    gh('release', 'create', tag, '--draft', '--target', source, '--title', 'AlphaSync ' + version,
       '--notes-file', str(notes))
    gh('release', 'upload', tag, *(str(assets / name) for name in sorted(manifest)))
    releases = json.loads(gh('api', f'repos/{repository}/releases?per_page=100'))
    release = next(item for item in releases if item['tag_name'] == tag)
    if not release['draft'] or release['target_commitish'] != source:
        raise ValueError('The draft does not refer to the tested source.')
    actual = {item['name']: item for item in release['assets']}
    if set(actual) != set(manifest):
        raise ValueError('The uploaded asset list differs from the verified asset list.')
    for name, expected in manifest.items():
        item = actual[name]
        if item['state'] != 'uploaded' or item['size'] != expected['size'] or item['digest'] != 'sha256:' + expected['sha256']:
            raise ValueError(f'The uploaded asset does not match its verified hash: {name}')
    gh('release', 'edit', tag, '--draft=false', '--latest')
    published = json.loads(gh('api', f'repos/{repository}/releases/tags/{tag}'))
    if published['draft'] or published['prerelease']:
        raise ValueError('The release was not published as a stable release.')
    print('Published ' + published['html_url'])


if __name__ == '__main__':
    main()
