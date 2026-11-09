#!/usr/bin/env python3
"""Check that mixed or damaged app packages cannot be collected as one build."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import plistlib
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('collector', ROOT / 'scripts/collect-builds.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
release_spec = importlib.util.spec_from_file_location('release_check', ROOT / 'scripts/check-release.py')
release_check = importlib.util.module_from_spec(release_spec)
release_spec.loader.exec_module(release_check)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.folders = [self.root / profile for profile in collector.PROFILES]
        for profile, folder in zip(collector.PROFILES, self.folders):
            folder.mkdir()
            label, architectures = collector.PROFILES[profile]
            stem = f'AlphaSync-2.0-149-{label}'
            for suffix in ['', '-symbols']:
                archive = folder / (stem + suffix + '.zip')
                archive.write_bytes(b'package fixture ' + profile.encode() + suffix.encode())
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                (folder / (archive.name + '.sha256')).write_text(f'{digest}  {archive.name}\n')
                fields = {'Version': '2.0', 'Build': '149', 'Source commit': 'a' * 40}
                if not suffix:
                    fields.update(Variant=profile, **{'Minimum macOS': '13.0', 'Supported macOS': '13 and later',
                                  'Architectures': ' '.join(sorted(architectures)), 'Signing': 'ad-hoc'})
                fields.update(Archive=archive.name, **{'SHA-256': digest})
                (folder / (archive.name + '.build-information.txt')).write_text(''.join(f'{k}: {v}\n' for k, v in fields.items()))

    def collect(self):
        return collector.collect(*self.folders, self.root / 'output', '2.0', '149', 'a' * 40)

    def report(self, suffix=''):
        return next(self.folders[1].glob('*apple-silicon' + suffix + '.zip.build-information.txt'))

    def rejected(self):
        with self.assertRaises(ValueError):
            self.collect()
        self.assertFalse((self.root / 'output').exists())

    def test_complete_matching_editions(self):
        self.assertEqual(self.collect(), 12)
        self.assertEqual(len(list((self.root / 'output').iterdir())), 12)

    def test_other_source_rejected(self):
        report = self.report()
        report.write_text(report.read_text().replace('a' * 40, 'b' * 40))
        self.rejected()

    def test_wrong_architecture_rejected(self):
        report = self.report()
        report.write_text(report.read_text().replace('Architectures: arm64', 'Architectures: x86_64'))
        self.rejected()

    def test_corrupt_archive_rejected(self):
        archive = next(self.folders[1].glob('*apple-silicon.zip'))
        archive.write_bytes(b'corrupt')
        self.rejected()

    def test_other_symbols_rejected(self):
        report = self.report('-symbols')
        report.write_text(report.read_text().replace('Build: 149', 'Build: 147'))
        self.rejected()


class ReleaseAssetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        for profile, (label, architectures) in collector.PROFILES.items():
            stem = f'AlphaSync-2.0-149-{label}'
            for suffix in ['', '-symbols']:
                path = self.assets / (stem + suffix + '.zip')
                with zipfile.ZipFile(path, 'w') as archive:
                    if suffix:
                        for name in ['AlphaSync', 'AlphaSyncLauncher']:
                            archive.writestr(name + '.app.dSYM/Contents/Resources/DWARF/' + name, b'symbol fixture')
                    else:
                        for prefix, name in [('AlphaSync.app', 'AlphaSync'),
                                             ('AlphaSync.app/Contents/Library/LoginItems/AlphaSyncLauncher.app', 'AlphaSyncLauncher')]:
                            info = {'CFBundleIdentifier': 'com.tsoniq.' + name, 'CFBundleShortVersionString': '2.0',
                                    'CFBundleVersion': '149', 'LSMinimumSystemVersion': '13.0',
                                    'ASBuildProfile': profile, 'ASReleaseChannel': 'stable'}
                            archive.writestr(prefix + '/Contents/Info.plist', plistlib.dumps(info))
                fields = {'Version': '2.0', 'Build': '149', 'Source commit': 'a' * 40}
                if not suffix:
                    fields.update(Variant=profile, **{'Minimum macOS': '13.0', 'Supported macOS': '13 and later',
                                  'Architectures': ' '.join(sorted(architectures)), 'Signing': 'ad-hoc'})
                fields.update(Archive=path.name, **{'SHA-256': hashlib.sha256(path.read_bytes()).hexdigest()})
                self.write_reports(path, fields)

    def write_reports(self, path, fields):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        fields['SHA-256'] = digest
        path.with_name(path.name + '.sha256').write_text(f'{digest}  {path.name}\n')
        path.with_name(path.name + '.build-information.txt').write_text(''.join(f'{k}: {v}\n' for k, v in fields.items()))

    def validate(self):
        return release_check.validate_assets(self.assets, '2.0', '149', 'a' * 40)

    def alter_archive(self, extra):
        archive = next(self.assets.glob('*universal.zip'))
        with zipfile.ZipFile(archive, 'a') as output:
            extra(output)
        report = archive.with_name(archive.name + '.build-information.txt')
        fields = collector.read_report(report, collector.APP_FIELDS)
        self.write_reports(archive, fields)

    def test_complete_release_records_every_asset_hash(self):
        manifest = self.validate()
        self.assertEqual(len(manifest), 12)
        for name, fields in manifest.items():
            self.assertEqual(fields['sha256'], hashlib.sha256((self.assets / name).read_bytes()).hexdigest())

    def test_unsafe_archive_path_rejected_even_with_valid_checksum(self):
        self.alter_archive(lambda archive: archive.writestr('../outside.txt', b'outside'))
        with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
            self.validate()

    def test_wrong_archived_version_rejected_even_with_matching_reports(self):
        path = next(self.assets.glob('*universal.zip'))
        with zipfile.ZipFile(path) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        key = 'AlphaSync.app/Contents/Info.plist'
        info = plistlib.loads(entries[key])
        info['CFBundleVersion'] = '148'
        entries[key] = plistlib.dumps(info)
        with zipfile.ZipFile(path, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        self.write_reports(path, collector.read_report(path.with_name(path.name + '.build-information.txt'), collector.APP_FIELDS))
        with self.assertRaisesRegex(ValueError, 'unexpected metadata'):
            self.validate()

    def test_extra_release_asset_rejected(self):
        (self.assets / 'unexpected.txt').write_text('not a release asset')
        with self.assertRaisesRegex(ValueError, 'unexpected release assets'):
            self.validate()


if __name__ == '__main__':
    unittest.main()
