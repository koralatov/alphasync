# Performance and correctness in build 160

Prepare a private **2.0.5, build 160** from verified build 159.  The user requested performance, bug fixes, and code correctness only.  Keep both current editions, the native interface, the working USB packet handling, and the connected-window correction.  The planned stable release remains 2.1 for Apple Silicon.  This work does not authorise publication, retirement, or changes to frozen legacy source.

## Review and changes

| Area | Finding | Change |
| --- | --- | --- |
| Explicit connection retry | A refresh that discovered a stale handle removed it but waited for another click before reopening | Reopen once in the same explicitly requested retry; assign a new connection identity and keep automatic retry suppression |
| Backup cancellation | Stop could arrive after the final USB block, before decoding and saving that file | Check cancellation after reading and after conversion; retain completed files, the incomplete folder, and the cancelled log |
| Reader and Inspector | Text conversion returned to the main actor after the USB read | Decode on the existing serial device executor; validate file identity and cancellation before returning text |
| File lists | View and command updates repeatedly filtered and sorted the same immutable snapshot | Reuse the sorted list until devices, sidebar selection, or filter change |
| Read-only text | Unchanged SwiftUI updates reapplied the font, selection, and scroll position | Update the native text view only when its text or font changes; preserve selection and scrolling |
| Dictionary conversion | An unusably long word could grow a buffer to the full import size; encoding also filtered all words nineteen times | Retain only the 32-byte warning example and the actual word length; group valid words by length once |

Keep dictionary byte order, deduplication, offsets, word limits, omission warnings, exact-source consent, and unsupported-character checks unchanged.  The legacy decoder permits a gap before the first word section; do not add an unproven restriction during a maintenance pass.  Keep existing preflights, recovery copies, atomic file publication, committed-write completion, and strict readback verification.  The mode switch, USB buffers, packet sizes, timeouts, and protocol requests are unchanged.

The review also covered the serial executor, connection generations, attachment monitoring, shutdown, exports, temporary promises, backup logs, recovery retention, text import bounds, codecs, and command eligibility.  Avoid speculative protocol changes and broad refactoring.

## Full compile and build milestone

Review edits before execution.  Thirteen regressions extend the Swift suite from 157 to **170**: six service cases cover retry, stale identities, all decoded file types, missing files, and late cancellation; three store cases cover list invalidation; four dictionary cases cover literal legacy bytes, a full-size omitted word, length boundaries, and unsupported characters beyond the example prefix.

Extend the native component checks to exercise a scrolled preview, unchanged updates, font changes, and selection preservation.  Retain all twenty real-window observations in both appearances and the combined failing 120-second deadline.  Keep test preferences isolated, USB discovery disabled in the interface fixture, and test code out of shipping app targets.

Record a same-host comparison between 500 repeated sorts of a 64-file fixture and 500 warm-cache accesses.  Verify identical results.  Timing is diagnostic, with no flaky pass threshold.  This SwiftPM debug comparison is not a release-app benchmark or a claim about physical USB transfer speed.  Report other performance improvements by the work removed or moved off the main actor, rather than inventing speed percentages.

Require both pinned Mac compilers, all 170 Swift tests, all 55 Help and release fixtures, both app editions and helpers, native interfaces, signatures, architectures, hardened runtime, matching symbols, and native execution of both exact canonical downloads.  Independently verify four artifact digests, twelve asset hashes, and both Help books against tested source.  Inspect captured interfaces and retain the known macOS 26 compositor limitation explicitly.

Create a separate private Apple Silicon ZIP and permanent verification under `releases/verification/2.0.5-160` only after the checks pass.  Preserve all earlier candidates and evidence.  Compare protected releases, notes, every asset, all twelve version tags, frozen legacy source, and the latest-release state with the fresh baseline.

## Physical checks

Confirm 2.0.5 (160) in About on the M2 Air.  Repeat connection, first-row visibility, resizing, filters, scrolling, reading, and reconnection.  Check Refresh and Try Again after a recoverable failure.  Back up disposable files, stop during a read, and confirm earlier saved files remain available while the current file and log are marked accurately.

Repeat dictionary import, warning consent, read-only preview, selection, font changes, saving, drag export, rename, replacement, recovery, and readback verification using the [manual checklist](../tests/manual-checks.md).  Hosted checks cannot establish those physical outcomes, macOS 13 runtime behaviour, actual Login Items approval, native Help Viewer behaviour, or VoiceOver support.
