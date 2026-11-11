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

- The initial 2.0.4 Help source was `fb99a85d3b3ba39e0e9ad485afdde5c6de88f645`. Three attempts of run `42860366107` failed to allocate a macOS 26 arm64 runner before execution. The revised canonical Intel and native Apple Silicon workflow below superseded that blocked candidate; its source remains in Git history.

- Version 2.0.4, build 154 is published at immutable tag `v2.0.4`, source `7b71c9fa7f8de748c91e26990050decfb2a98472`. Run `42906295418` passed both host jobs: canonical Xcode 26.6 on macOS 26 Intel, and Xcode 16.4 compatibility checks on macOS 15 Apple Silicon. Both hosts built both editions and passed 109 Swift regressions, all 55 Help and release fixtures, and native interface checks. A separate native Apple Silicon job verified and ran both downloaded canonical apps before Intel publication repeated package verification. Help, helpers, architectures, signatures, hardened runtime, matching symbols, all twelve public asset hashes, and the latest-release state passed verification. Permanent evidence is in `releases/verification/2.0.4-154`. Retirement stayed disabled; the existing 1.5.1 and 2.0.3 releases, all eleven earlier tags, and the frozen legacy source and assets remain unchanged. Keep the documented native Help Viewer, VoiceOver, physical Neo, Login Items approval, and macOS 13 checks explicit. Choose a fresh version and build for future app changes; never replace these assets or move this tag.

- The final native interface checker uses private preferences, an isolated Login Items fixture, direct execution, unbuffered progress, and a failing 120-second deadline with process sampling. All native assertions passed in the published build. Keep the bounded checker and all publication gates for future releases.

- The Intel About stall was diagnosed from the process sample in run `42904497735`. The published source uses the public `doc.text` symbol when bundled artwork is unavailable, avoiding the synchronous application-icon service lookup. Both native interface jobs passed with this correction.

- The user subsequently requested deletion of the 2.0.3 release listing. Retirement is complete: only 1.5.1 and 2.0.4 are published, with 2.0.4 latest. The exact retained release notes and assets, all twelve source tags including `v2.0.3`, and the frozen legacy branch are unchanged. The reviewed plan, archived 2.0.3 notes and asset metadata, and completion evidence are in `releases/verification/2.0.4-154`. This retirement did not rebuild either app or move a source tag.

- On 11 November 2026, the user reported 2.0.4 remaining in keyboard mode on an M2 MacBook Air while 1.5.1 works. Unpublished 2.0.5, build 155 restores the legacy USB configuration and endpoint-zero controls through public IOUSBHost APIs. Source `56e1db9936a115bf09494d3e0d51bd2d504ecc8f` passed non-publishing run `43005406688`: 115 Swift tests, 55 fixtures, both app builds and native interfaces on Intel and Apple Silicon, and native verification of both canonical packages. The initial compiler selector correction and permanent evidence are in `docs/neo-keyboard-mode.md` and `releases/verification/2.0.5-155`. Physical resolution is unverified until the user tests this candidate. Do not publish a release without a release request, replace 2.0.4 assets, or change protected tags or legacy source.

- The user subsequently reported that the supplied 2.0.5, build 155 quits unexpectedly. Its record is now `crash-reported-not-published`; the physical connection fix is not confirmed. The photograph contains only the generic crash dialog. Preserve source `56e1db9936a115bf09494d3e0d51bd2d504ecc8f` and its matching symbols, obtain the full crash report and crash timing, and diagnose the actual failing thread before choosing another correction. Use build 156 or later for a changed test app. Do not replace the original candidate, publish a new release, or change protected releases or tags.

- The full build 155 crash report is now available and identifies macOS 14.7.1 on the M2 Air. The abort is an Objective-C exception through `IOBufferMutableData.bytes` from `USBModeSwitchConnection.send` on the USB queue. Build 156 replaces specialised fixed kernel buffers with ordinary Foundation buffers for all control and bulk requests, with bounded copies and independent ownership. Follow the documented full non-publishing milestone and eight new buffer-boundary regressions. Do not commit the raw report or its private identifiers, replace build 155, change protected releases or tags, or claim physical resolution before the new candidate is tested.

- Build 156 source `89c26ce25918153341e7f367a7219d5d8baaf5a4` passed both host jobs in run `43020148543`: 123 Swift regressions, including eight new buffer checks, all 55 fixtures, both app and helper builds, native interfaces, and no compiler warnings. Local checks of all twelve canonical assets and both Help books passed. The final native download job received no Mac runner in two fifteen-minute attempts and executed no steps; the overall run is not passed. The pending record is `releases/verification/2.0.5-156/verification.json`. Preserve the successful builds and retry only the unstarted native job. Finish native download verification and the test-build handover, then send the user the requested summary and outcome by email. Do not publish a release or claim physical Neo resolution.
