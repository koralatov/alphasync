# Simplification review after build 165

Reviewed source: `51f7cd2282b4415b58beaa7cbe3e2d0f5e16f570`.  Review the modern Swift application, core, hardware service, launcher, and native UI checks for simpler control flow, repeated work, ownership, and state.  The frozen legacy sources are outside this review.  Build and package results are recorded separately in [the build 165 record](../releases/verification/2.0.5-165/verification.json).

The review found one useful small cleanup and two conditional opportunities.  It did not identify a further correctness fix that requires changing the tested build.  No production source was changed by this review.  The examples below are proposals, not compiled or verified implementations.

## 1. Make Clear eligibility easier to read

[`AppStore.canClear`](../Sources/AlphaSyncUI/AppStore.swift) combines two different selection cases in a nested expression.  For an eligible non-empty selection, it also evaluates `selectedFiles` twice.  That property filters the current file list and allocates an array each time.

An early busy guard, a separate empty-selection branch, and one local selection value would make the existing rules explicit:

```swift
public var canClear: Bool {
    guard !busy else { return false }
    if selection.isEmpty {
        guard let applet = chosenApplet else { return false }
        return applet.canWrite && !applet.files.isEmpty
    }
    let selected = selectedFiles
    return selected.count == selection.count &&
        Set(selection.map(\.applet)).count == 1 &&
        selected.allSatisfy { applet(for: $0.id)?.canWrite == true }
}
```

Keep the complete selection-count comparison.  It rejects stale IDs that are absent from the visible inventory.  Keep the single-applet rule and each selected file’s writable-applet check.  An empty selection still means all files in the chosen writable applet; it must never widen to every applet or device.  Keep confirmation, fresh-target validation, recovery, and readback in the operation layer.

This is the first cleanup to consider at a future source milestone.  It removes one repeated filter for an eligible selection without introducing a cache or state.  There is no measured speed claim, and it cannot improve USB throughput.

Existing coverage includes `testClearRejectsAMixedWritableAppletSelectionWithoutAConfirmationOrWrite`, `testClearStillPreparesASelectionFromOneWritableApplet`, and the pending-confirmation busy-state check.  Before applying it, cover empty writable and read-only applets, absent or stale selected IDs, a device sidebar selection with no chosen applet, and busy or shutting-down states.  These should check eligibility and the absence of unintended device writes.

## 2. Consider removing the unused Find fallback

[`AppActions.find`](../Sources/AlphaSyncUI/AppActions.swift) accepts an optional text view and falls back to the application responder chain.  The only repository call is in [`ReaderFindContext.perform`](../Sources/AlphaSyncUI/ReaderFocus.swift), after it has obtained a specific live text view and checked that its window is key.

Making the target required would remove the optional branch and unused fallback.  Keep the key-window check, weak ownership, exact-view detach check, and registry.  The intended Reader must continue to receive Find when another control has focus.

This method is public in the exported `AlphaSyncUI` package product.  A required argument would narrow that API, so absence of another repository call alone is insufficient reason to change it.  Confirm the supported package API before removing the fallback, or leave this small method alone.  If changed, retain all twelve native Find observations per host and the actual menu-command checks before and after Reader reloading and late old-view cleanup.

## 3. Keep snapshot publication explicit unless duplication grows

[`AppStore`](../Sources/AlphaSyncUI/AppStore.swift) publishes a discovery result in the attachment scan, failed-operation recovery, and explicit Refresh.  Each assigns the devices and discovery issue, combines connection issues, and reconciles selection.  A small synchronous private helper could centralise those assignments.

The differences matter.  Explicit Refresh and failed-operation recovery invalidate the preview even when the file identity and size are unchanged.  A background attachment scan does not.  The scan also has epoch, busy, cancellation, and shutdown checks that must remain at its call site.  Assignment order and announcement coalescing must still produce one current connection message.

A helper would therefore need an explicit preview-invalidation policy and sequencing coverage.  That is a modest maintenance trade-off for only three short sites.  Leave the code explicit for now; revisit it if another publication path is added.  Do not introduce a general state framework or an asynchronous helper for these assignments.

Relevant regressions are `testExplicitRefreshInvalidatesPreviewWithoutChangingSelection`, `testReplacementInvalidatesPreviewWithTheSameFileIdentityAndSize`, `testErrorRecoveryDoesNotRetryModeSwitchFailures`, and `testRelatedConnectionAndFailureChangesProduceOneCurrentAnnouncement`.  A future extraction also needs to show that an ordinary background scan does not reread an unchanged preview and that an obsolete scan cannot replace a newer operation’s result.

## Safety boundaries to retain

| Area | Why the separate paths or checks remain |
| --- | --- |
| Device executor and connection identities | Serial access confines mutable transport state.  Fresh connection identities reject requests captured before reconnection.  Unstructured tasks or actor reentrancy would change that contract. |
| Cancellation and committed changes | Preparation can stop immediately before the first write.  A committed change must finish and verify.  A single generic cancellation wrapper would obscure that boundary. |
| Activity and confirmation state | A pending confirmation disables conflicting actions without claiming a transfer is running.  The busy and progress predicates have different meanings. |
| File panels and captured requests | SwiftUI can dismiss a panel before delivering its result.  Presentation Booleans and captured target identities cannot safely be collapsed. |
| Export and backup-log writes | Normal exports must not overwrite existing files.  A backup session may replace only its own known log.  Keep exclusive creation, ownership checks, no-follow rules, synchronisation, and recovery retention. |
| User-selected and internal file reads | A selected symlink to a regular text file and an internal metadata path have different trust rules.  Do not merge their readers by discarding `O_NOFOLLOW` protection. |
| Binary parsing and transfer buffers | Subtraction-based bounds avoid overflow.  Owned, normalised buffers avoid alignment, slice-index, and lifetime hazards.  Unsafe pointer shortcuts have no demonstrated benefit here. |
| Conversion | Character-map ordering, duplicate handling, wrapping, padding, dictionary offsets, limits, and ordering affect the actual device bytes.  Preserve independent wire fixtures. |
| Retry policies | Attachment monitoring, mode switching, and launching have different bounded retry rules.  A shared retry framework would hide those distinctions. |
| Toolbar updates | The controller’s `connected` input can trigger a SwiftUI update when the toolbar changes.  Its lack of a direct property read does not establish that deleting it preserves reconnection behaviour. |

Keep the existing file-list cache and locale-aware formatter reuse.  Do not add mutable caches for these small predicates, share mutable formatters across executors, or claim measured device performance from UI diagnostics.

## Outcome

Retain the verified build unchanged.  The Clear predicate is a worthwhile, contained cleanup for the next source milestone.  The Find change needs an API decision, and snapshot publication is clearer left explicit at its present size.  Any later implementation must use a new private build, preserve the relevant behavioural regressions and full package gates, and keep physical Neo testing separate from hosted verification before deciding on stable 2.1.

## Implemented follow-up

The user subsequently authorised all three findings.  Private build 166 implements the Clear predicate cleanup, explicit Find target, and shared snapshot publication with its distinct preview policies, together with obsolete-confirmation protection and selectable file details.  The [maintenance review](maintenance-166.md) and [verified record](../releases/verification/2.0.5-166/verification.json) retain the implementation, regression coverage, completed checks, and physical testing still required.
