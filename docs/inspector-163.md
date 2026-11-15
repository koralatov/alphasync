# File previews in build 163

Private **2.0.5, build 163** is verified and ready for testing with Preview shown only for exactly one selected file.  The user reports that build 162 appears to work and will complete the wider M2 MacBook Air checks as time permits.  This request authorises a new test build, without publishing 2.1 or changing existing public releases.

## Change

Use the Inspector’s existing single-file selection to conditionally include the whole Preview section.  Keep the selected item’s header icon and More Information.  Remove the enlarged duplicate symbol used for a Neo or applet.  Several selected files also have no Preview section or heading.  Preserve file text, selectable contents, the twelve-line extract, loading and failure states, and the existing asynchronous task and cancellation identity.

All core and hardware files and other application UI sources must match build 162.  Preserve its permanent sidebar, indentation, filled keyboard symbol, toolbar choices, green status, consent, recovery, and working USB handling.  Update the bundled Inspector Help, release notes, technical guide, and manual checklist.

## Compile and build milestone

Review the small source diff before compiling.  Keep all 172 Swift tests, 55 validation fixtures, both pinned Mac compilers and app editions, all thirty-two real-window observations per host, all sidebar and toolbar checks, and the combined failing 120-second interface deadline.  Reuse the existing native file, Neo, AlphaWord, dictionary, and unknown-app Inspector captures in both appearances.  Add a capture after changing the same open Inspector from one file to two, for visual confirmation that the whole Preview section disappears immediately.  This gives 48 captures per host and 96 overall.  No mirrored unit test is needed for this conditional view.

Require native Apple Silicon execution of both exact canonical packages, signatures, architectures, minimum deployment, helpers, matching symbols, four independent artifact digests, twelve asset hashes, both Help books against tested source, and captured-image review.  Save the result in `releases/verification/2.0.5-163`, then provide a separate private Apple Silicon ZIP.  Earlier test copies, the public 1.5.1 and 2.0.4 releases, all twelve version tags, and the frozen legacy source remain preserved.

## Verified result

Source `92c5424251ef5ffc2e4f180b6a8bf4ec2454b2dc` passed [run 43756388436](https://github.com/koralatov/alphasync/actions/runs/43756388436) on 15 November 2026 at its first attempt.  Both Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 passed 172 Swift tests, all 55 fixtures, thirty-two browser observations, twelve sidebar width and size records, all toolbar modes, and both editions and helpers.  There were no Swift compiler warnings; six existing App Intents and signed-helper build notices remain per host.

Both exact canonical packages ran natively on Apple Silicon.  Four artifact digests, twelve asset hashes, bundle metadata, matching symbols, and both Help books passed independent verification.  Each Help book contains eighteen checked pages and 83 links, with twenty authored files matching tested source and a non-empty search index.

All 96 captured images were reviewed.  In both appearances on both hosts, one file retains Preview, and switching the same Inspector to two files removes the whole section immediately.  The Neo and all tested applets retain their header icons and More Information without a Preview heading or enlarged duplicate icon.  Browser, confirmation, Reader, and Settings captures retain their expected layout.  macOS 26 layer images still do not faithfully render Dark toolbar compositor materials; native names, visibility, bounds, and mode checks passed.  macOS 15 toolbar backgrounds render correctly in both appearances in this run.  Final screen-composited appearance remains a manual check.

The [permanent record](../releases/verification/2.0.5-163/verification.json) contains exact package hashes, image hashes and limits, native geometry, toolbar and sidebar records, and protected-release comparison.  Only `AuxiliaryViews.swift` changed among application sources; the complete preview task matches build 162.  The separate private Apple Silicon ZIP has SHA-256 `da831ad34a5f7aec63c6ed6b81050721e65c05ba9e9c1860ffd76036eaa71043`.  Only 1.5.1 and 2.0.4 remain public, with notes, eighteen assets, all twelve version tags, and frozen legacy source unchanged.  No new release or tag was created.

## Physical checks

With About showing **2.0.5 (163)**, keep Inspector open and select one file, several files, an applet, and the Neo.  Only one file should show Preview.  Headers and More Information remain available.  Return to a file and confirm its text loads normally, including an empty file and a refreshed file.  Repeat in Light and Dark Mode.  Continue the broader [manual checks](../tests/manual-checks.md) towards 2.1; the user’s general working report does not establish each untested operation, oldest runtime, Help Viewer, Login Items approval, final compositor appearance, or VoiceOver.
