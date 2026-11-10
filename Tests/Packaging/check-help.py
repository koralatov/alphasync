#!/usr/bin/env python3
"""Check Help validation with broken books and the real licence generator."""

import html
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("help_check", ROOT / "scripts/check-help.py")
help_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(help_check)


def page(title, body, extra=""):
    return f'''<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<meta name="KEYWORDS" content="help"><meta name="description" content="A Help topic.">
<link rel="stylesheet" href="help.css"><title>{title}</title>{extra}
</head><body><main><h1>{title}</h1>{body}</main></body></html>'''


class HelpTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.book = self.root / "AlphaSync Help"
        self.book.mkdir()
        self.original = self.root / "LICENSE"
        self.original.write_text("Original <notice> & conditions.\n", encoding="utf-8")
        (self.book / "help.css").write_text("body { color: CanvasText; }", encoding="utf-8")
        (self.book / "icon.png").write_bytes(b"fixture")
        self.home = self.book / "alphasync-help.html"
        self.home.write_text(page("AlphaSync Help", '<a id="alphasync-home" name="alphasync-home"></a><a href="licence.html#alphasync-licence">Licence</a>', '<meta name="AppleTitle" content="AlphaSync Help"><meta name="AppleIcon" content="AlphaSync%20Help/icon.png">'), encoding="utf-8")
        self.licence = self.book / "licence.html"
        self.licence.write_text(page("Licence", '<a id="alphasync-licence" name="alphasync-licence"></a><pre>' + html.escape(self.original.read_text()) + '</pre><a href="alphasync-help.html">AlphaSync Help</a>'), encoding="utf-8")

    def change(self, path, before, after):
        path.write_text(path.read_text(encoding="utf-8").replace(before, after), encoding="utf-8")

    def check(self):
        return help_check.check_help(self.book, self.original)

    def test_complete_book_and_escaped_original_notice(self):
        self.assertEqual(self.check(), {"pages": 2, "links": 2})

    def test_missing_local_page(self):
        self.change(self.home, "licence.html#alphasync-licence", "missing.html")
        with self.assertRaisesRegex(help_check.HelpError, "missing local target"):
            self.check()

    def test_missing_fragment(self):
        self.change(self.home, "#alphasync-licence", "#missing")
        with self.assertRaisesRegex(help_check.HelpError, "missing fragment"):
            self.check()

    def test_orphan_page(self):
        (self.book / "orphan.html").write_text(page("Unlinked", "<p>Lost task.</p>"), encoding="utf-8")
        with self.assertRaisesRegex(help_check.HelpError, "unreachable"):
            self.check()

    def test_repeated_anchor(self):
        self.change(self.home, "</main>", '<p id="alphasync-home">Repeated</p></main>')
        with self.assertRaisesRegex(help_check.HelpError, "duplicate anchor"):
            self.check()

    def test_empty_link(self):
        self.change(self.home, ">Licence</a>", "></a>")
        with self.assertRaisesRegex(help_check.HelpError, "descriptive text"):
            self.check()

    def test_remote_resource(self):
        self.change(self.home, 'href="help.css"', 'href="https://example.com/help.css"')
        with self.assertRaisesRegex(help_check.HelpError, "non-local asset"):
            self.check()

    def test_path_outside_book(self):
        self.change(self.home, 'href="help.css"', 'href="../LICENSE"')
        with self.assertRaisesRegex(help_check.HelpError, "leaves the Help book"):
            self.check()

    def test_active_content(self):
        self.change(self.home, "</main>", "<script>bad()</script></main>")
        with self.assertRaisesRegex(help_check.HelpError, "active element"):
            self.check()

    def test_broken_help_menu_entry(self):
        self.change(self.home, 'id="alphasync-home" name="alphasync-home"', 'id="different"')
        with self.assertRaisesRegex(help_check.HelpError, "stable Help entry point"):
            self.check()

    def test_wrong_book_title(self):
        self.change(self.home, 'name="AppleTitle" content="AlphaSync Help"', 'name="AppleTitle" content="Other Help"')
        with self.assertRaisesRegex(help_check.HelpError, "AppleTitle"):
            self.check()

    def test_changed_licence(self):
        self.change(self.licence, "Original", "Changed")
        with self.assertRaisesRegex(help_check.HelpError, "differs from the original"):
            self.check()

    def test_real_book_and_generator(self):
        resources = self.root / "build/Contents/Resources"
        target = resources / "AlphaSync Help"
        shutil.copytree(ROOT / "AlphaSync/AlphaSync Help", target)
        environment = dict(os.environ, SRCROOT=str(ROOT / "AlphaSync"), TARGET_BUILD_DIR=str(self.root / "build"), UNLOCALIZED_RESOURCES_FOLDER_PATH="Contents/Resources")
        result = subprocess.run(["bash", str(ROOT / "scripts/build-help.sh"), "--skip-index"], env=environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(help_check.check_help(target, ROOT / "LICENSE")["pages"], 18)


if __name__ == "__main__":
    unittest.main()
