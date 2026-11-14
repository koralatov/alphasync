# USB comparison with 1.5.1

The user requested a full USB comparison after the M2 MacBook Air connection failures. This audit compares unpublished 2.0.5, build 157 with frozen 1.5.1, commit `6cb821c9ab8073ff950414952bf2480eb4638c5d`. Corrections use build 158 and retain the earlier mode-switch, buffer, and System applet fixes. No physical Neo is available to the hosted checks, so passing them cannot establish flawless hardware operation.

## Reference and findings

The references are frozen [ASDeviceFactory.cc](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASDeviceFactory.cc), [ASDevice.cc](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASDevice.cc), [ASMessage.h](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASMessage.h), and [ASDevice.h](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASDevice.h). Compare executable request layouts rather than relying on header comments alone.

| Area | Working legacy behaviour | Swift comparison and decision |
| --- | --- | --- |
| Discovery | Vendor `081e`; keyboard product `bd04`; transfer product `bd01`. | Matches. Discover the keyboard USB device directly, without reading keystrokes. |
| Keyboard handoff | First configuration descriptor’s actual value, then five one-byte reports `e0` to `e4`. | Matches. Request type `21`, request `09`, value `0200`, index `0001`, length `0001`, through public IOUSBHost endpoint-zero calls. |
| Transfer interface | Open the interface and choose its first bulk input and output pipes. | Matches endpoint selection. IOUSBHost takes endpoint addresses instead of legacy pipe ordinals. Do not reconfigure an already active transfer interface. |
| Hello | Ten attempts; write `01`, read at most eight bytes, require a two-byte big-endian version of at least `0230`. Reads and writes allow 100 ms. Reset and wait 100 ms between failures. | Build 157 tried three times with 500 ms probes. Build 158 restores ten 100 ms probes. A valid unsupported version fails immediately, as in legacy. Recovery reset remains bounded at 500 ms. |
| Dialogue | Reset `3f ff 00 72 65 73 65 74`, select System with `3f 53 77 74 63 68 00 00`, expect `Switched`, and reset on exit. | Matches, including cleanup after failure. Only hello is retried; file writes are never replayed automatically. |
| Bulk packets | Request `min(8, remaining)` bytes, with an unpadded final tail. Empty writes send no packet. | Matches. Hello intentionally accepts its two-byte actual count. |
| Short reads | Stop at a short packet. An exact-length read fails if its total is incomplete. | Build 157 could join a short packet to a later packet. Build 158 rejects the incomplete packet without consuming its successor. An exact requested tail still succeeds. |
| Framing | Eight-byte commands; modulo-256 command checksum; big-endian fields; blocks up to 1,024 bytes with a modulo-65,536 checksum. | Matches. Retain strict ranges, checksums, and advertised-length validation. |
| File read | `1c`: size at bytes 1–3, index at byte 4, applet at bytes 5–6. `10` gets each `4d` block or `4e` end marker. | Matches, including multiple blocks and empty dictionary files. |
| File write | `1f`: index at byte 1, size at bytes 2–4, applet at bytes 5–6. `02` receives `42`, data receives `43`, and `15` confirms with `51`. | Matches. Retain original-file preflights, recovery copies, and complete readback. |
| Attributes and create | `13` reads attributes; `1d` stages 40 bytes; `1e` commits the index at byte 4 and applet at bytes 5–6 before new contents. | Matches. Independent tests cover creation and rename, including preserved password and allocation bytes. |
| Enumeration | System information is separate from file collections. | Retain build 157’s correction: no System file-count query, with strict failures for real file errors. |
| Timeouts | Default 20 seconds per legacy pipe request. | Intentionally retain a monotonic 20-second budget across each Swift packet sequence or block, bounding stalled operations instead of renewing the full allowance for every eight bytes. |
| Transfer error | Clear the failed endpoint’s stall and return the error without replaying a write. | Matches through public `clearStall()`. Preserve the original error if recovery also fails. Invalid caller bounds do not touch a pipe. |
| Lifetime | Close and release USB objects on every exit. | Retain serial ownership, generation checks, and close on failed discovery. Build 158 also aborts both pipes before interface release during final deinitialisation. Close remains idempotent if either abort fails. |

Apple’s [clearStall documentation](https://developer.apple.com/documentation/iousbhost/iousbhostpipe/clearstall()) confirms that this public method clears the halt, handles an intermediate hub’s transaction buffer when needed, aborts pending endpoint I/O, and resets its data toggle. Retain this API rather than adding a private USB reset or driver extension.

## Independent regressions

Twenty-four new tests extend the Swift suite from 131 to 155. Twelve exercise the actual hardware transport path through injected endpoint transfers: owned reads, sliced writes, eight-byte chunks and tails, empty writes, partial output, failure after an accepted packet, preserved errors, invalid counts and timeouts, explicit close, abort failures, closed-handle rejection, and final cleanup. The thin native adapter calls the same public IOUSBHost selectors.

Seven protocol checks cover the tenth probe, unsupported versions, short command and payload packets, valid tails, empty packets, and oversized replies. The existing bounded-failure test now requires ten attempts and final reset.

Five file tests use literal legacy layouts and independent checksums. They cover a 2,304-byte replacement in three blocks, new index 9 with attributes before contents, metadata-only rename, an empty dictionary without a data block, and corrupted readback reported as a possible change without replay. Earlier mode-switch, buffer, snapshot, cancellation, and recovery tests remain required.

## Compile and build milestone

Tests are deferred until these edits and their review are complete. This is the full non-publishing milestone for version 2.0.5, build 158. Require both pinned Mac compilers, all 155 Swift tests and 55 fixtures, both app editions and helpers, native interface checks, matching symbols, Help, signatures, architectures, and native execution of the exact canonical downloads. Independently check artifact digests and all twelve assets. Record the actual outcome after execution, including infrastructure failures. Do not weaken runner or publication gates.

Keep 1.5.1 and 2.0.4 public, preserve all twelve tags and the frozen legacy branch, and retain builds 155–157 and their evidence. This request does not publish 2.0.5.

The first audited source, `97d26d838ed6ce02eb7fc9d4a3665eadda54d6fe`, passed all 155 Swift tests, 55 fixtures, both native host builds, exact-package execution, and independent hashes in [run 43646830824](https://github.com/koralatov/alphasync/actions/runs/43646830824). The newer compiler reported one repeated weak-variable warning in the lifetime regression. Remove that redundant reference: the abort and release counters already prove deinitialisation occurred. Repeat the full milestone for the final source before handover; the app’s USB implementation is unchanged by this test correction.

## Physical checks still required

Use the same Neo, cable, adapter, and M2 Air that work with 1.5.1. Quit each app before opening the other. Preserve files with a verified backup before trying a write.

1. Confirm version 2.0.5, build 158 in About. Launch before attachment, then launch with the Neo already attached. Check manager recognition, the complete file list, and opening an existing AlphaWord file.
2. Save and back up files to the Mac. Compare contents with known-good 1.5.1 copies, including non-ASCII text and files larger than 1,024 bytes.
3. Disconnect while idle, reconnect, and repeat. Test Try Again after a failed connection and the usual hub or adapter. Confirm stale selections cannot reach a newly attached device.
4. With a disposable file and its recovery copy, test create, rename, replace, and readback. Test an empty dictionary only if intended. An interrupted write must report a possible change and retain its recovery copy.
5. Record the affected macOS 14.7.1 M2 Air first, then available Intel and Apple Silicon Macs, including macOS 13 and the current supported macOS. Hosted builds and native app execution do not replace these device checks.

Do not mark the hardware problem resolved until actual enumeration and transfers succeed on the affected setup.
