#!/usr/bin/env python3
"""Validate the macOS 11 and 12 app and matching symbols before publication."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil


LABEL = 'macOS-11-12-universal'


def read_report(path, required):
    fields = {}
    for line in path.read_text().split('\n\n', 1)[0].splitlines():
        key, separator, value = line.partition(': ')
        if not separator or key in fields:
            raise ValueError(f'Invalid build report: {path}')
        fields[key] = value
    if set(fields) != required:
        raise ValueError(f'Incomplete build report: {path}')
    return fields


def check_archive(directory, fields, expected):
    if fields['Archive'] != expected:
        raise ValueError(f'Unexpected archive name: {fields["Archive"]}')
    archive = directory / expected
    checksum = directory / (expected + '.sha256')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if fields['SHA-256'] != digest or checksum.read_text().split() != [digest, expected]:
        raise ValueError(f'Checksum mismatch: {archive}')
    return archive, checksum, directory / (expected + '.build-information.txt')


def read_package(directory, require_notarised=False):
    reports = list(directory.glob(f'*-{LABEL}.zip.build-information.txt'))
    if len(reports) != 1:
        raise ValueError('Exactly one legacy app build report is required.')
    required = {'Version', 'Build', 'Source commit', 'Variant', 'Minimum macOS',
                'Supported macOS', 'Architectures', 'Signing', 'Archive', 'SHA-256'}
    fields = read_report(reports[0], required)
    if fields['Version'] != '1.5.1' or fields['Build'] != '147':
        raise ValueError('This frozen release requires version 1.5.1, build 147.')
    if not re.fullmatch(r'[0-9a-f]{40}', fields['Source commit']):
        raise ValueError('Invalid source commit.')
    if (fields['Variant'] != 'universal' or fields['Minimum macOS'] != '11.0' or
            fields['Supported macOS'] != '11 and 12' or
            set(fields['Architectures'].split()) != {'x86_64', 'arm64'}):
        raise ValueError('The package is not the macOS 11 and 12 Universal build.')
    if fields['Signing'] not in ('development', 'notarised'):
        raise ValueError('Unknown signing state.')
    if require_notarised and fields['Signing'] != 'notarised':
        raise ValueError('This operation requires a notarised package.')
    stem = f"AlphaSync-{fields['Version']}-{fields['Build']}-{LABEL}"
    files = list(check_archive(directory, fields, stem + '.zip'))
    symbols_name = stem + '-symbols.zip'
    symbols = read_report(directory / (symbols_name + '.build-information.txt'),
                          {'Version', 'Build', 'Source commit', 'Archive', 'SHA-256'})
    if any(symbols[key] != fields[key] for key in ('Version', 'Build', 'Source commit')):
        raise ValueError('The crash symbols do not match the app version and source.')
    files.extend(check_archive(directory, symbols, symbols_name))
    if {p.name for p in directory.iterdir()} != {p.name for p in files}:
        raise ValueError('The release directory contains missing or unexpected assets.')
    return fields, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--universal', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--require-notarised', action='store_true')
    parser.add_argument('--tag', help='Require the tag to match the app version.')
    parser.add_argument('--source-commit', help='Require the app and symbols to match this source commit.')
    args = parser.parse_args()
    try:
        fields, files = read_package(args.universal, args.require_notarised)
        if args.tag is not None and args.tag != 'v' + fields['Version']:
            raise ValueError('The release tag does not match the package version.')
        if args.source_commit is not None and args.source_commit != fields['Source commit']:
            raise ValueError('The downloads do not match the selected source commit.')
        # Validate every asset before creating a directory that could be published.
        args.output.mkdir(parents=True, exist_ok=False)
        for path in files:
            shutil.copy2(path, args.output / path.name)
        notes = (f"AlphaSync {fields['Version']}, build {fields['Build']}.\n\n"
                 'The final legacy release for macOS 11 and 12, on Intel or Apple Silicon.\n'
                 'Download the app ZIP to install AlphaSync. The symbols ZIP is for crash diagnosis.\n'
                 'Keep the bundled launcher inside the app.\n')
        (args.output / 'release-notes.md').write_text(notes)
    except (OSError, ValueError) as error:
        parser.exit(1, f'{error}\n')
    print(f"Validated the legacy app and symbols for AlphaSync {fields['Version']}: {args.output}")


if __name__ == '__main__':
    main()
