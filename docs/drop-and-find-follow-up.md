# Unbuilt corrections after build 167

On 18 November 2026, the user reported that an accidental file drop created a new Neo file and that Use Selection for Find did not work.  The user requested source fixes without a build.  Both corrections are committed on master; they are not present in the saved build 167 ZIP.

## Replacement-only drops

The file table had a drop destination that could infer an import target from the sidebar and current selection.  With no selected file, it used the creation branch and added an unbound named file immediately.  That broad destination is removed.  The drop entry point now requires exactly one source URL and an explicit existing writable Neo file.  Missing targets, untargeted drops, and multiple files are rejected before changing selection or scheduling an operation.

A valid row drop still captures its named target before starting asynchronous work and opens the existing Replace confirmation.  It must write nothing before consent.  The explicit Import command retains intentional new-file creation; selecting a file retains replacement.  Recovery, fresh-target checks, original-byte comparison, cancellation, and committed-write completion are unchanged.

Four deferred regressions cover untargeted drops under device and applet scopes with empty, single, and multiple selections; multiple source files; absent or read-only targets; and empty source lists.  The existing row-target test now also confirms zero writes before consent, one verified replacement after consent, unchanged file identities, and preserved bytes in the other file.  These additions take the planned Swift suite from 212 to 216, but no tests have run for this source.

Correction: `9c4e00ea03e553e2d620ed701667b6a30771a976`.

## Find command removal

Remove Use Selection for Find and its Command-E shortcut from the application commands.  Keep Find, Find Next, and Find Previous, native Find bars, exact Reader ownership, key-window guards, and lifecycle cleanup unchanged.  The deferred native checker now requires those three commands and explicitly rejects the removed menu item at every existing Find stage.  Help describes typing or pasting search text instead.

Correction: `1f31bdea06659fa5414e181406de56ae2cfab0b2`.

## Removing an unwanted named file

AlphaSync’s Clear command empties file contents; it does not delete a named file.  A named AlphaWord file is not necessarily assigned to one of the eight file keys.  No new deletion protocol or device write has been added by this correction.

After preserving any wanted text and disconnecting the Neo from USB, use AlphaWord’s Ctrl-D deletion list.  Select the unwanted named file carefully, press Enter, and confirm with Y only after checking the selected name.  N cancels.  Avoid confusing a named file such as ‘7’ with the normal File 7 workspace.  Deletion is permanent.

This procedure is documented in Renaissance’s [NEO 1 and NEO 2 manual, printed page 57](https://uk.renaissance.com/wp-content/uploads/2010/12/neo-user-manual.pdf) and [NEO 2 manual, printed page 39](https://uk.renaissance.com/wp-content/uploads/2013/08/NEO2-User-Manual.pdf).

## Verification status

Code and diffs were reviewed only.  No compilation, automated tests, native checks, package generation, new ZIP, or email occurred.  All routine commits use `[skip ci]`.  Keep the verified build 167 package and its historical evidence intact, with the newly reported issues recorded separately from its completed hosted checks.

When the user requests a build, use a fresh build number, at least 168, and run the full applicable milestone against that exact source.  Verify background-drop rejection and confirmed row replacement on the actual interface, the remaining Find commands and Reader reload checks, Help, and all established package and data-integrity gates.  Do not claim that the saved build 167 contains these fixes.
