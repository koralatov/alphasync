#!/usr/bin/env python3
"""Check that mixed or damaged app packages cannot be collected as one build."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('collector', ROOT / 'scripts/collect-builds.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.folders = [self.root / profile for profile in collector.PROFILES]
        for profile, folder in zip(collector.PROFILES, self.folders):
            folder.mkdir()
            label, architectures = collector.PROFILES[profile]
            stem = f'AlphaSync-1.6-148-{label}'
            for suffix in ['', '-symbols']:
                archive = folder / (stem + suffix + '.zip')
                archive.write_bytes(b'package fixture ' + profile.encode() + suffix.encode())
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                (folder / (archive.name + '.sha256')).write_text(f'{digest}  {archive.name}\n')
                fields = {'Version': '1.6', 'Build': '148', 'Source commit': 'a' * 40}
                if not suffix:
                    fields.update(Variant=profile, **{'Minimum macOS': '13.0', 'Supported macOS': '13 and later',
                                  'Architectures': ' '.join(sorted(architectures)), 'Signing': 'development'})
                fields.update(Archive=archive.name, **{'SHA-256': digest})
                (folder / (archive.name + '.build-information.txt')).write_text(''.join(f'{k}: {v}\n' for k, v in fields.items()))

    def collect(self):
        return collector.collect(*self.folders, self.root / 'output', '1.6', '148', 'a' * 40)

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
        report.write_text(report.read_text().replace('Build: 148', 'Build: 147'))
        self.rejected()


if __name__ == '__main__':
    unittest.main()
