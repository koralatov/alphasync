#import <Cocoa/Cocoa.h>
#include <math.h>
#include <stdio.h>

// Used only by --smoke-test.  These cached sample rows never access a NEO.
@interface ASInterfaceRows : NSObject <NSOutlineViewDataSource>
@property (retain) NSArray* roots;
@property (assign) id delegate;
@end

@implementation ASInterfaceRows
- (void)dealloc { [_roots release]; [super dealloc]; }
- (BOOL)respondsToSelector:(SEL)selector
{
    return [super respondsToSelector:selector] || [_delegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector
{
    return [_delegate respondsToSelector:selector] ? _delegate : [super forwardingTargetForSelector:selector];
}
- (void)outlineViewSelectionDidChange:(NSNotification*)notification
{
    // Sample rows have no device attributes.  Do not ask the real Inspector to read them.
    (void)notification;
}
- (NSInteger)outlineView:(NSOutlineView*)view numberOfChildrenOfItem:(id)item
{
    (void)view;
    return (NSInteger)[(item ? [item valueForKey:@"children"] : _roots) count];
}
- (id)outlineView:(NSOutlineView*)view child:(NSInteger)index ofItem:(id)item
{
    (void)view;
    return [(item ? [item valueForKey:@"children"] : _roots) objectAtIndex:(NSUInteger)index];
}
- (BOOL)outlineView:(NSOutlineView*)view isItemExpandable:(id)item
{
    return [self outlineView:view numberOfChildrenOfItem:item] > 0;
}
@end

static void requireInterface(BOOL passed, NSString* reason)
{
    if (!passed) [NSException raise:@"InterfaceCheck" format:@"%@", reason];
}

static void checkInheritedAppearance(NSView* view)
{
    requireInterface([view appearance] == nil, @"A view overrides the system appearance.");
    requireInterface(![NSStringFromClass([view class]) hasPrefix:@"AS"], @"A custom view replaces an AppKit component.");
    for (NSView* child in [view subviews]) checkInheritedAppearance(child);
}

static CGFloat luminance(NSColor* colour)
{
    NSColor* rgb = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    requireInterface(rgb != nil, @"A colour cannot be checked for contrast.");
    CGFloat components[] = {[rgb redComponent], [rgb greenComponent], [rgb blueComponent]};
    for (int i = 0; i < 3; ++i)
        components[i] = components[i] <= 0.04045 ? components[i] / 12.92 : pow((components[i] + 0.055) / 1.055, 2.4);
    return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2];
}

static void checkContrast(NSColor* text, NSColor* background)
{
    CGFloat first = luminance(text), second = luminance(background);
    CGFloat ratio = (MAX(first, second) + 0.05) / (MIN(first, second) + 0.05);
    requireInterface(ratio >= 4.5, [NSString stringWithFormat:@"Text contrast is too low: %.2f.", ratio]);
}

static void captureWindow(NSWindow* window, NSString* directory, NSString* name)
{
    [window makeKeyAndOrderFront:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    [window displayIfNeeded];
    NSString* path = [directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    // Window Server captures include composited native materials such as Liquid
    // Glass, which cacheDisplayInRect cannot always render accurately.
    NSTask* capture = [[[NSTask alloc] init] autorelease];
    [capture setExecutableURL:[NSURL fileURLWithPath:@"/usr/sbin/screencapture"]];
    [capture setArguments:@[@"-x", @"-o", @"-l", [NSString stringWithFormat:@"%ld", (long)[window windowNumber]], path]];
    NSError* captureError = nil;
    if ([capture launchAndReturnError:&captureError])
    {
        [capture waitUntilExit];
        if ([capture terminationStatus] == 0 && [[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            printf("Captured %s with Window Server.\n", [name UTF8String]);
            return;
        }
    }
    fprintf(stderr, "Window capture unavailable for %s; using the AppKit bitmap fallback.\n", [name UTF8String]);
    NSView* frame = [[window contentView] superview];
    [frame layoutSubtreeIfNeeded];
    NSBitmapImageRep* bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
    requireInterface(bitmap != nil, @"A window could not be rendered.");
    [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
    NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSError* error = nil;
    requireInterface([png writeToFile:path options:NSDataWritingAtomic error:&error], [error localizedDescription] ?: @"A screenshot could not be saved.");
}

static void checkPreferenceLayout(id preferences)
{
    NSView* content = [[preferences window] contentView];
    [content layoutSubtreeIfNeeded];
    for (NSString* key in @[@"outletFilterOption", @"outputFormatField", @"backupFolderPath", @"chooseFolderButton",
                             @"outletAutoRun", @"automaticLaunchStatusField", @"loginItemsButton"])
    {
        NSView* view = [preferences valueForKey:key];
        if ([view isHiddenOrHasHiddenAncestor]) continue;
        NSRect frame = [view convertRect:[view bounds] toView:content];
        requireInterface(NSContainsRect(NSInsetRect([content bounds], -1, -1), frame),
                         [NSString stringWithFormat:@"The Preferences control %@ is outside the window.", key]);
    }
    NSTextField* status = [preferences valueForKey:@"automaticLaunchStatusField"];
    NSSize needed = [[status cell] cellSizeForBounds:NSMakeRect(0, 0, NSWidth([status bounds]), 10000)];
    requireInterface(NSHeight([status bounds]) >= needed.height - 1, @"The automatic-launch status is clipped.");
    NSButton* choose = [preferences valueForKey:@"chooseFolderButton"];
    CGFloat width = NSWidth([choose alignmentRectForFrame:[choose frame]]);
    requireInterface(width <= [choose intrinsicContentSize].width + 1,
                     [NSString stringWithFormat:@"The folder button is stretched (alignment %.1f, intrinsic %.1f).", width, [choose intrinsicContentSize].width]);
}

static void checkPreferences(id controller)
{
    id preferences = [controller valueForKey:@"preferenceController"];
    NSWindow* window = [preferences window];
    NSPopUpButton* filter = [preferences valueForKey:@"outletFilterOption"];
    NSPathControl* path = [preferences valueForKey:@"backupFolderPath"];
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [window makeKeyAndOrderFront:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    requireInterface([window isMemberOfClass:[NSWindow class]], @"Preferences is not a standard Mac window.");
    requireInterface([filter selectedTag] == [defaults integerForKey:@"FilterMode"], @"Preferences did not load the saved file filter.");
    requireInterface([[[path URL] path] isEqualToString:[defaults stringForKey:@"BackupFolder"]], @"Preferences did not load the saved backup folder.");
    requireInterface([window initialFirstResponder] == filter, @"The initial keyboard focus is not the file filter.");
    if ([NSApp isFullKeyboardAccessEnabled])
        requireInterface([window makeFirstResponder:filter], @"The file filter cannot receive keyboard focus.");
    checkPreferenceLayout(preferences);

    // Exercise the system folder chooser in the manual checklist.  Its remote
    // service can time out on unattended runners before a sheet is available.
    [preferences close];
    [preferences showWindow:nil];
    requireInterface([preferences window] == window && [filter selectedTag] == [defaults integerForKey:@"FilterMode"],
                     @"Closing and reopening Preferences lost its settings.");
}

static void checkBackupLayout(NSWindowController* backup)
{
    NSView* content = [[backup window] contentView];
    [content layoutSubtreeIfNeeded];
    checkInheritedAppearance(content);
    NSMutableArray* views = [NSMutableArray arrayWithObject:content];
    while ([views count])
    {
        NSView* view = [[[views lastObject] retain] autorelease];
        [views removeLastObject];
        if ([view isHiddenOrHasHiddenAncestor]) continue;
        [views addObjectsFromArray:[view subviews]];
        if (![view isKindOfClass:[NSControl class]]) continue;
        NSRect frame = [view convertRect:[view bounds] toView:content];
        requireInterface(NSContainsRect(NSInsetRect([content bounds], -1, -1), frame), @"A backup control is outside the sheet.");
        if ([view isKindOfClass:[NSTextField class]])
        {
            NSTextField* field = (NSTextField*)view;
            NSSize needed = [[field cell] cellSizeForBounds:NSMakeRect(0, 0, NSWidth([field bounds]), 10000)];
            requireInterface(NSHeight([field bounds]) >= needed.height - 1, @"Backup text or a folder location is clipped.");
            if ([[field identifier] isEqualToString:@"backup-location"])
                requireInterface([field isSelectable], @"A backup location cannot be copied.");
        }
    }
    for (NSString* key in @[@"openBackupButton", @"outletStopDoneButton"])
    {
        NSButton* button = [backup valueForKey:key];
        if ([button isHiddenOrHasHiddenAncestor]) continue;
        requireInterface(NSWidth([button alignmentRectForFrame:[button frame]]) <= [button intrinsicContentSize].width + 1,
                         @"A backup button is stretched.");
    }
}

static void sampleBackupResult(NSWindowController* backup, NSUInteger total, NSUInteger processed, NSUInteger failed,
                               NSUInteger devices, NSArray* paths, NSString* status)
{
    // Only the completion state is simulated.  Do not copy files or open Finder.
    NSMutableArray* items = [NSMutableArray arrayWithCapacity:total];
    for (NSUInteger index = 0; index < total; ++index) [items addObject:[NSNull null]];
    [backup setValue:items forKey:@"backupItems"];
    [backup setValue:@(processed) forKey:@"nextBackupItem"];
    [backup setValue:@(failed) forKey:@"failedFiles"];
    [backup setValue:@(devices) forKey:@"backupDeviceCount"];
    [backup setValue:[NSMutableArray arrayWithArray:paths] forKey:@"backupSessionPaths"];
    [backup performSelector:NSSelectorFromString(@"stopBackup:status:") withObject:@"Cancelled" withObject:status];
    checkBackupLayout(backup);
}

static void checkBackupResults(NSWindowController* backup)
{
    NSArray* paths = @[@"/Users/Example/Documents/AlphaSync/My NEO/2026-11-08"];
    sampleBackupResult(backup, 8, 8, 0, 1, paths, @"complete");
    NSTextField* title = [backup valueForKey:@"outletFilesRemaining"];
    NSTextField* summary = [backup valueForKey:@"outletBackupItem"];
    NSButton* open = [backup valueForKey:@"openBackupButton"];
    NSButton* done = [backup valueForKey:@"outletStopDoneButton"];
    requireInterface([[title stringValue] isEqualToString:@"Backup complete"] &&
                     [[summary stringValue] containsString:@"copies of 8 files from your NEO"], @"Successful backup wording changed.");
    requireInterface(![open isHidden] && [open target] == backup && [open action] == NSSelectorFromString(@"actionOpenBackupFolders:"),
                     @"The backup folder button is not connected.");
    requireInterface([[done title] isEqualToString:@"Done"] && [[done keyEquivalent] isEqualToString:@"\r"], @"Done is not the default completion button.");
    NSStackView* locations = [backup valueForKey:@"backupLocationsView"];
    NSTextField* location = [[locations arrangedSubviews] lastObject];
    requireInterface([[location toolTip] isEqualToString:paths[0]] && [[location stringValue] isEqualToString:paths[0]],
                     @"The completion sheet lost its dated backup location.");

    sampleBackupResult(backup, 1, 1, 0, 1, paths, @"complete");
    requireInterface([[summary stringValue] containsString:@"a copy of 1 file"], @"A single-file backup has the wrong wording.");
    sampleBackupResult(backup, 8, 8, 2, 1, paths, @"complete");
    requireInterface([[title stringValue] isEqualToString:@"Backup incomplete"] &&
                     [[summary stringValue] containsString:@"saved 6 of 8 files"] &&
                     [[summary stringValue] containsString:@"2 files could not be backed up"], @"Failed files are not explained.");
    sampleBackupResult(backup, 8, 3, 0, 1, paths, @"cancelled");
    requireInterface([[title stringValue] isEqualToString:@"Backup stopped"] && [[summary stringValue] containsString:@"5 files were not copied"],
                     @"A stopped backup is labelled complete.");
    sampleBackupResult(backup, 8, 1, 1, 1, @[], @"failed");
    requireInterface([open isHidden] && [locations isHidden], @"A backup without a folder offers to open one.");
    sampleBackupResult(backup, 0, 0, 0, 0, @[], @"complete");
    requireInterface([[title stringValue] isEqualToString:@"No files to back up"] && [open isHidden], @"An empty backup claims files were saved.");
    [backup performSelector:NSSelectorFromString(@"showBackupProgress")];
    requireInterface([open isHidden] && [locations isHidden] && [[done title] isEqualToString:@"Stop"], @"Starting another backup left its old result visible.");
    checkBackupLayout(backup);
    puts("Backup completion, failure counts, cancellation, empty backups, folder actions, and native layout passed.");
}

static void captureBackupResults(NSWindowController* backup, NSString* directory, NSString* mode)
{
    NSArray* paths = @[@"/Users/Example/Documents/AlphaSync/My NEO/2026-11-08"];
    sampleBackupResult(backup, 8, 8, 0, 1, paths, @"complete");
    CGFloat shortHeight = NSHeight([[backup window] frame]);
    captureWindow([backup window], directory, [mode stringByAppendingString:@"-backup-complete"]);
    sampleBackupResult(backup, 8, 8, 2, 1, paths, @"complete");
    captureWindow([backup window], directory, [mode stringByAppendingString:@"-backup-incomplete"]);
    NSArray* longPaths = @[
        @"/Users/Example/Documents/Writing and notes/AlphaSmart NEO backups/An unusually long backup folder name/My first NEO/2026-11-08",
        @"/Users/Example/Documents/Writing and notes/AlphaSmart NEO backups/An unusually long backup folder name/My second NEO/2026-11-08 (1)"
    ];
    sampleBackupResult(backup, 16, 16, 0, 2, longPaths, @"complete");
    requireInterface(NSHeight([[backup window] frame]) > shortHeight, @"The backup sheet did not grow for multiple long locations.");
    requireInterface([[[backup valueForKey:@"outletBackupItem"] stringValue] containsString:@"from 2 NEOs"] &&
                     [[[backup valueForKey:@"backupLocationsView"] arrangedSubviews] count] == 3 &&
                     [[[backup valueForKey:@"openBackupButton"] title] isEqualToString:@"Open Backup Folders"], @"Multiple NEO backup locations are missing.");
    captureWindow([backup window], directory, [mode stringByAppendingString:@"-backup-locations"]);
    [backup performSelector:NSSelectorFromString(@"showBackupProgress")];
}

static void capturePreferenceStatus(id controller, NSString* directory, NSString* mode)
{
    id preferences = [controller valueForKey:@"preferenceController"];
    NSPathControl* path = [preferences valueForKey:@"backupFolderPath"];
    NSURL* originalFolder = [[path URL] retain];
    id originalError = [[controller valueForKey:@"automaticLaunchError"] retain];
    @try
    {
        // Display samples only.  Do not alter saved preferences or login-item registration.
        [path setURL:[NSURL fileURLWithPath:@"/Users/Example/Documents/Writing and notes/AlphaSmart NEO backups/An unusually long backup folder name" isDirectory:YES]];
        [controller setValue:@"The system could not register the automatic-launch helper.  Check the app’s location and permissions, then try again.  If approval is needed, open Login Items Settings and allow AlphaSync to run in the background."
                      forKey:@"automaticLaunchError"];
        [preferences performSelector:NSSelectorFromString(@"refreshAutomaticLaunchStatus:") withObject:nil];
        checkPreferenceLayout(preferences);
        captureWindow([preferences window], directory, [mode stringByAppendingString:@"-preferences-status"]);
    }
    @finally
    {
        [path setURL:originalFolder];
        [controller setValue:originalError forKey:@"automaticLaunchError"];
        [preferences performSelector:NSSelectorFromString(@"refreshAutomaticLaunchStatus:") withObject:nil];
        [originalFolder release];
        [originalError release];
    }
}

static void checkAppearances(id controller, NSWindowController* backup, NSString* directory)
{
    requireInterface([NSApp appearance] == nil, @"The app overrides the system appearance.");
    NSWindow* main = [controller valueForKey:@"outletMainWindow"];
    NSOutlineView* outline = [controller valueForKey:@"outletFileView"];
    id inspector = [controller valueForKey:@"inspectorController"];
    NSArray* windows = @[main, [[controller valueForKey:@"preferenceController"] window], [inspector window], [backup window],
                         [[controller valueForKey:@"aboutController"] window]];
    NSArray* names = @[@"main", @"preferences", @"inspector", @"backup", @"about"];
    for (NSWindow* window in windows)
    {
        requireInterface([window appearance] == nil, @"A window overrides the system appearance.");
        checkInheritedAppearance([window contentView]);
    }
    for (NSToolbarItem* item in [[main toolbar] items])
        if ([item action]) requireInterface([item image] != nil && [[item image] isTemplate], @"A toolbar icon is not a native template image.");

    id device = [[[NSClassFromString(@"ASNode") alloc] init] autorelease];
    id file = [[[NSClassFromString(@"ASFileNode") alloc] performSelector:NSSelectorFromString(@"initForDisplay")] autorelease];
    [device setValue:@"AlphaSmart NEO" forKey:@"displayName"];
    [device setValue:@"Device" forKey:@"displayKind"];
    [device setValue:[NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:nil] forKey:@"icon"];
    [file setValue:@"Example document.txt" forKey:@"displayName"];
    [file setValue:@"Text" forKey:@"displayKind"];
    [file setValue:@"1.2 kB" forKey:@"displaySize"];
    [file setValue:[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil] forKey:@"icon"];
    [device performSelector:@selector(addChild:) withObject:file];
    ASInterfaceRows* rows = [[[ASInterfaceRows alloc] init] autorelease];
    [rows setRoots:@[device]];
    id originalDelegate = [outline delegate];
    [rows setDelegate:originalDelegate];
    id originalSource = [outline dataSource];
    [outline setDelegate:(id<NSOutlineViewDelegate>)rows];
    [outline setDataSource:rows];
    [outline reloadData];
    [outline expandItem:device];

    NSTableColumn* nameColumn = [outline tableColumnWithIdentifier:@"Name"];
    NSTableCellView* fileCell = (NSTableCellView*)[[outline delegate] outlineView:outline viewForTableColumn:nameColumn item:file];
    NSTableCellView* deviceCell = (NSTableCellView*)[[outline delegate] outlineView:outline viewForTableColumn:nameColumn item:device];
    requireInterface([fileCell isMemberOfClass:[NSTableCellView class]] && [[fileCell imageView] isMemberOfClass:[NSImageView class]] &&
                     [[fileCell textField] isMemberOfClass:[NSTextField class]], @"The file row is not made of standard AppKit views.");
    requireInterface([[fileCell textField] isEditable] && ![[deviceCell textField] isEditable], @"The wrong rows allow renaming.");
    id<NSTextFieldDelegate> editing = controller;
    NSTextView* editor = [[[NSTextView alloc] initWithFrame:NSZeroRect] autorelease];
    requireInterface([editing control:[fileCell textField] textShouldBeginEditing:editor] &&
                     ![editing control:[deviceCell textField] textShouldBeginEditing:editor], @"Row editing permissions changed.");
    [[fileCell textField] setStringValue:@"Cancelled name"];
    [editing controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:[fileCell textField]
                                                                userInfo:@{@"NSTextMovement": @(NSCancelTextMovement)}]];
    requireInterface([[[fileCell textField] stringValue] isEqualToString:@"Example document.txt"], @"Cancelling a rename changed the filename.");

    NSError* error = nil;
    requireInterface([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error],
                     [error localizedDescription] ?: @"The screenshot folder could not be created.");
    NSArray* appearances = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameAqua];
    for (NSUInteger pass = 0; pass < [appearances count]; ++pass)
    {
        [[inspector valueForKey:@"outletShowPreviewDisclosure"] setState:NSControlStateValueOff];
        [[inspector valueForKey:@"outletShowDetailDisclosure"] setState:NSControlStateValueOff];
        [inspector performSelector:NSSelectorFromString(@"actionPreviewDisclosure:") withObject:nil];
        NSString* appearanceName = appearances[pass];
        NSAppearance* appearance = [NSAppearance appearanceNamed:appearanceName];
        // Only the test sets an appearance.  Production windows inherit macOS settings.
        [NSApp setAppearance:appearance];
        NSString* mode = pass == 1 ? @"dark" : (pass == 0 ? @"light" : @"light-again");
        [appearance performAsCurrentDrawingAppearance:^{
            checkContrast([[fileCell textField] textColor], [outline backgroundColor]);
            NSTextField* preview = [inspector valueForKey:@"outletPreviewAsText"];
            checkContrast([preview textColor], [preview backgroundColor]);
        }];
        for (NSUInteger index = 0; index < [windows count]; ++index)
        {
            NSWindow* window = windows[index];
            NSString* actual = [[window effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            requireInterface([actual isEqualToString:appearanceName], @"A window did not follow an appearance change.");
            captureWindow(window, directory, [NSString stringWithFormat:@"%@-%@", mode, names[index]]);
        }
        [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        captureWindow(main, directory, [mode stringByAppendingString:@"-selection"]);
        [outline deselectAll:nil];
        capturePreferenceStatus(controller, directory, mode);
        captureBackupResults(backup, directory, mode);

        NSTextField* preview = [inspector valueForKey:@"outletPreviewAsText"];
        [preview setStringValue:@"A text preview with £, café, and curly quotes: ‘Hello’.\nThe same native field follows each appearance change."];
        [preview setHidden:NO];
        [[inspector valueForKey:@"outletPreviewAsIcon"] setHidden:YES];
        [[inspector valueForKey:@"outletShowPreviewDisclosure"] setState:NSControlStateValueOn];
        [[inspector valueForKey:@"outletShowDetailDisclosure"] setState:NSControlStateValueOn];
        NSArray* panels = @[@"device", @"applet", @"file"];
        SEL selector = NSSelectorFromString(@"configurePanelsToShowSystem:showApplet:showFile:");
        for (NSUInteger index = 0; index < [panels count]; ++index)
        {
            NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[inspector methodSignatureForSelector:selector]];
            [invocation setSelector:selector];
            for (NSUInteger panel = 0; panel < 3; ++panel)
            {
                BOOL show = panel == index;
                [invocation setArgument:&show atIndex:(NSInteger)panel + 2];
            }
            [invocation invokeWithTarget:inspector];
            captureWindow([inspector window], directory, [NSString stringWithFormat:@"%@-inspector-%@", mode, panels[index]]);
        }
    }
    [outline setDataSource:originalSource];
    [outline setDelegate:originalDelegate];
    [NSApp setAppearance:nil];
    puts("Native views, editing permissions, cancelled renames, contrast, and live appearance changes passed.");
}

static int checkInterface(void)
{
    @try
    {
        fputs("Interface check: starting AppKit.\n", stderr);
        [NSApplication sharedApplication];
        fputs("Interface check: loading the main menu.\n", stderr);
        NSNib* nib = [[[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:[NSBundle mainBundle]] autorelease];
        NSArray* objects = nil;
        if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) return 1;
        // NSApplicationMain normally installs the nib's main menu.  The smoke
        // check instantiates that nib itself, so install its top-level menu too.
        for (id object in objects)
            if ([object isKindOfClass:[NSMenu class]])
            {
                [NSApp setMainMenu:object];
                break;
            }
        requireInterface([NSApp mainMenu] != nil, @"The main menu did not load.");
        // Use normal AppKit startup for the window and appearance checks.
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        fputs("Interface check: finishing application launch.\n", stderr);
        [NSApp finishLaunching];
        fputs("Interface check: activating the application.\n", stderr);
        if (@available(macOS 14.0, *)) [NSApp activate];
        else [NSApp activateIgnoringOtherApps:YES];
        id controller = [NSApp delegate];
        if (!controller || ![controller valueForKey:@"outletMainWindow"] || ![controller valueForKey:@"outletFileView"]) return 1;

        // Load every window, so missing resources and broken outlet connections fail the check.
        fputs("Interface check: opening Preferences.\n", stderr);
        [controller performSelector:NSSelectorFromString(@"actionShowPreferences:") withObject:nil];
        fputs("Interface check: opening the Inspector.\n", stderr);
        [controller performSelector:NSSelectorFromString(@"actionInfo:") withObject:nil];
        fputs("Interface check: opening About through the menu.\n", stderr);
        BOOL openedAbout = NO;
        for (NSMenuItem* menu in [[NSApp mainMenu] itemArray])
            for (NSMenuItem* item in [[menu submenu] itemArray])
                if ([item action] == NSSelectorFromString(@"actionShowAbout:"))
                    openedAbout = [NSApp sendAction:[item action] to:[item target] from:item];
        requireInterface(openedAbout, @"The About menu did not open the native About window.");
        for (NSString* key in @[@"preferenceController", @"inspectorController", @"aboutController"])
        {
            NSWindowController* windowController = [controller valueForKey:key];
            requireInterface([windowController window] != nil, [NSString stringWithFormat:@"The %@ window did not load.", key]);
        }
        fputs("Interface check: checking Preferences settings and layout.\n", stderr);
        checkPreferences(controller);
        fputs("Interface check: creating the backup window.\n", stderr);
        NSWindowController* backup = [[NSClassFromString(@"ASBackupController") alloc] init];
        BOOL loaded = [backup window] != nil;
        requireInterface(loaded, @"The backup window did not load.");
        fputs("Interface check: checking backup results.\n", stderr);
        if (loaded) checkBackupResults(backup);
        NSArray* arguments = [[NSProcessInfo processInfo] arguments];
        NSUInteger snapshots = [arguments indexOfObject:@"--appearance-snapshots"];
        if (loaded && snapshots != NSNotFound)
        {
            requireInterface(snapshots + 1 < [arguments count], @"Supply a screenshot folder after --appearance-snapshots.");
            checkAppearances(controller, backup, arguments[snapshots + 1]);
        }
        [backup release];
        if (!loaded) return 1;
        puts("All interface windows loaded successfully.");
        return 0;
    }
    @catch (NSException* exception)
    {
        fprintf(stderr, "Interface check failed: %s\n", [[exception description] UTF8String]);
        return 1;
    }
}

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--smoke-test"])
            return checkInterface();
        return NSApplicationMain(argc, (const char**)argv);
    }
}
