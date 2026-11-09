"""Reject incomplete, altered, or mismatched legacy release assets."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

COLLECTOR = Path(__file__).resolve().parents[1] / 'scripts' / 'collect-release.py'


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package_dir = self.root / 'universal'
        self.package_dir.mkdir()

    def package(self, version='1.5.1', build='147', source='a' * 40,
                architectures='x86_64 arm64', supported='11 and 12', symbols_source=None):
        stem = f'AlphaSync-{version}-{build}-macOS-11-12-universal'
        for symbols in (False, True):
            name = stem + ('-symbols.zip' if symbols else '.zip')
            data = b'crash symbols' if symbols else b'legacy app'
            digest = hashlib.sha256(data).hexdigest()
            (self.package_dir / name).write_bytes(data)
            (self.package_dir / (name + '.sha256')).write_text(f'{digest}  {name}\n')
            report = (f'Version: {version}\nBuild: {build}\n'
                      f'Source commit: {(symbols_source or source) if symbols else source}\n')
            if not symbols:
                report += (f'Variant: universal\nMinimum macOS: 11.0\nSupported macOS: {supported}\n'
                           f'Architectures: {architectures}\nSigning: development\n')
            report += f'Archive: {name}\nSHA-256: {digest}\n\nCompiler or UUID details\n'
            (self.package_dir / (name + '.build-information.txt')).write_text(report)
        return self.package_dir / (stem + '.zip')

    def collect(self, *options, succeeds=False):
        output = self.root / 'release'
        result = subprocess.run([sys.executable, str(COLLECTOR), '--universal', str(self.package_dir),
                                 '--output', str(output), *options], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0 if succeeds else 1, result.stderr)
        if succeeds:
            self.assertEqual(len(list(output.glob('*.zip'))), 2)  # One app, one symbol archive.
            self.assertEqual(len(list(output.iterdir())), 7)
        else:
            self.assertFalse(output.exists())

    def test_complete_legacy_release(self):
        self.package()
        self.collect('--tag', 'v1.5.1', '--source-commit', 'a' * 40, succeeds=True)

    def test_wrong_version(self):
        self.package(version='1.6')
        self.collect()

    def test_wrong_build(self):
        self.package(build='146')
        self.collect()

    def test_wrong_architecture(self):
        self.package(architectures='arm64')
        self.collect()

    def test_wrong_supported_systems(self):
        self.package(supported='11 through 26')
        self.collect()

    def test_changed_app(self):
        self.package().write_bytes(b'changed app')
        self.collect()

    def test_changed_symbols(self):
        self.package()
        next(self.package_dir.glob('*-symbols.zip')).write_bytes(b'changed symbols')
        self.collect()

    def test_missing_symbols(self):
        self.package()
        next(self.package_dir.glob('*-symbols.zip')).unlink()
        self.collect()

    def test_mismatched_symbols(self):
        self.package(symbols_source='b' * 40)
        self.collect()

    def test_unexpected_modern_download(self):
        self.package()
        (self.package_dir / 'AlphaSync-modern.zip').write_bytes(b'wrong edition')
        self.collect()

    def test_publication_requirements(self):
        self.package()
        self.collect('--require-notarised')
        self.collect('--tag', 'v1.5')
        self.collect('--source-commit', 'b' * 40)


if __name__ == '__main__':
    unittest.main()
