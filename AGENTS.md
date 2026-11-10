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
- Version 2.0.2, build 151 has immutable tag `v2.0.2`, source `807b4bedf1bb1cd655e934e1495723bb5c203c93`. Preserve that tag and source. The user explicitly requested a maintenance reissue as 2.0.2 and authorised deleting the existing listing if necessary.
- The reissue uses version 2.0.2, build 152, and unique tag `v2.0.2-build.152`, because GitHub forbids reusing an immutable release tag even after deletion. Retire the build 151 listing only after the reissue is verified and public. The two public versions remain legacy 1.5.1 and modern 2.0.2. Preserve all source tags and the exact 1.5.1 release.
- `AS_RELEASE_TAG` supplies the exact stable tag for publication, Help, licence links, and package verification. Normally use `v` plus the version; an explicitly requested reissue uses `vVERSION-build.BUILD`. Never replace published assets or move a published tag. Choose a fresh version and build for future development.
- The final 2.0.2 maintenance reissue is published at `v2.0.2-build.152`, source `fbcc566207d550ee313245e3eff39a55d3c986fb`. Its first publication attempt passed, and only its listing and 1.5.1 remain public. The build 151 listing is retired; its tag and all earlier tags remain preserved. Permanent evidence for both builds is in `releases/verification`. The user considers the maintenance work complete for now.
- The user subsequently requested release 2.0.3 and retirement of both 2.0.2 listings. Prepare version 2.0.3, build 153, at standard tag `v2.0.3`. Publish and verify both editions before retiring the remaining 2.0.2 listing; the original build 151 listing is already absent. Preserve both 2.0.2 source tags, all earlier tags, and the exact frozen 1.5.1 release. Retain permanent verification and retirement records for 2.0.3.
- Version 2.0.3, build 153 is now published at immutable tag `v2.0.3`, source `db3ff4c23253c024726dd812868e6ac745a7b831`. Only 1.5.1 and 2.0.3 remain public. Both 2.0.2 listings are retired; all ten earlier source tags and the exact legacy release remain unchanged. The verified first-attempt release and retirement evidence are preserved in `releases/verification/2.0.3-153`. Choose a fresh version and build for any future release.

- The user requested a complete built-in Help review and publication as 2.0.4 after checking and emailing the 2.0.3 result. The 2.0.3 result has been checked and emailed. Prepare version 2.0.4, build 154, at `v2.0.4`. Validate every Help page, build both editions, and verify the exact downloads before publication. Keep `retire_superseded` disabled: this request does not authorise removing 2.0.3. Preserve all earlier source tags and the frozen legacy release.

- The 2.0.4 Help work is prepared at source `fb99a85d3b3ba39e0e9ad485afdde5c6de88f645`, but is not published. Run `42860366107` passed Intel checks, including 109 Swift regressions, all 55 fixtures, native interface, Universal app/helper, Help index, and symbol verification. Both attempts to allocate Apple Silicon runners failed before execution with GitHub internal server and arm64 capacity errors; publication was skipped. Preserve the successful results and re-run only failed jobs after service recovery, with publication enabled and retirement disabled. The pending evidence is in `releases/verification/2.0.4-154`. Public downloads remain 1.5.1 and 2.0.3; all eleven source tags and the frozen legacy references and assets are unchanged. After publication, verify the exact public assets and replace the pending record and documentation with the completed result.
