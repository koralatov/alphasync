# Neo recognises AlphaSmart Manager but returns 0x90

On 11 November 2026, the user reported that the Neo recognises AlphaSmart Manager on its screen when attached to the M2 MacBook Air, while AlphaSync shows a connection failure with reply 0x90. This follows the supplied build 156 test copy. The screenshot itself does not show the app version. It establishes an error reply, not successful file enumeration or transfer.

## Legacy comparison

The frozen 1.5.1 source provides the reference:

- [ASMessage.h](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASMessage.h) identifies 0x90 as a parameter rejection. Its example for a resource query to applet 0 shows that reply.
- [ASDevice.cc](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Driver/ASDevice.cc) sends 0x1b with selector 1 and the applet ID to obtain the file count and RAM use. It treats 0x90 from a file-attributes query as an absent entry.
- [ASDeviceNode.mm](https://github.com/koralatov/alphasync/blob/v1.5.1/AlphaSync/Application/ASDeviceNode.mm) normally lists AlphaWord and the dictionary. The System applet supplies system information separately.

The Swift snapshot instead queried file counts for every applet, including System. A rejected query aborted the entire connection before any files could appear. The former command-list simulations never exercised this complete snapshot path.

## Build 157 correction

Keep the earlier USB handoff and owned-buffer corrections. Do not send file-count or file-attributes requests to System. For another read-only applet, tolerate only a rejected resource query followed by confirmation that file index 1 is absent. If it has a file, has a different error, or returns a damaged frame, keep the error. AlphaWord and the dictionary retain strict file-count and attributes checks, including rejection of an incomplete advertised list. Existing write preflights, recovery, and verification remain required.

Rejected replies now retain the command and applet ID in a typed error and readable diagnostic. No file contents, passwords, or private report identifiers are logged.

Eight new regressions use request layouts and responses independent of the production NeoMessage encoder. They cover a full snapshot with System, eight AlphaWord files, the dictionary, and a fileless read-only applet; a file read after connection; and failures for writable applets, other replies, unexpected real files, missing advertised attributes, and corrupt checksums. Every case checks that connection and read preparation send no file-writing command.

## Compile and build milestone

Tests were deferred while editing. This is the full non-publishing compile and build milestone for version 2.0.5, build 157. Require both host jobs, all 131 Swift tests and 55 fixtures, both app editions and helpers, native interfaces, Help, package hashes, signatures, architectures, matching symbols, and native execution of the exact downloaded packages. Preserve the existing Mac runner gates. Record infrastructure failures separately if a job cannot receive a runner. Do not publish, replace earlier test copies, move tags, or change the frozen legacy source.

Physical confirmation still requires the M2 Air to show the file list and open a real Neo file. The manager recognition and a passing fixture alone do not establish that result.

## Verified private test build

On 14 November 2026, [run 43642608956](https://github.com/koralatov/alphasync/actions/runs/43642608956) passed for exact source `12e9e29d8e1302265dfb5d8e1d03452df35ed44d`. Intel with Xcode 26.6 and Apple Silicon with Xcode 16.4 each passed all 131 Swift regressions, including the eight snapshot wire cases, all 55 fixtures, both app and helper builds, and native interface checks, without compiler warnings. The separate download-verification job ran both canonical app editions natively on Apple Silicon and checked architectures, signatures, hardened runtime, metadata, and matching symbols. Publication was skipped.

The four downloaded artifact digests matched GitHub’s records. Independent verification of all twelve assets matched the native Apple Silicon manifest. Both Help books passed eighteen-page and eighty-three-link checks, retained their original licence and nonempty indexes, and matched all twenty authored files from the tested source. The [permanent record](../releases/verification/2.0.5-157/verification.json) retains this evidence. A separate Apple Silicon ZIP is prepared for private handover, preserving builds 155 and 156.

Only 1.5.1 and 2.0.4 remain public. Their notes and asset metadata, all twelve tags, and the frozen legacy branch are unchanged. The next physical check is to open build 157, confirm that version in About, reconnect the Neo, and open an existing file. Do not mark actual Neo operation as passed until that result is reported.
