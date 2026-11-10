# Built-in Help review for 2.0.4

The review covers every shipping Help page and the commands, views, settings, and file operations in the Swift app. The guide now has seventeen authored pages and one generated licence page. It is available offline through Help → AlphaSync Help and ⌘?.

## Findings and changes

The old home page described a development version. Importing was mixed into copying, renaming had no task page, and recovery needed a clear procedure. Selection, the file filter, and backup scope were easy to confuse. Troubleshooting and support instructions were scattered. Small fixed text and links distinguished mainly by colour made the pages harder to read.

The revised home page groups tasks by purpose. Each task explains what it does, gives short steps using the actual command names, and links to related tasks. Terms such as applet and byte-order mark are explained where needed. Important limits and the consequences of replacement and clearing appear beside the relevant steps.

The guide explicitly explains these easily missed behaviours:

- Backup includes the chosen file types from every connected Neo. A row, applet, or Neo selection does not narrow it.
- Save to Mac with no files selected copies the current list. Clear All Files applies to one selected editable applet.
- New AlphaWord files are unbound. Renaming does not change their file-key assignment.
- Recovery is a manual import of saved text onto the correct file. Raw `.neo` and other applet `.xml` files are not text imports.
- A loaded reader is a snapshot. After reconnection, open a new reader from the refreshed list; its old request belongs to the old connection.
- Saved files survive an interrupted export or backup. An unfinished backup folder remains marked Incomplete.
- Requested recovery copies must succeed before a destructive change. Once writing starts, Quit waits for writing and verification.
- Automatic-opening intent and the actual macOS Login Items status are different. Destinations that become unavailable need attention in Settings.

## Function coverage

| Function or state | Help topic | Primary source reviewed |
| --- | --- | --- |
| Installation, editions, first connection, sidebar, multiple Neos, file filter | Get started | `MainView.swift`, `AppStore.swift`, `Preferences.swift` |
| Open Read-only, multiple readers, Find commands, selected and complete clipboard copying, fonts, retry, reader lifetime | Read and find text | `ReaderView.swift`, `AlphaSyncCommands.swift`, `AppStore.swift` |
| Selected and whole-list export, Finder dragging, retained existing files, partial export | Copy files to your Mac | `AppActions.swift`, `FileDrag.swift`, `AppStore.swift` |
| Add, Replace, file drops, dictionary review, resumed batches, unsupported applets | Add or replace text | `MainView.swift`, `AppStore.swift`, `DictionaryCodec.swift`, `ConfirmationViews.swift` |
| Shortcut-menu Rename, supported names, file-key binding | Rename a file | `MainView.swift`, `AuxiliaryViews.swift`, `AppStore.swift`, `FileCodec.swift` |
| Every-Neo backup scope, filter, destination, result counts, folder buttons, Stop, Incomplete, logs | Back up your Neo files | `BackupOperations.swift`, `MainView.swift`, `AuxiliaryViews.swift`, `Preferences.swift` |
| Saved readable and raw originals, manual restoration, destination, expiry, Trash | Restore text from a recovery copy | `BackupOperations.swift`, `AppStore.swift`, `AtomicFileStore.swift`, `Preferences.swift` |
| Clear one, several, or all files in one applet, warnings, Cancel, failed verification | Clear files | `MainView.swift`, `AlphaSyncCommands.swift`, `ConfirmationViews.swift`, `AppStore.swift` |
| File, applet, and Neo details, More Information, Preview, unavailable limits, Refresh | Inspect a file, applet, or Neo | `AuxiliaryViews.swift`, `AppStore.swift` |
| Every setting, defaults, saved folders, appearance, reader font | Change AlphaSync settings | `Preferences.swift`, `AuxiliaryViews.swift`, `ReaderView.swift`, `AppStore.swift` |
| Enable, approve, disable, missing helper, older standalone helper | Open AlphaSync when you connect a Neo | `Preferences.swift`, launcher entry point |
| Plain text, supported encodings, unsupported characters, names, converted sizes, memory, dictionary limits, opaque exports | Choose a text format | `TextFiles.swift`, `FileCodec.swift`, `DictionaryCodec.swift`, `FileOperations.swift` |
| File, View, Settings, Help, reader, Find, Close, Quit, focus, Cancel, Stop | Use keyboard shortcuts | `AlphaSyncCommands.swift`, `ConfirmationViews.swift`, `MainView.swift`, `ReaderView.swift` |
| About, installed-version notes, offline licence, GitHub, issue form, unsent contact message, diagnostics, Copy Link | Get help or report a problem | `AlphaSyncCommands.swift`, `AppMetadata.swift`, `AppActions.swift` |
| Connection failures, accessory approval, sleep, hidden files, disabled commands, missing destinations, partial operations, safe shutdown | Solve a connection or file problem | `AppStore.swift`, `DeviceService.swift`, `BackupOperations.swift`, `AlphaSyncApp.swift` |
| Disable automatic opening, finish work, quit, remove complete app, keep saved writing | Remove AlphaSync | `Preferences.swift`, app and launcher entry points |
| Original copyright, terms, disclaimer | Licence | `LICENSE`, `scripts/build-help.sh` |

Source names in this table identify the behaviour reviewed; use the repository search to locate each file. Standard macOS menu and window actions are covered where they help complete an AlphaSync task.

## Apple guidance applied

The review used Apple’s [Offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) and [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) guidance. Topics follow the user’s task, use familiar language and active instructions, match the interface, and provide meaningful links. Warnings appear before the relevant action. Short topics and related links keep detailed information available without putting it all on the home page.

Apple’s archived [Authoring Apple Help](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/ProvidingUserAssitAppleHelp/authoring_help/authoring_help_book.html) also informed the separation of overview, task, and problem-solving topics. Existing native Help integration and stable entry anchors are retained.

Pages declare their language, have a single main landmark and main heading, use ordered lists for procedures, and give the shortcut table a caption and column headings. A shared stylesheet uses the system font, relative sizes, readable line lengths, system Light and Dark colours, underlined links, and a visible keyboard-focus outline. Text wraps in narrow columns, including the original licence. The decorative app icon has empty alternative text.

These changes apply the guidance to this app. They do not constitute Apple certification or replace checks with Help Viewer and assistive technology.

## Build and verification

`scripts/build-help.sh` generates the offline licence from the unchanged original notice. It then runs `scripts/check-help.py` before the mandatory macOS `hiutil` search-index build. The Xcode project tracks the validator as a build input. An explicit `--skip-index` mode supports local static previews on systems without `hiutil`; shipping builds do not use that mode.

The validator checks local pages, assets, anchors, reachability from the home page, unique titles, heading order, language, metadata, main landmarks, descriptive links, offline resources, and the stable Help-menu entry points. It rejects active web content, references outside the book, and changes to the generated licence. App verification repeats these checks on the extracted packages before publication.

Thirteen disposable Help fixtures cover broken pages and fragments, orphan pages, duplicate anchors, empty links, remote resources, escaping the book, active content, lost Help entry points, a wrong book title, an altered licence, and the actual generator with the complete source book. Both release host jobs and the regression workflow run them alongside the existing release fixtures.

At the documented completion milestone, all thirteen Help fixtures and the existing forty-two release fixtures passed locally. The generated eighteen-page book passed validation of eighty-three links, local resources, and the unchanged licence. Shell syntax and generated-project review passed. Static rendering covered every page, with additional narrow and 200% text samples for importing, shortcuts, and the licence. Light and Dark palette samples were reviewed with explicit preview colours because the static renderer does not resolve macOS system colours. This checks layout and wrapping; it does not establish Help Viewer rendering. Record the exact successful Mac workflow and package evidence after publication.

Native Help Viewer navigation, indexed topic search, cached-book replacement after upgrading, keyboard focus, and VoiceOver remain manual checks on macOS. Static layout checks do not establish those results. Physical Neo transfers, real Login Items approval, and the macOS 13 minimum runtime also remain unverified.
