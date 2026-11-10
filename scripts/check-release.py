#!/usr/bin/env python3
"""Check the exact release assets before extracting or publishing them."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import plistlib
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect-builds.py'))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def archive_entries(archive, roots):
    entries = archive.infolist()
    if len(entries) > 10_000 or sum(item.file_size for item in entries) > 256 * 1024 * 1024:
        raise ValueError('The archive exceeds the release size limits.')
    names = set()
    for item in entries:
        path = PurePosixPath(item.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in item.filename or not path.parts:
            raise ValueError(f'Unsafe archive path: {item.filename}')
        if item.filename in names:
            raise ValueError(f'Duplicate archive entry: {item.filename}')
        names.add(item.filename)
        if path.parts[0] not in roots | {'__MACOSX'}:
            raise ValueError(f'Unexpected archive root: {item.filename}')
    return names


def validate_bundle(archive, prefix, identifier, version, build):
    info = archive.getinfo(prefix + '/Contents/Info.plist')
    if info.file_size > 1024 * 1024:
        raise ValueError('The bundle property list is too large.')
    fields = plistlib.loads(archive.read(info))
    expected = {'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': version,
                'CFBundleVersion': build, 'LSMinimumSystemVersion': '13.0'}
    if any(fields.get(key) != value for key, value in expected.items()):
        raise ValueError(f'The archived bundle has unexpected metadata: {prefix}')
    return fields


def validate_assets(directory, version, build, source, tag=None):
    expected = set()
    manifest = {}
    with tempfile.TemporaryDirectory() as temporary:
        for profile, (label, _) in collector.PROFILES.items():
            stem = f'AlphaSync-{version}-{build}-{label}'
            names = [stem + suffix + '.zip' + extra for suffix in ['', '-symbols']
                     for extra in ['', '.sha256', '.build-information.txt']]
            expected.update(names)
            staging = Path(temporary) / profile
            staging.mkdir()
            for name in names:
                path = directory / name
                if not path.is_file() or path.is_symlink():
                    raise ValueError(f'Missing regular release asset: {name}')
                (staging / name).symlink_to(path.resolve())
                manifest[name] = {'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
            collector.read_edition(staging, profile, version, build, source)
            with zipfile.ZipFile(directory / (stem + '.zip')) as archive:
                archive_entries(archive, {'AlphaSync.app'})
                app = validate_bundle(archive, 'AlphaSync.app', 'com.tsoniq.AlphaSync', version, build)
                validate_bundle(archive, 'AlphaSync.app/Contents/Library/LoginItems/AlphaSyncLauncher.app',
                                'com.tsoniq.AlphaSyncLauncher', version, build)
                if app.get('ASBuildProfile') != profile or app.get('ASReleaseChannel') != 'stable':
                    raise ValueError('The archived app has the wrong edition or release channel.')
                if app.get('ASReleaseTag') != (tag or 'v' + version):
                    raise ValueError('The archived app links to another release tag.')
            with zipfile.ZipFile(directory / (stem + '-symbols.zip')) as archive:
                names_in_archive = archive_entries(archive, {'AlphaSync.app.dSYM', 'AlphaSyncLauncher.app.dSYM'})
                for name in ['AlphaSync', 'AlphaSyncLauncher']:
                    if name + '.app.dSYM/Contents/Resources/DWARF/' + name not in names_in_archive:
                        raise ValueError(f'Missing archived crash symbols: {name}')
    if {path.name for path in directory.iterdir()} != expected:
        raise ValueError('There are missing or unexpected release assets.')
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('assets', type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--tag')
    parser.add_argument('--manifest', required=True, type=Path)
    args = parser.parse_args()
    try:
        manifest = validate_assets(args.assets, args.version, args.build, args.source, args.tag)
        args.manifest.write_text(json.dumps(manifest, indent=2) + '\n')
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f'{error}\n')
    print(f'Checked all {len(manifest)} release assets, bundle metadata, checksums, and archive paths.')


if __name__ == '__main__':
    main()
