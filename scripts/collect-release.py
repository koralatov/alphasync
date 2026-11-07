#!/usr/bin/env python3
"""Collect matching universal and modern downloads into one release directory."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil


PROFILES = {
    'universal': ('11.0', {'x86_64', 'arm64'}, 'macOS-11-26-universal'),
    'modern': ('27.0', {'arm64'}, 'macOS-27-apple-silicon'),
}


def read_package(directory, variant, require_notarised):
    reports = list(directory.glob('*.zip.build-information.txt'))
    if len(reports) != 1:
        raise ValueError(f'{directory} must contain exactly one packaged build report.')
    fields = {}
    for line in reports[0].read_text().splitlines()[:9]:
        key, separator, value = line.partition(': ')
        if not separator or key in fields:
            raise ValueError(f'Invalid build report: {reports[0]}')
        fields[key] = value
    required = {'Version', 'Build', 'Source commit', 'Variant', 'Minimum macOS',
                'Architectures', 'Signing', 'Archive', 'SHA-256'}
    if set(fields) != required:
        raise ValueError(f'Incomplete build report: {reports[0]}')
    if not re.fullmatch(r'\d+\.\d+\.\d+', fields['Version']):
        raise ValueError('Invalid version number.')
    if not re.fullmatch(r'[1-9]\d*', fields['Build']):
        raise ValueError('Invalid build number.')
    if not re.fullmatch(r'[0-9a-f]{40}', fields['Source commit']):
        raise ValueError('Invalid source commit.')
    minimum, architectures, label = PROFILES[variant]
    if (fields['Variant'] != variant or fields['Minimum macOS'] != minimum or
            set(fields['Architectures'].split()) != architectures):
        raise ValueError(f'The {variant} package has the wrong build profile.')
    if fields['Signing'] not in ('development', 'notarised'):
        raise ValueError('Unknown signing state.')
    if require_notarised and fields['Signing'] != 'notarised':
        raise ValueError('A distribution release requires both packages to be notarised.')
    expected = f"AlphaSync-{fields['Version']}-{fields['Build']}-{label}.zip"
    if fields['Archive'] != expected:
        raise ValueError(f'Unexpected archive name: {fields["Archive"]}')
    archive = directory / expected
    checksum = directory / (expected + '.sha256')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if fields['SHA-256'] != digest or checksum.read_text().split() != [digest, expected]:
        raise ValueError(f'Checksum mismatch: {archive}')
    return fields, (archive, checksum, reports[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--universal', required=True, type=Path)
    parser.add_argument('--modern', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--require-notarised', action='store_true')
    parser.add_argument('--tag', help='Require the release tag to match the shared version.')
    args = parser.parse_args()
    try:
        packages = [read_package(getattr(args, variant), variant, args.require_notarised)
                    for variant in PROFILES]
        for key in ('Version', 'Build', 'Source commit', 'Signing'):
            if len({fields[key] for fields, files in packages}) != 1:
                raise ValueError(f'The downloads have different {key.lower()} values.')
        version = packages[0][0]['Version']
        if args.tag is not None and args.tag != 'v' + version:
            raise ValueError('The release tag does not match the package version.')
        # Validate everything before creating a directory that could be published.
        args.output.mkdir(parents=True, exist_ok=False)
        for fields, files in packages:
            for path in files:
                shutil.copy2(path, args.output / path.name)
        notes = (f'AlphaSync {version}, build {packages[0][0]["Build"]}.\n\n'
                 'Choose the download for your Mac:\n\n'
                 '- **macOS 11–26, Intel or Apple Silicon:** the universal ZIP.\n'
                 '- **macOS 27 or later, Apple Silicon:** the Apple Silicon ZIP.\n\n'
                 'Both downloads use the same app version and source code.  '
                 'Keep the bundled launcher inside the app.\n')
        if packages[0][0]['Signing'] == 'development':
            notes += '\nThese are development builds with ad hoc signatures.\n'
        (args.output / 'release-notes.md').write_text(notes)
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Collected both downloads for AlphaSync {version}: {args.output}')


if __name__ == '__main__':
    main()
