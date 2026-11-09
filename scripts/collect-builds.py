#!/usr/bin/env python3
"""Validate and collect both macOS 13 editions without publishing them."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil

PROFILES = {
    'universal': ('macOS-13-universal', {'x86_64', 'arm64'}),
    'apple-silicon': ('macOS-13-apple-silicon', {'arm64'}),
}
APP_FIELDS = {'Version', 'Build', 'Source commit', 'Variant', 'Minimum macOS',
              'Supported macOS', 'Architectures', 'Signing', 'Archive', 'SHA-256'}
SYMBOL_FIELDS = {'Version', 'Build', 'Source commit', 'Archive', 'SHA-256'}


def read_report(path, required):
    if path.stat().st_size > 65_536:
        raise ValueError(f'Build report is too large: {path}')
    fields = {}
    for line in path.read_text().split('\n\n', 1)[0].splitlines():
        key, separator, value = line.partition(': ')
        if not separator or key in fields:
            raise ValueError(f'Invalid build report: {path}')
        fields[key] = value
    if set(fields) != required:
        raise ValueError(f'Incomplete build report: {path}')
    return fields


def check_archive(directory, fields, name):
    if fields['Archive'] != name:
        raise ValueError(f'Unexpected archive name: {fields["Archive"]}')
    archive = directory / name
    checksum = directory / (name + '.sha256')
    digest = hashlib.sha256()
    with archive.open('rb') as handle:
        for block in iter(lambda: handle.read(128 * 1024), b''):
            digest.update(block)
    if fields['SHA-256'] != digest.hexdigest() or checksum.read_text().split() != [digest.hexdigest(), name]:
        raise ValueError(f'Checksum mismatch: {archive}')
    return [archive, checksum, directory / (name + '.build-information.txt')]


def read_edition(directory, profile, version, build, source, require_notarised=False):
    label, architectures = PROFILES[profile]
    stem = f'AlphaSync-{version}-{build}-{label}'
    fields = read_report(directory / (stem + '.zip.build-information.txt'), APP_FIELDS)
    expected = {'Version': version, 'Build': build, 'Source commit': source, 'Variant': profile,
                'Minimum macOS': '13.0', 'Supported macOS': '13 and later'}
    if any(fields[key] != value for key, value in expected.items()):
        raise ValueError(f'Wrong version, source, or deployment profile: {directory}')
    if set(fields['Architectures'].split()) != architectures:
        raise ValueError(f'Wrong architectures: {directory}')
    if fields['Signing'] not in ['development', 'notarised']:
        raise ValueError(f'Unknown signing state: {directory}')
    if require_notarised and fields['Signing'] != 'notarised':
        raise ValueError(f'A notarised package is required: {directory}')
    files = check_archive(directory, fields, stem + '.zip')
    symbols = read_report(directory / (stem + '-symbols.zip.build-information.txt'), SYMBOL_FIELDS)
    if any(symbols[key] != fields[key] for key in ['Version', 'Build', 'Source commit']):
        raise ValueError(f'Crash symbols do not match the app: {directory}')
    files += check_archive(directory, symbols, stem + '-symbols.zip')
    if {p.name for p in directory.iterdir()} != {p.name for p in files}:
        raise ValueError(f'Missing or unexpected assets: {directory}')
    return fields['Signing'], files


def collect(universal, silicon, output, version, build, source, require_notarised=False):
    if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Invalid version or build number.')
    if not re.fullmatch(r'[0-9a-f]{40}', source):
        raise ValueError('Invalid source commit.')
    first, one = read_edition(universal, 'universal', version, build, source, require_notarised)
    second, two = read_edition(silicon, 'apple-silicon', version, build, source, require_notarised)
    if first != second:
        raise ValueError('The two editions have different signing states.')
    # Validate every package before creating the combined download directory.
    output.mkdir(parents=True, exist_ok=False)
    for path in one + two:
        shutil.copy2(path, output / path.name)
    return len(one + two)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--universal', required=True, type=Path)
    parser.add_argument('--apple-silicon', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--require-notarised', action='store_true')
    args = parser.parse_args()
    try:
        count = collect(args.universal, args.apple_silicon, args.output, args.version, args.build,
                        args.source_commit, args.require_notarised)
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Validated {count} assets for both editions: {args.output}')


if __name__ == '__main__':
    main()
