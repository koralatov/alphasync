# Unbuilt corrections after build 167

On 18 November 2026, the user reported that an accidental file drop created a new Neo file and that Use Selection for Find did not work.  The user requested source fixes without a build.  Both corrections are committed on master; they are not present in the saved build 167 ZIP.

## Confirm additions from drops

The build 167 table destination inferred its action from the current file selection.  An empty selection let a drop add a named file immediately.  Commit `9c4e00ea03e553e2d620ed701667b6a30771a976` initially removed the table destination.  The follow-up restores background drops into an editable applet’s file list with an explicit Add File or Add Files confirmation.

The prompt lists the source names and destination, with Cancel initially focused and no default add action.  The request captures the connection and applet when the drop occurs.  File selection cannot turn it into a replacement, and changing the sidebar cannot redirect it.  Cancel and obsolete callbacks perform no writes.  The existing import validates the captured applet and handles file reading, conversion, and dictionary warnings after consent.

A single drop onto a writable file’s name still uses the Replace warning.  The explicit Import command retains its existing behaviour.  Deferred regressions cover cancellation, obsolete confirmation, a confirmed batch with a changed sidebar, rejection without an editable applet, and the existing row replacement and rejection paths.

## Find command removal

Remove Use Selection for Find and its Command-E shortcut from the application commands.  Keep Find, Find Next, and Find Previous, native Find bars, exact Reader ownership, key-window guards, and lifecycle cleanup unchanged.  The deferred native checker now requires those three commands and explicitly rejects the removed menu item at every existing Find stage.  Help describes typing or pasting search text instead.

Correction: `1f31bdea06659fa5414e181406de56ae2cfab0b2`.

## Removing an unwanted named file

AlphaSync’s Clear command empties file contents; it does not delete a named file.  A named AlphaWord file is not necessarily assigned to one of the eight file keys.  No new deletion protocol or device write has been added by this correction.

After preserving any wanted text and disconnecting the Neo from USB, use AlphaWord’s Ctrl-D deletion list.  Select the unwanted named file carefully, press Enter, and confirm with Y only after checking the selected name.  N cancels.  Avoid confusing a named file such as ‘7’ with the normal File 7 workspace.  Deletion is permanent.

This procedure is documented in Renaissance’s [NEO 1 and NEO 2 manual, printed page 57](https://uk.renaissance.com/wp-content/uploads/2010/12/neo-user-manual.pdf) and [NEO 2 manual, printed page 39](https://uk.renaissance.com/wp-content/uploads/2013/08/NEO2-User-Manual.pdf).

## Verification status

Code and diffs were reviewed only.  No compilation, automated tests, native checks, package generation, new ZIP, or email occurred.  All routine commits use `[skip ci]`.  Keep the verified build 167 package and its historical evidence intact, with the newly reported issues recorded separately from its completed hosted checks.

When the user requests a build, use a fresh build number, at least 168, and run the full applicable milestone against that exact source.  Verify confirmed additions and confirmed row replacement on the actual interface, the remaining Find commands and Reader reload checks, Help, and all established package and data-integrity gates.  Do not claim that the saved build 167 contains these fixes.
