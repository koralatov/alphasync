"""Check build filtering against real Git comparisons, including renamed files."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('scope', Path(__file__).resolve().parents[1] / 'scripts/check-build-scope.py')
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ScopeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.root / 'README.md').write_text('Initial guide.\n')
        self.base = self.commit('Initial')

    def git(self, *arguments):
        return subprocess.check_output(['git', *arguments], cwd=self.root, text=True).strip()

    def commit(self, message):
        self.git('add', '.')
        self.git('commit', '-qm', message)
        return self.git('rev-parse', 'HEAD')

    def event(self, head, message='Update the guide'):
        return {'before': self.base, 'after': head, 'head_commit': {'message': message}}

    def test_documentation_and_release_override(self):
        (self.root / 'README.md').write_text('Improved guide.\n')
        head = self.commit('Guide')
        self.assertFalse(scope.requires_build(self.event(head), 'push', self.root))
        self.assertTrue(scope.requires_build(self.event(head, 'Release AlphaSync 1.5'), 'push', self.root))
        request = {'pull_request': {'base': {'sha': self.base}, 'head': {'sha': head}}}
        self.assertFalse(scope.requires_build(request, 'pull_request', self.root))

    def test_runtime_help_and_renames_require_build(self):
        (self.root / 'Help.html').write_text('Bundled help.\n')
        head = self.commit('Help')
        self.assertTrue(scope.requires_build(self.event(head), 'push', self.root))
        self.base = head
        self.git('mv', 'Help.html', 'TECHNICAL.md')
        head = self.commit('Move Help')
        self.assertTrue(scope.requires_build(self.event(head), 'push', self.root))

    def test_unknown_comparisons_require_build(self):
        for event, name in [({}, 'workflow_dispatch'), ({}, 'push'),
                            ({'before': '0' * 40, 'after': self.base}, 'push'),
                            ({'before': 'f' * 40, 'after': self.base}, 'push')]:
            self.assertTrue(scope.requires_build(event, name, self.root))


if __name__ == '__main__':
    unittest.main()
