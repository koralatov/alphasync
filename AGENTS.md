# AlphaSync project instructions

## Writing

- Use one space after a full stop in all new or edited prose, including documentation, user-facing text, comments, and commit messages.
- Use clear, natural British English, British punctuation, curly quotation marks, and Oxford commas.
- Do not use em dashes. Use spaced en dashes sparingly.
- Preserve code syntax, quoted material, and original third-party copyright and licence notices.

## Development

- Work on master unless the user requests another branch.
- Keep changes in small, focused commits. Explain what changed and why in simple English.
- For the time being, defer automated tests until the compile or build stage, unless the user explicitly asks for tests earlier. Review code and diffs only during routine edits.
- Keep routine commits from starting CI by including `[skip ci]` in their messages. During major migrations, compile and test only at a documented major milestone or completion. Omit the marker for those milestone checks.
- End commit messages with: Made with CalxGPT (GPT-6.1 Sol Max)
- Prioritise correctness, safety, and the protection of the user’s files and device contents.
- Use standard native macOS components and public Apple frameworks. Respect the system appearance and accessibility settings.

## Frozen legacy release

- Version 1.5.1, build 147 is the final supported macOS 11 and 12 release. Build only the legacy Universal app for it.
- Preserve the exact published source on `legacy-macos-11-12` and `v1.5.1`. Do not merge, push, or force changes onto those frozen references or replace their release assets.
- Continue future development on master. Version 2.0 and later require macOS 13 or later.

## Version 2.0

- Develop on master with two targets sharing the same Swift core and SwiftUI application sources.
- Both targets support macOS 13 and later. Universal includes x86_64 and arm64; Apple Silicon includes arm64 only.
- Use public IOUSBHost bulk APIs for file transfers. The Neo’s HID keyboard interface cannot carry its bulk file protocol. Do not add a DriverKit extension or security bypass without a real hardware requirement.
- Follow the milestones and data-protection requirements in `docs/1.6-migration.md`. Do not publish a release without a release request.
- Version 2.0, build 149 has immutable tag `v2.0`, source `a508da036db4516d65d98b0a33e1d031e96f8b88`. Preserve that tag and source. The user authorised retiring its release listing and other superseded listings after 2.0.2 is verified and published. The reviewed retirement plan preserves all Git tags and the exact 1.5.1 release.
- Version 2.0.2, build 151 uses the stable release channel. Choose a new version and build before a later release; never replace published assets or move a published tag.
