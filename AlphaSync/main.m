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
    NSView* frame = [[window contentView] superview];
    [frame layoutSubtreeIfNeeded];
    NSBitmapImageRep* bitmap = [frame bitmapImageRepForCachingDisplayInRect:[frame bounds]];
    requireInterface(bitmap != nil, @"A window could not be rendered.");
    [frame cacheDisplayInRect:[frame bounds] toBitmapImageRep:bitmap];
    NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSError* error = nil;
    requireInterface([png writeToFile:[directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]
                            options:NSDataWritingAtomic error:&error], [error localizedDescription] ?: @"A screenshot could not be saved.");
}

static void checkAppearances(id controller, NSWindowController* backup, NSString* directory)
{
    requireInterface([NSApp appearance] == nil, @"The app overrides the system appearance.");
    NSWindow* main = [controller valueForKey:@"outletMainWindow"];
    NSOutlineView* outline = [controller valueForKey:@"outletFileView"];
    id inspector = [controller valueForKey:@"inspectorController"];
    NSArray* windows = @[main, [[controller valueForKey:@"preferenceController"] window], [inspector window], [backup window]];
    NSArray* names = @[@"main", @"preferences", @"inspector", @"backup"];
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
        [NSApplication sharedApplication];
        NSNib* nib = [[[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:[NSBundle mainBundle]] autorelease];
        NSArray* objects = nil;
        if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) return 1;
        id controller = [NSApp delegate];
        if (!controller || ![controller valueForKey:@"outletMainWindow"] || ![controller valueForKey:@"outletFileView"]) return 1;

        // Load every window, so missing resources and broken outlet connections fail the check.
        [controller performSelector:NSSelectorFromString(@"actionShowPreferences:") withObject:nil];
        [controller performSelector:NSSelectorFromString(@"actionInfo:") withObject:nil];
        for (NSString* key in @[@"preferenceController", @"inspectorController"])
        {
            NSWindowController* windowController = [controller valueForKey:key];
            if (![windowController window]) return 1;
        }
        NSWindowController* backup = [[NSClassFromString(@"ASBackupController") alloc] init];
        BOOL loaded = [backup window] != nil;
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
