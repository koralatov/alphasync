#!/usr/bin/env python3
"""Check the offline Help book before indexing or releasing an app."""

import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


class HelpError(ValueError):
    pass


class Page(HTMLParser):
    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
    BLOCKED = {"script", "iframe", "object", "embed", "form", "base"}

    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path = path
        self.stack = []
        self.meta = {}
        self.anchors = set()
        self.links = []
        self.assets = []
        self.active_link = None
        self.title = []
        self.headings = []
        self.main_count = 0
        self.lang = ""
        self.charset = ""
        self.licence = []
        self.text = []
        self.feed(path.read_text(encoding="utf-8"))
        self.close()
        self.require(not self.stack, "unclosed HTML element")

    def require(self, condition, message):
        if not condition:
            raise HelpError(f"{self.path.name}: {message}")

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.require(tag not in self.BLOCKED, f"unsupported active element <{tag}>")
        self.require(not any(key.startswith("on") for key in attrs), "event handler in offline Help")
        for anchor in {attrs.get("id"), attrs.get("name") if tag == "a" else None} - {None, ""}:
            self.require(anchor not in self.anchors, f"duplicate anchor {anchor}")
            self.anchors.add(anchor)
        if tag == "html":
            self.lang = attrs.get("lang", "")
        elif tag == "meta":
            if "charset" in attrs:
                self.charset = attrs["charset"].lower()
            name = attrs.get("name", "").lower()
            if name:
                self.require(name not in self.meta, f"duplicate metadata {name}")
                self.meta[name] = attrs.get("content", "")
        elif tag == "main":
            self.main_count += 1
        elif re.fullmatch(r"h[1-6]", tag):
            self.headings.append(int(tag[1]))
        elif tag == "a" and "href" in attrs:
            self.require(self.active_link is None, "nested link")
            self.active_link = [attrs["href"], []]
        elif tag == "img":
            self.require("alt" in attrs, "image has no alternative text")
            if self.active_link:
                self.active_link[1].append(attrs["alt"])
        if "src" in attrs:
            self.assets.append(attrs["src"])
        if tag == "link":
            self.assets.append(attrs.get("href", ""))
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        self.require(bool(self.stack) and self.stack[-1] == tag, f"incorrect closing </{tag}>")
        if tag == "a" and self.active_link:
            href, words = self.active_link
            self.require(bool("".join(words).strip()), f"link has no descriptive text: {href}")
            self.links.append(href)
            self.active_link = None
        self.stack.pop()

    def handle_data(self, data):
        self.text.append(data)
        if "title" in self.stack:
            self.title.append(data)
        if "pre" in self.stack:
            self.licence.append(data)
        if self.active_link:
            self.active_link[1].append(data)


def check_help(book, licence_source=None):
    book = Path(book).resolve()
    paths = sorted(book.rglob("*.html"))
    if not paths:
        raise HelpError("The Help book has no HTML pages")
    pages = {path: Page(path) for path in paths}
    home = book / "alphasync-help.html"
    licence = book / "licence.html"
    for path, anchor in ((home, "alphasync-home"), (licence, "alphasync-licence")):
        if path not in pages or anchor not in pages[path].anchors:
            raise HelpError(f"Missing stable Help entry point: {anchor}")
    titles = set()
    graph = {}
    link_count = 0

    def local_target(page, value, asset=False):
        parts = urlsplit(value)
        if parts.scheme or parts.netloc:
            page.require(not asset and parts.scheme in {"https", "http", "mailto"}, f"non-local asset or unsupported link: {value}")
            return None
        page.require(bool(value.strip()), "empty local reference")
        target = (page.path.parent / unquote(parts.path)).resolve() if parts.path else page.path
        page.require(target.is_relative_to(book), f"reference leaves the Help book: {value}")
        page.require(target.is_file(), f"missing local target: {value}")
        if parts.fragment:
            page.require(target in pages and unquote(parts.fragment) in pages[target].anchors, f"missing fragment: {value}")
        return target

    for path, page in pages.items():
        title = "".join(page.title).strip()
        page.require(title and title not in titles, "missing or repeated page title")
        titles.add(title)
        page.require(page.lang.lower().startswith("en"), "missing English document language")
        page.require(page.charset == "utf-8", "missing UTF-8 declaration")
        for key in ("keywords", "description", "viewport"):
            page.require(bool(page.meta.get(key, "").strip()), f"missing {key} metadata")
        page.require(page.main_count == 1, "expected one main landmark")
        page.require(page.headings.count(1) == 1 and page.headings[0] == 1, "expected one initial h1")
        page.require(all(right <= left + 1 for left, right in zip(page.headings, page.headings[1:])), "skipped heading level")
        graph[path] = set()
        for value in page.links:
            target = local_target(page, value)
            if target in pages:
                graph[path].add(target)
            link_count += 1
        for value in page.assets:
            local_target(page, value, asset=True)
    landing = pages[home]
    landing.require(landing.meta.get("appletitle") == "AlphaSync Help", "wrong AppleTitle")
    icon = unquote(landing.meta.get("appleicon", ""))
    prefix = book.name + "/"
    landing.require(icon.startswith(prefix), "AppleIcon must name this Help book")
    local_target(landing, icon[len(prefix):], asset=True)
    landing.require("development version" not in "".join(landing.text).lower(), "obsolete development notice")
    for css in book.rglob("*.css"):
        content = css.read_text(encoding="utf-8")
        if re.search(r"@import\b", content, re.IGNORECASE):
            raise HelpError(f"{css.name}: imported stylesheets are not supported")
        for match in re.finditer(r"url\(\s*['\"]?([^)'\"]+)['\"]?\s*\)", content, re.IGNORECASE):
            # Resolve CSS resources beside the stylesheet, not the referring HTML.
            css_page = object.__new__(Page)
            css_page.path = css
            local_target(css_page, match.group(1).strip(), asset=True)
    reached, pending = set(), [home]
    while pending:
        path = pending.pop()
        if path not in reached:
            reached.add(path)
            pending.extend(graph[path] - reached)
    if reached != set(pages):
        raise HelpError("Pages unreachable from the Help home: " + ", ".join(sorted(path.name for path in set(pages) - reached)))
    if licence_source is not None:
        original = Path(licence_source).read_text(encoding="utf-8").strip("\n")
        if "".join(pages[licence].licence).strip("\n") != original:
            raise HelpError("The offline licence differs from the original notice")
    return {"pages": len(pages), "links": link_count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("book", type=Path)
    parser.add_argument("--licence-source", type=Path)
    args = parser.parse_args()
    try:
        result = check_help(args.book, args.licence_source)
    except (HelpError, OSError, UnicodeError) as error:
        parser.exit(1, f"Help check failed: {error}\n")
    print(f"Verified {result['pages']} offline Help pages and {result['links']} links.")


if __name__ == "__main__":
    main()
