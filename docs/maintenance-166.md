# Maintenance in build 166

Prepare private **2.0.5, build 166** under the user’s request to apply all three [simplification findings](simplification-review-165.md), make further useful improvements, build the result, and email the verified download link.  Preserve build 165, all earlier private copies, public 1.5.1 and 2.0.4, their eighteen assets and notes, all twelve version tags, and frozen legacy source.  No release publication or retirement is authorised.

## Clear eligibility

Use an early busy guard, a separate empty-selection branch, and one local selected-file array.  Preserve the full selection-count comparison, one-applet rule, writable checks, and chosen-applet scope.  An empty selection must never widen Clear to every applet or device.

Four regressions cover empty applets and device scope, read-only applets and files, missing or reconnected selected IDs, and confirmation or shutdown states.  The existing blocked-preparation test also requires Clear to remain unavailable while work is active.

## Explicit Find target

Require the native text view in `AppActions.find` and remove the unused responder-chain fallback.  The sole application caller already supplies its owned Reader view after checking the key window.  The user’s request resolves the API decision recorded in the earlier review: the helper no longer accepts an omitted or nil target.  This is a source-signature change in the exported UI module.

Keep weak ownership, exact-view cleanup, native window association, the key-window guard, and all native Find commands and Reader reload assertions.  Do not route Find to an arbitrary focused control.

## Shared snapshot publication

Use one small synchronous main-actor helper to assign a discovery result, combine connection issues, optionally invalidate the preview, and reconcile selection.  Each caller must state its preview policy explicitly.

Background attachment scans retain the current preview revision.  Explicit Refresh and failed-operation recovery invalidate it even when the selected file’s identity and size are unchanged.  Keep the epoch, busy, cancellation, and shutdown checks at the scan call site.  The helper contains no suspension point, new task, cache, or additional stored state.

Add regressions showing that an attachment scan retains a selected preview and that failed-operation recovery invalidates it without a device write.  Retain explicit Refresh, same-size replacement, announcement coalescing, scan cancellation, and operation-lifetime checks.

## Confirmation identity

A delayed button callback must act only on the confirmation whose request identity it captured.  Share a small identity-checked dismissal helper between Clear or Replace confirmation, its Cancel action, dictionary consent, and dictionary cancellation.

Four regressions cover a repeated completed Replace callback, an old change targeting a newer warning, an old dictionary warning after its source changed, and old dictionary consent reaching a subsequent Replace warning.  Obsolete callbacks must leave the current warning and notices alone and perform no additional write.  Current consent and cancellation must still work.

The service’s fresh-target checks, original-byte comparison, recovery copies, cancellation boundary, committed-write completion, and readback remain unchanged.

## Readable native confirmations

Make the destructive explanation and file names selectable using standard SwiftUI text selection.  Put each affected name on its own line, preserving commas within names.  Keep the existing scroll limit, native controls, Cancel first and initially focused, Escape, and no default button.

Extend the component checker with a three-file Clear warning, including a name containing a comma.  Exercise Return, keypad Enter, Space, and Escape in both appearances.  There are now eight safe confirmation records per host.

## Full non-publishing milestone

The expected Swift suite is **204 regressions**, comprising build 165’s 194 plus ten new tests.  Keep all **55 fixtures**, both pinned compilers and Mac hosts, both app editions and helpers, no Swift compiler warnings, exact byte-count formatting, thirty-two browser observations, twelve sidebar records, six toolbar records, and twelve Find observations per host.  Keep the combined failing 120-second native interface deadline.

Capture sixteen component views and fifteen window-scene views per appearance on each host, **124 images overall**, and review the final source’s images.  Earlier build 165 images do not establish the new result.  Require native execution of both exact canonical packages on Apple Silicon, independent artifact and asset hashes, architectures, deployment targets, signatures, hardened runtime, helper identities, matching symbols, and both Help books against tested source.

Store permanent evidence under `releases/verification/2.0.5-166`.  Retry only failed or unstarted jobs where safe, retaining successful results and recording every attempt accurately.  Never weaken a gate to get a green run.

## Completion and email

Save a separate `AlphaSync-2.0.5-166-macOS-13-apple-silicon.zip` only after all build, package, source, and captured-image checks pass.  Record verification as pending while any check or saving step remains unfinished.  Workspace unavailability does not justify claiming visual review, artifact inspection, or saving.

Once the verified separate copy is ready, email Mike through the CalxGPT Gmail account with the actual saved download link, a short change summary, checks performed, and the physical testing still required.  Use plain text, the user’s writing and signature rules, and the verified recipient.  Check for an already sent completion email before sending, then record success and pause the continuation task so it sends no repeat notification.

Physical Neo operations, actual VoiceOver speech, keyboard focus and editing, regional settings, final system-composited appearance, macOS 13, native Help Viewer, and Login Items approval remain manual.  Physical Neo testing comes next before deciding on stable 2.1.

## Apple references

- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Text views](https://developer.apple.com/design/human-interface-guidelines/text-views)
- [Native text selection](https://developer.apple.com/documentation/swiftui/view/textselection(_:))
