"""Check that mismatched or incomplete downloads cannot form one release."""
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

    def package(self, variant, version='1.4.0', build='140', source='a' * 40,
                signing='development', architectures=None):
        label = 'macOS-11-26-universal' if variant == 'universal' else 'macOS-27-apple-silicon'
        minimum = '11.0' if variant == 'universal' else '27.0'
        architectures = architectures or ('x86_64 arm64' if variant == 'universal' else 'arm64')
        directory = self.root / variant
        directory.mkdir()
        name = f'AlphaSync-{version}-{build}-{label}.zip'
        data = b'packaged build contents for ' + variant.encode()
        digest = hashlib.sha256(data).hexdigest()
        (directory / name).write_bytes(data)
        (directory / (name + '.sha256')).write_text(f'{digest}  {name}\n')
        (directory / (name + '.build-information.txt')).write_text(
            f'Version: {version}\nBuild: {build}\nSource commit: {source}\n'
            f'Variant: {variant}\nMinimum macOS: {minimum}\nArchitectures: {architectures}\n'
            f'Signing: {signing}\nArchive: {name}\nSHA-256: {digest}\n\nCompiler details\n')
        return directory / name

    def collect(self, *options, succeeds=False):
        output = self.root / 'release'
        result = subprocess.run([sys.executable, str(COLLECTOR), '--universal', str(self.root / 'universal'),
                                 '--modern', str(self.root / 'modern'), '--output', str(output), *options],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0 if succeeds else 1, result.stderr)
        if succeeds:
            self.assertEqual(len(list(output.glob('*.zip'))), 2)
            self.assertTrue((output / 'release-notes.md').exists())
        else:
            self.assertFalse(output.exists())

    def test_matching_downloads(self):
        self.package('universal')
        self.package('modern')
        self.collect(succeeds=True)

    def test_different_release_identifiers(self):
        for change in ({'version': '1.4.1'}, {'build': '141'}, {'source': 'b' * 40}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                self.root = Path(directory)
                self.package('universal')
                self.package('modern', **change)
                self.collect()

    def test_missing_download(self):
        self.package('universal')
        self.collect()

    def test_changed_archive(self):
        self.package('universal')
        archive = self.package('modern')
        archive.write_bytes(b'incomplete or replaced archive')
        self.collect()

    def test_wrong_modern_architectures(self):
        self.package('universal')
        self.package('modern', architectures='x86_64 arm64')
        self.collect()

    def test_signing_and_tag_requirements(self):
        self.package('universal')
        self.package('modern')
        self.collect('--require-notarised')
        self.collect('--tag', 'v1.4.1')

    def test_matching_notarised_downloads(self):
        self.package('universal', signing='notarised')
        self.package('modern', signing='notarised')
        self.collect('--require-notarised', '--tag', 'v1.4.0', succeeds=True)


if __name__ == '__main__':
    unittest.main()
