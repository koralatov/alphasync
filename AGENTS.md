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
- Keep routine commits from starting CI by including `[skip ci]` in their messages. Omit it when the user requests a compile, build, or release.
- End commit messages with: Made with CalxGPT (GPT-6.1 Sol Max)
- Prioritise correctness, safety, and the protection of the user’s files and device contents.
- Use standard native macOS components and public Apple frameworks. Respect the system appearance and accessibility settings.

## Frozen legacy release

- Version 1.5.1, build 147 is the final supported macOS 11 and 12 release. Build only the legacy Universal app for it.
- Preserve the exact published source on `legacy-macos-11-12` and `v1.5.1`. Do not merge, push, or force changes onto those frozen references or replace their release assets.
- Continue future development on master. Version 1.6 will require a newer macOS version.
