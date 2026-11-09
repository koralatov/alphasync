#import <Cocoa/Cocoa.h>
#import "AQFileUtilities.h"
#import "ASNode.h"
#import "ASFileViewWindowController.h"
#import "ASDeviceAccessProtocol.h"
#include <math.h>
#include <stdio.h>

// Used only by --smoke-test.  These cached sample rows never access a Neo.
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

// File exports and scheduling for backup checks only.  No USB device is opened.
@interface ASInterfaceBackupFile : ASNode
@property BOOL failExport;
@end
@implementation ASInterfaceBackupFile
- (NSString*)saveUnderPath:(NSString*)path error:(NSString**)error
{
    if (_failExport)
    {
        if (error) *error = @"Sample export failure";
        return nil;
    }
    NSString* filename = [[self displayName] stringByAppendingPathExtension:@"txt"];
    NSError* writeError = nil;
    if (![@"Test backup\n" writeToFile:[path stringByAppendingPathComponent:filename] atomically:YES encoding:NSUTF8StringEncoding error:&writeError])
    {
        if (error) *error = [writeError localizedDescription];
        return nil;
    }
    return filename;
}
@end

@interface NSWindowController (ASBackupInterfaceChecks)
- (void)runBackupFor:(ASNode*)root controller:(id)controller modalForWindow:(NSWindow*)window;
- (void)requestStopForTermination;
- (IBAction)actionStopDone:(id)sender;
@end

@interface ASInterfaceBackupQueue : NSObject
@property (assign) NSWindowController* backup;
@property NSUInteger stopAfter;
@property NSUInteger completed;
@end
@implementation ASInterfaceBackupQueue
- (void)performTaskForNode:(ASNode*)node refresh:(BOOL)refresh task:(id (^)(ASNode*))task completion:(void (^)(id, NSString*))completion
{
    (void)refresh;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool
        {
            id result = [task(node) retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (++_completed == 1)
                {
                    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
                    [defaults setBool:![defaults boolForKey:@"SaveBackupLogs"] forKey:@"SaveBackupLogs"];
                }
                if (_stopAfter && _completed == _stopAfter) [_backup requestStopForTermination];
                completion(result, nil);
                [result release];
            });
        }
    });
}
@end

// Reader checks use a distinct worker object and complete text, with no USB access.
@interface ASInterfaceReadFile : ASNode
@property (copy) NSString* text;
@property BOOL failRead;
@property BOOL readOffMain;
@property NSUInteger reads;
@property NSUInteger writes;
- (NSString*)fileData;
- (BOOL)setFileData:(NSString*)text error:(NSString**)error;
@end
@implementation ASInterfaceReadFile
- (void)dealloc { [_text release]; [super dealloc]; }
- (NSString*)fileData
{
    ++_reads;
    _readOffMain = ![NSThread isMainThread];
    return _failRead ? nil : _text;
}
- (BOOL)setFileData:(NSString*)text error:(NSString**)error
{
    (void)text; (void)error; ++_writes; return NO;
}
@end

@interface ASInterfaceReadQueue : NSObject
@property (retain) ASInterfaceReadFile* worker;
@property (retain) ASNode* systemRoot;
@property (copy) void (^pendingRead)(void);
@property BOOL holdRead;
@property BOOL busy;
@property BOOL refreshed;
@property NSUInteger completed;
- (BOOL)isBusy;
- (void)finishPendingRead;
- (void)performTaskForNode:(ASNode*)node refresh:(BOOL)refresh task:(id (^)(ASNode*))task completion:(void (^)(id, NSString*))completion;
@end
@implementation ASInterfaceReadQueue
- (void)dealloc { [_worker release]; [_systemRoot release]; [_pendingRead release]; [super dealloc]; }
- (BOOL)isBusy { return _busy; }
- (void)performTaskForNode:(ASNode*)node refresh:(BOOL)refresh task:(id (^)(ASNode*))task completion:(void (^)(id, NSString*))completion
{
    (void)node;
    _refreshed = _refreshed || refresh;
    void (^read)(void) = ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool
            {
                [_worker setOperationError:nil];
                id result = [task(_worker) retain];
                NSString* error = result ? nil : [_worker operationError];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(result, error);
                    ++_completed;
                    [result release];
                });
            }
        });
    };
    if (_holdRead) [self setPendingRead:read];
    else read();
}
- (void)finishPendingRead
{
    void (^read)(void) = [[_pendingRead copy] autorelease];
    [self setPendingRead:nil];
    if (read) read();
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

static void checkClearConfirmation(id controller)
{
    NSWindow* parent = [controller valueForKey:@"outletMainWindow"];
    for (NSString* className in @[@"ASFileNode", @"ASAppletNode"])
    {
        id node = [[[NSClassFromString(className) alloc] performSelector:NSSelectorFromString(@"initForDisplay")] autorelease];
        [node setValue:@"Example" forKey:@"displayName"];
        for (NSNumber* replacement in @[@NO, @YES])
        {
            BOOL replace = [replacement boolValue];
            if (replace && [className isEqualToString:@"ASAppletNode"]) continue;
            NSString* command = replace ? @"Replace" : ([className isEqualToString:@"ASAppletNode"] ? @"Clear All Files" : @"Clear File");
            for (NSNumber* confirm in @[@NO, @YES])
            {
                __block BOOL finished = NO, allowed = NO;
                void (^completion)(BOOL) = ^(BOOL value) { allowed = value; finished = YES; };
                if (replace) [(id<ASDeviceAccessProtocol>)controller confirmReplace:node with:@"/tmp/Example.txt" completion:completion];
                else [(id<ASDeviceAccessProtocol>)controller confirmDelete:node completion:completion];
                NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5];
                NSButton* cancel = nil;
                NSButton* proceed = nil;
                while ((!cancel || !proceed) && [deadline timeIntervalSinceNow] > 0)
                {
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                    NSMutableArray* views = [NSMutableArray array];
                    if ([parent attachedSheet]) [views addObject:[[parent attachedSheet] contentView]];
                    while ([views count])
                    {
                        NSView* view = [[[views lastObject] retain] autorelease];
                        [views removeLastObject];
                        [views addObjectsFromArray:[view subviews]];
                        if (![view isKindOfClass:[NSButton class]]) continue;
                        if ([[(NSButton*)view title] isEqualToString:@"Cancel"]) cancel = (NSButton*)view;
                        if ([[(NSButton*)view title] isEqualToString:command]) proceed = (NSButton*)view;
                    }
                }
                requireInterface(cancel && proceed && [[parent attachedSheet] defaultButtonCell] == [cancel cell] &&
                                 [[proceed keyEquivalent] length] == 0, @"A destructive sheet has no safe Cancel default or explicit action label.");
                [([confirm boolValue] ? proceed : cancel) performClick:nil];
                while (!finished && [deadline timeIntervalSinceNow] > 0)
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                requireInterface(finished && allowed == [confirm boolValue], @"A destructive sheet returned the wrong response.");
                [controller performSelector:NSSelectorFromString(@"displayStatusTimerDone")];
            }
        }
    }
    puts("Native Replace and Clear sheets keep Cancel as the default and require an explicit destructive choice.");
}

static void checkConnectionLayout(id controller)
{
    NSWindow* window = [controller valueForKey:@"outletMainWindow"];
    NSView* content = [window contentView];
    [content layoutSubtreeIfNeeded];
    checkInheritedAppearance(content);
    for (NSString* key in @[@"connectionSymbol", @"connectionTitle", @"connectionMessage"])
    {
        NSView* view = [controller valueForKey:key];
        requireInterface(NSContainsRect(NSInsetRect([content bounds], -1, -1),
                                         [view convertRect:[view bounds] toView:content]), @"A connection control is outside the window.");
        if ([view isKindOfClass:[NSTextField class]])
        {
            NSTextField* label = (NSTextField*)view;
            NSSize needed = [[label cell] cellSizeForBounds:NSMakeRect(0, 0, NSWidth([label bounds]), 10000)];
            requireInterface(NSHeight([label bounds]) >= needed.height - 1, @"Connection text is clipped.");
        }
    }
}

static void sampleConnection(id controller, id device, BOOL connected)
{
    // Modify only the display tree.  --smoke-test never enables USB detection.
    id root = [[controller valueForKey:@"deviceController"] valueForKey:@"systemRoot"];
    [root performSelector:NSSelectorFromString(connected ? @"addChild:" : @"removeChild:") withObject:device];
    [[NSNotificationCenter defaultCenter] postNotificationName:connected ? @"ASDeviceConnected" : @"ASDeviceDisconnected" object:device];
}

static void checkConnectionStates(id controller)
{
    NSWindow* window = [controller valueForKey:@"outletMainWindow"];
    NSView* compact = [controller valueForKey:@"connectionContentView"];
    NSView* files = [controller valueForKey:@"fileViewerContentView"];
    NSTextField* title = [controller valueForKey:@"connectionTitle"];
    NSTextField* message = [controller valueForKey:@"connectionMessage"];
    NSImageView* symbol = [controller valueForKey:@"connectionSymbol"];
    NSToolbar* toolbar = [controller valueForKey:@"toolbar"];
    requireInterface([window contentView] == compact && [window toolbar] == nil && NSWidth([window frame]) < 480,
                     @"Startup without a Neo did not show the compact connection window.");
    requireInterface([NSImage imageWithSystemSymbolName:@"cable.connector" accessibilityDescription:nil] != nil &&
                     [[symbol image] isTemplate],
                     @"The connection icon is not an available native SF Symbol.");
    if (@available(macOS 12.0, *))
        requireInterface([[symbol image] symbolConfiguration] != nil, @"The connection symbol lost its native configuration.");
    requireInterface([[title stringValue] isEqualToString:@"No Neo connected"], @"The disconnected title changed.");
    checkConnectionLayout(controller);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ASDeviceDetected" object:nil];
    requireInterface([window contentView] == compact && [[title stringValue] isEqualToString:@"Connecting to Neo…"],
                     @"Detecting a Neo did not keep the compact connection progress visible.");
    NSString* error = @"The Neo could not be opened because another application is using it.  Close that application, check the USB cable, and reconnect your Neo to try again.";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ASDeviceError" object:error];
    requireInterface([[message stringValue] isEqualToString:error], @"The compact view hid a connection error.");
    checkConnectionLayout(controller);
    [controller performSelector:NSSelectorFromString(@"displayStatusTimerDone")];
    requireInterface([[title stringValue] isEqualToString:@"No Neo connected"] && [[message stringValue] containsString:@"USB cable"],
                     @"The waiting message did not return after a temporary error.");

    id first = [[[NSClassFromString(@"ASNode") alloc] init] autorelease];
    id second = [[[NSClassFromString(@"ASNode") alloc] init] autorelease];
    sampleConnection(controller, first, YES);
    requireInterface([window contentView] == files && [window toolbar] == toolbar && NSWidth([window frame]) >= 480,
                     @"Connecting did not restore the file viewer and its toolbar.");
    NSSize initialSize = [window frame].size;
    NSRect resized = [window frame];
    resized.size = NSMakeSize(620, 560);
    [window setFrame:resized display:YES];
    NSSize userSize = [window frame].size;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ASDeviceDataChanged" object:nil];
    sampleConnection(controller, second, YES);
    sampleConnection(controller, first, NO);
    requireInterface([window contentView] == files && NSEqualSizes([window frame].size, userSize),
                     @"A refresh or disconnect with another Neo present changed the file viewer size.");

    // A disconnect must not interrupt a backup result or a native file sheet.
    NSWindow* sheet = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 100)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
    [sheet setReleasedWhenClosed:NO];
    [window makeKeyAndOrderFront:nil];
    [window beginSheet:sheet completionHandler:nil];
    sampleConnection(controller, second, NO);
    requireInterface([window contentView] == files && [window attachedSheet] == sheet,
                     @"The parent window shrank while its sheet was open.");
    [window endSheet:sheet];
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (([window attachedSheet] || [window contentView] != compact) && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    requireInterface([window contentView] == compact && [window toolbar] == nil, @"The last Neo disconnect did not return to the compact window.");
    sampleConnection(controller, first, YES);
    requireInterface([window contentView] == files && NSEqualSizes([window frame].size, userSize),
                     @"Reconnecting lost the chosen file viewer size.");
    resized = [window frame];
    resized.size = initialSize;
    [window setFrame:resized display:YES];
    sampleConnection(controller, first, NO);
    checkConnectionLayout(controller);
    puts("Native connection symbol, waiting, progress, errors, reconnect sizing, multiple Neos, and sheet deferral passed.");
}

static void checkPreferenceLayout(id preferences)
{
    NSView* content = [[preferences window] contentView];
    [content layoutSubtreeIfNeeded];
    for (NSString* key in @[@"outletFilterOption", @"outputFormatField", @"backupFolderPath", @"chooseFolderButton",
                             @"saveBackupLogsButton", @"outletAutoRun", @"automaticLaunchStatusField", @"loginItemsButton"])
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
    NSButton* logs = [preferences valueForKey:@"saveBackupLogsButton"];
    requireInterface(![[defaults volatileDomainForName:NSRegistrationDomain][@"SaveBackupLogs"] boolValue], @"Backup logs are enabled by default.");
    BOOL originalLogs = [defaults boolForKey:@"SaveBackupLogs"];
    requireInterface(([logs state] == NSControlStateValueOn) == originalLogs, @"Preferences did not load the backup log option.");
    @try
    {
        [logs performClick:nil];
        requireInterface([defaults boolForKey:@"SaveBackupLogs"] != originalLogs, @"The backup log option did not save its change.");
        [logs performClick:nil];
        requireInterface([defaults boolForKey:@"SaveBackupLogs"] == originalLogs, @"The backup log option could not be restored.");
    }
    @finally
    {
        [defaults setBool:originalLogs forKey:@"SaveBackupLogs"];
        [logs setState:originalLogs ? NSControlStateValueOn : NSControlStateValueOff];
    }
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
    NSArray* paths = @[@"/Users/Example/Documents/AlphaSync/My Neo/2026-11-08"];
    sampleBackupResult(backup, 8, 8, 0, 1, paths, @"complete");
    NSTextField* title = [backup valueForKey:@"outletFilesRemaining"];
    NSTextField* summary = [backup valueForKey:@"outletBackupItem"];
    NSButton* open = [backup valueForKey:@"openBackupButton"];
    NSButton* done = [backup valueForKey:@"outletStopDoneButton"];
    requireInterface([[title stringValue] isEqualToString:@"Backup complete"] &&
                     [[summary stringValue] containsString:@"copies of 8 files from your Neo"], @"Successful backup wording changed.");
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

static void checkBackupLogs(id controller, NSWindowController* backup)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    id originalFolder = [[defaults objectForKey:@"BackupFolder"] retain];
    id originalLogs = [[defaults objectForKey:@"SaveBackupLogs"] retain];
    NSFileManager* manager = [NSFileManager defaultManager];
    NSString* temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSWindow* parent = [controller valueForKey:@"outletMainWindow"];
    @try
    {
        for (NSUInteger scenario = 0; scenario < 5; ++scenario)
        {
            NSString* folder = [temporary stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu", (unsigned long)scenario]];
            [defaults setObject:folder forKey:@"BackupFolder"];
            [defaults setBool:scenario != 0 forKey:@"SaveBackupLogs"];
            ASNode* root = [[[ASNode alloc] init] autorelease];
            for (NSUInteger device = 0; device < (scenario == 4 ? 0 : 2); ++device)
            {
                ASNode* neo = [[[ASNode alloc] init] autorelease];
                [neo setDisplayName:device == 0 ? @"First Neo" : @"Second Neo"];
                ASNode* applet = [[[ASNode alloc] init] autorelease];
                [applet setDisplayName:@"AlphaWord"];
                for (NSUInteger index = 0; index < 2; ++index)
                {
                    ASInterfaceBackupFile* file = [[[ASInterfaceBackupFile alloc] init] autorelease];
                    [file setDisplayName:index == 0 ? @"One" : @"Two"];
                    [file setFileSize:12];
                    [file setFailExport:scenario == 3 && device == 0 && index == 1];
                    [applet addChild:file];
                }
                [neo addChild:applet];
                [root addChild:neo];
            }
            ASInterfaceBackupQueue* queue = [[[ASInterfaceBackupQueue alloc] init] autorelease];
            [queue setBackup:backup];
            [queue setStopAfter:scenario == 2 ? 3 : 0];
            [backup runBackupFor:root controller:queue modalForWindow:parent];
            NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:10];
            while ([backup valueForKey:@"backupItems"] && [deadline timeIntervalSinceNow] > 0)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            requireInterface([backup valueForKey:@"backupItems"] == nil, @"The sample backup did not finish.");
            NSArray* titles = @[@"Backup complete", @"Backup complete", @"Backup stopped", @"Backup incomplete", @"No files to back up"];
            requireInterface([[[backup valueForKey:@"outletFilesRemaining"] stringValue] isEqualToString:titles[scenario]], @"A backup result changed when logging was optional.");
            NSArray* paths = [backup valueForKey:@"backupSessionPaths"];
            requireInterface([paths count] == (scenario == 4 ? 0 : 2), @"A dated Neo backup folder is missing.");
            for (NSUInteger device = 0; device < [paths count]; ++device)
            {
                NSString* log = [paths[device] stringByAppendingPathComponent:@"AlphaSync Backup Log.plist"];
                requireInterface([manager fileExistsAtPath:log] == (scenario != 0), @"Backup logs did not follow the option captured at the start.");
                if (scenario == 0) continue;
                NSDictionary* contents = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:log] options:0 format:NULL error:NULL];
                NSArray* entries = contents[@"files"];
                NSString* expected = scenario == 2 && device == 1 ? @"cancelled" :
                                     (scenario == 3 && device == 0 ? @"completed with failures" : @"complete");
                requireInterface([contents[@"status"] isEqualToString:expected] && [entries count] == 2, @"A Neo log has the wrong final status or file count.");
                for (NSDictionary* entry in entries)
                {
                    NSString* name = device == 0 ? @"First Neo" : @"Second Neo";
                    requireInterface([entry[@"device"] isEqualToString:name], @"A log contains another Neo’s files.");
                    if ([entry[@"status"] isEqualToString:@"saved"])
                        requireInterface([manager fileExistsAtPath:entry[@"path"]], @"A log lists a file that was not saved.");
                }
                if (scenario == 2 && device == 1)
                    requireInterface([entries[1][@"status"] isEqualToString:@"pending"], @"A cancelled log lost its pending file.");
            }
            requireInterface(![manager fileExistsAtPath:[folder stringByAppendingPathComponent:@"Backup Reports"]], @"Backup logs created a separate reports folder.");
            if (scenario == 4) requireInterface(![manager fileExistsAtPath:folder], @"An empty backup created log folders.");
            [backup actionStopDone:nil];
            while ([parent attachedSheet] && [deadline timeIntervalSinceNow] > 0)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            requireInterface([parent attachedSheet] == nil, @"The sample backup sheet did not close.");
        }
    }
    @finally
    {
        if (originalFolder) [defaults setObject:originalFolder forKey:@"BackupFolder"];
        else [defaults removeObjectForKey:@"BackupFolder"];
        if (originalLogs) [defaults setObject:originalLogs forKey:@"SaveBackupLogs"];
        else [defaults removeObjectForKey:@"SaveBackupLogs"];
        [originalFolder release];
        [originalLogs release];
        [manager removeItemAtPath:temporary error:nil];
    }
    puts("Optional backup logs, dated destinations, separate Neos, cancellation, failed exports, and empty backups passed.");
}

static void captureBackupResults(NSWindowController* backup, NSString* directory, NSString* mode)
{
    NSArray* paths = @[@"/Users/Example/Documents/AlphaSync/My Neo/2026-11-08"];
    sampleBackupResult(backup, 8, 8, 0, 1, paths, @"complete");
    CGFloat shortHeight = NSHeight([[backup window] frame]);
    captureWindow([backup window], directory, [mode stringByAppendingString:@"-backup-complete"]);
    sampleBackupResult(backup, 8, 8, 2, 1, paths, @"complete");
    captureWindow([backup window], directory, [mode stringByAppendingString:@"-backup-incomplete"]);
    NSArray* longPaths = @[
        @"/Users/Example/Documents/Writing and notes/AlphaSmart Neo backups/An unusually long backup folder name/My first Neo/2026-11-08",
        @"/Users/Example/Documents/Writing and notes/AlphaSmart Neo backups/An unusually long backup folder name/My second Neo/2026-11-08 (1)"
    ];
    sampleBackupResult(backup, 16, 16, 0, 2, longPaths, @"complete");
    requireInterface(NSHeight([[backup window] frame]) > shortHeight, @"The backup sheet did not grow for multiple long locations.");
    requireInterface([[[backup valueForKey:@"outletBackupItem"] stringValue] containsString:@"from 2 Neos"] &&
                     [[[backup valueForKey:@"backupLocationsView"] arrangedSubviews] count] == 3 &&
                     [[[backup valueForKey:@"openBackupButton"] title] isEqualToString:@"Open Backup Folders"], @"Multiple Neo backup locations are missing.");
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
        [path setURL:[NSURL fileURLWithPath:@"/Users/Example/Documents/Writing and notes/AlphaSmart Neo backups/An unusually long backup folder name" isDirectory:YES]];
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

static NSString* sampleReadText(void)
{
    NSMutableString* text = [NSMutableString stringWithString:@"Notes from the Neo\n\n£, café, and curly quotes: ‘Hello’.\n\n"];
    for (NSUInteger line = 0; line < 100; ++line)
        [text appendString:@"The complete file remains available for reading, scrolling, and copying.\n"];
    [text appendString:@"End of the complete file.\n"];
    return text;
}

static void waitForRead(ASInterfaceReadQueue* queue, NSUInteger completed)
{
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while ([queue completed] < completed && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    requireInterface([queue completed] == completed, @"A file read did not complete on the main thread.");
}

static void checkFileViewLayout(ASFileViewWindowController* viewer)
{
    NSView* content = [[viewer window] contentView];
    [content layoutSubtreeIfNeeded];
    NSTextView* text = [viewer valueForKey:@"textView"];
    NSScrollView* scroll = [viewer valueForKey:@"scrollView"];
    // AppKit manages appearances on private text and scroller subviews.  Check
    // the controls we create and their effective mode, not framework internals.
    NSArray* modes = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua];
    NSString* expectedMode = [[[viewer window] effectiveAppearance] bestMatchFromAppearancesWithNames:modes];
    requireInterface([[viewer window] isMemberOfClass:[NSWindow class]] && [[viewer window] appearance] == nil,
                     @"The file viewer is not a standard window inheriting the system appearance.");
    for (NSView* view in @[content, text, scroll, [viewer valueForKey:@"fontStyle"], [viewer valueForKey:@"statusLabel"], [viewer valueForKey:@"progress"]])
    {
        requireInterface([view appearance] == nil && ![NSStringFromClass([view class]) hasPrefix:@"AS"],
                         [NSString stringWithFormat:@"The file viewer control %@ overrides its appearance or uses a custom view.", NSStringFromClass([view class])]);
        NSString* actualMode = [[view effectiveAppearance] bestMatchFromAppearancesWithNames:modes];
        requireInterface([actualMode isEqualToString:expectedMode], @"A file viewer control did not follow its window’s appearance.");
    }
    requireInterface(![text isEditable] && [text isSelectable] && ![text isRichText] && ![text allowsUndo],
                     @"The file viewer permits editing or prevents text selection.");
    requireInterface(NSWidth([text frame]) <= NSWidth([[scroll contentView] bounds]) + 1 && ![scroll hasHorizontalScroller],
                     @"The file viewer does not wrap its text to the visible width.");
    for (NSString* key in @[@"fontStyle", @"statusLabel"])
    {
        NSView* view = [viewer valueForKey:key];
        NSRect frame = [view convertRect:[view bounds] toView:content];
        requireInterface(NSContainsRect(NSInsetRect([content bounds], -1, -1), frame), @"A file viewer control is outside the window.");
    }
    NSTextField* status = [viewer valueForKey:@"statusLabel"];
    NSSize needed = [[status cell] cellSizeForBounds:NSMakeRect(0, 0, NSWidth([status bounds]), 10000)];
    requireInterface(NSHeight([status bounds]) >= needed.height - 1, @"A file viewer status or error is clipped.");
}

static void checkFileViews(id controller)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    id originalFont = [[defaults objectForKey:@"FileViewerMonospaced"] retain];
    id originalController = [[controller valueForKey:@"deviceController"] retain];
    ASInterfaceReadFile* worker = [[[ASInterfaceReadFile alloc] init] autorelease];
    [worker setText:sampleReadText()];
    ASInterfaceReadQueue* queue = [[[ASInterfaceReadQueue alloc] init] autorelease];
    [queue setWorker:worker];
    [queue setSystemRoot:[originalController valueForKey:@"systemRoot"]];
    id file = [[[NSClassFromString(@"ASFileNode") alloc] performSelector:NSSelectorFromString(@"initForDisplay")] autorelease];
    [file setValue:@"Example document.txt" forKey:@"displayName"];
    [file setValue:@"A shortened preview." forKey:@"filePreview"];
    @try
    {
        [defaults setBool:NO forKey:@"FileViewerMonospaced"];
        [controller setValue:queue forKey:@"deviceController"];
        NSOutlineView* outline = [controller valueForKey:@"outletFileView"];
        requireInterface([outline target] == controller && [outline doubleAction] == NSSelectorFromString(@"actionOpenFile:"),
                         @"The file list has no double-click open action.");
        NSUInteger before = [[controller valueForKey:@"fileViewWindows"] count];
        [outline sendAction:[outline doubleAction] to:[outline target]];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:[queue systemRoot]];
        [queue setBusy:YES];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        requireInterface([[controller valueForKey:@"fileViewWindows"] count] == before, @"An empty row, device, or busy list opened a file.");
        [queue setBusy:NO];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        ASFileViewWindowController* first = [[[controller valueForKey:@"fileViewWindows"] lastObject] retain];
        [first autorelease];
        requireInterface(first && [[first window] isVisible], @"Opening a file did not show a new window.");
        NSSize size = [[[first window] contentView] bounds].size;
        requireInterface(fabs(size.width - 640) < 1 && fabs(size.height - 480) < 1 &&
                         ([[first window] styleMask] & NSWindowStyleMaskResizable), @"The file viewer has the wrong initial size or cannot resize.");
        waitForRead(queue, 1);
        NSTextView* text = [first valueForKey:@"textView"];
        requireInterface([[text string] isEqualToString:[worker text]] && [worker readOffMain] && ![queue refreshed],
                         @"The viewer used a partial preview, read on the main thread, or refreshed the device.");
        [[first window] makeFirstResponder:text];
        [text setSelectedRange:NSMakeRange(0, 5)];
        NSPasteboard* copyBoard = [NSPasteboard pasteboardWithUniqueName];
        NSArray* copyTypes = [text writablePasteboardTypes];
        BOOL copied = [text writeSelectionToPasteboard:copyBoard types:copyTypes];
        NSString* copiedText = [copyBoard stringForType:NSPasteboardTypeString];
        requireInterface(copied && [copiedText isEqualToString:@"Notes"],
            [NSString stringWithFormat:@"Read-only copy failed: wrote=%d, selection=%@, types=%@, copied=%@.",
             copied, NSStringFromRange([text selectedRange]), copyTypes, copiedText]);
        [copyBoard releaseGlobally];
        NSSegmentedControl* style = [first valueForKey:@"fontStyle"];
        NSFont* regular = [NSFont systemFontOfSize:0];
        requireInterface([style selectedSegment] == 0 && [[[text font] fontName] isEqualToString:[regular fontName]] &&
                         fabs([[text font] pointSize] - [regular pointSize]) < 0.01, @"The regular font does not use system defaults.");
        [style setSelectedSegment:1];
        [style sendAction:[style action] to:[style target]];
        NSFont* mono = [NSFont monospacedSystemFontOfSize:0 weight:NSFontWeightRegular];
        requireInterface([[[text font] fontName] isEqualToString:[mono fontName]] && fabs([[text font] pointSize] - [mono pointSize]) < 0.01 &&
                         [[text string] isEqualToString:[worker text]] && NSEqualRanges([text selectedRange], NSMakeRange(0, 5)),
                         @"Changing the font changed the text, selection, or system font size.");
        checkFileViewLayout(first);
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        ASFileViewWindowController* second = [[controller valueForKey:@"fileViewWindows"] lastObject];
        waitForRead(queue, 2);
        requireInterface(second != first && [[second valueForKey:@"fontStyle"] selectedSegment] == 1 &&
                         !NSEqualPoints([[first window] frame].origin, [[second window] frame].origin), @"New file windows do not inherit the font choice or cascade.");
        [style setSelectedSegment:0];
        [style sendAction:[style action] to:[style target]];
        requireInterface([[second valueForKey:@"fontStyle"] selectedSegment] == 1, @"One file window changed another window’s font.");
        [first close];
        requireInterface([[controller valueForKey:@"fileViewWindows"] count] == before + 1, @"Closing a file window did not release its owner.");

        [worker setFailRead:YES];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        ASFileViewWindowController* failed = [[controller valueForKey:@"fileViewWindows"] lastObject];
        waitForRead(queue, 3);
        [[failed window] setContentSize:NSMakeSize(400, 300)];
        checkFileViewLayout(failed);
        requireInterface([[[failed valueForKey:@"textView"] string] length] == 0 &&
                         [[[failed valueForKey:@"statusLabel"] stringValue] containsString:@"couldn’t read"], @"A failed read displayed stale text or no explanation.");
        [worker setFailRead:NO];
        [worker setText:@""];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        ASFileViewWindowController* empty = [[controller valueForKey:@"fileViewWindows"] lastObject];
        waitForRead(queue, 4);
        requireInterface([[[empty valueForKey:@"statusLabel"] stringValue] containsString:@"empty"], @"An empty file was treated as a read failure.");
        [queue setHoldRead:YES];
        [controller performSelector:NSSelectorFromString(@"openFile:") withObject:file];
        ASFileViewWindowController* closed = [[[[controller valueForKey:@"fileViewWindows"] lastObject] retain] autorelease];
        [closed close];
        [queue finishPendingRead];
        waitForRead(queue, 5);
        requireInterface(![[closed window] isVisible] && [[[closed valueForKey:@"textView"] string] length] == 0 &&
                         [worker writes] == 0 && [worker reads] == 5, @"A closed reader reopened, or viewing wrote to the file.");
    }
    @finally
    {
        [queue setPendingRead:nil];
        for (NSWindowController* viewer in [[[controller valueForKey:@"fileViewWindows"] copy] autorelease]) [viewer close];
        [controller setValue:originalController forKey:@"deviceController"];
        if (originalFont) [defaults setObject:originalFont forKey:@"FileViewerMonospaced"];
        else [defaults removeObjectForKey:@"FileViewerMonospaced"];
        [originalFont release];
        [originalController release];
    }
    puts("Complete background reads, read-only copying, system fonts, independent file windows, empty files, errors, and close-during-read checks passed.");
}

static void captureFileViews(NSString* directory, NSString* mode)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    id original = [[defaults objectForKey:@"FileViewerMonospaced"] retain];
    ASFileViewWindowController* viewer = [[[ASFileViewWindowController alloc] initWithFileName:@"Example document.txt"] autorelease];
    ASInterfaceReadFile* worker = [[[ASInterfaceReadFile alloc] init] autorelease];
    [worker setText:sampleReadText()];
    ASInterfaceReadQueue* queue = [[[ASInterfaceReadQueue alloc] init] autorelease];
    [queue setWorker:worker];
    @try
    {
        [viewer showWindow:nil];
        [viewer loadFile:nil controller:(ASDeviceController*)queue];
        waitForRead(queue, 1);
        requireInterface([[viewer window] appearance] == nil, @"A file window overrides the system appearance.");
        [[[viewer window] effectiveAppearance] performAsCurrentDrawingAppearance:^{
            NSTextView* text = [viewer valueForKey:@"textView"];
            checkContrast([text textColor], [text backgroundColor]);
        }];
        NSSegmentedControl* style = [viewer valueForKey:@"fontStyle"];
        for (NSInteger index = 0; index < 2; ++index)
        {
            [style setSelectedSegment:index];
            [style sendAction:[style action] to:[style target]];
            checkFileViewLayout(viewer);
            captureWindow([viewer window], directory, [NSString stringWithFormat:@"%@-file-%@", mode, index ? @"monospaced" : @"regular"]);
        }
    }
    @finally
    {
        [viewer close];
        if (original) [defaults setObject:original forKey:@"FileViewerMonospaced"];
        else [defaults removeObjectForKey:@"FileViewerMonospaced"];
        [original release];
    }
}

static void checkInspectorLayout(id inspector)
{
    NSView* content = [[inspector window] contentView];
    [content layoutSubtreeIfNeeded];
    for (NSString* key in @[@"previewHeading", @"detailsHeading", @"previewContainer"])
        requireInterface(![[inspector valueForKey:key] isHiddenOrHasHiddenAncestor], @"An Inspector section is collapsed.");
    NSArray* fields = @[@"outletMainName", @"outletMainType", @"outletMainSize", @"outletMainRamRom",
                        @"outletSystemVersion", @"outletSystemBuild", @"outletSystemDate", @"outletSystemInfo", @"outletSystemRAM", @"outletSystemROM",
                        @"outletAppletDescription", @"outletAppletInfo", @"outletAppletFlags", @"outletAppletMinFileSize", @"outletAppletMaxFileSize",
                        @"outletAppletROM", @"outletAppletRAM1", @"outletAppletRAM2", @"outletFilePassword", @"outletFileRam", @"outletFileKey"];
    for (NSString* key in fields)
    {
        NSTextField* field = [inspector valueForKey:key];
        if ([field isHiddenOrHasHiddenAncestor]) continue;
        NSRect frame = [field convertRect:[field bounds] toView:content];
        requireInterface(NSContainsRect(NSInsetRect([content bounds], -1, -1), frame),
                         [NSString stringWithFormat:@"The Inspector field %@ is outside the window.", key]);
        NSSize needed = [[field cell] cellSizeForBounds:NSMakeRect(0, 0, NSWidth([field bounds]), 10000)];
        requireInterface(NSHeight([field bounds]) >= needed.height - 1,
                         [NSString stringWithFormat:@"The Inspector field %@ is clipped.", key]);
    }
    NSTextView* preview = [inspector valueForKey:@"outletPreviewAsText"];
    requireInterface(![preview isEditable] && [preview isSelectable], @"The Inspector preview is not read-only and selectable.");
    NSScrollView* scroll = [inspector valueForKey:@"previewScrollView"];
    if (![scroll isHiddenOrHasHiddenAncestor])
        requireInterface(NSWidth([preview frame]) <= NSWidth([[scroll contentView] bounds]) + 1, @"The Inspector preview does not wrap to its visible width.");
}

static void captureHelpMenu(NSWindow* window, NSString* directory, NSString* mode)
{
    NSMenu* menu = [NSApp helpMenu];
    NSView* content = [window contentView];
    NSPoint point = NSMakePoint(20, NSHeight([content bounds]) - 20);
    NSPoint onScreen = [window convertPointToScreen:[content convertPoint:point toView:nil]];
    __block BOOL captured = NO;
    NSTimer* captureTimer = [NSTimer timerWithTimeInterval:0.4 repeats:NO block:^(NSTimer* timer) {
        (void)timer;
        @try
        {
            NSSize size = [menu size];
            CGFloat screenTop = NSMaxY([[[NSScreen screens] firstObject] frame]);
            NSString* rectangle = [NSString stringWithFormat:@"%.0f,%.0f,%.0f,%.0f", onScreen.x - 12,
                screenTop - onScreen.y - 12, MAX(size.width, 260) + 24, size.height + 48];
            NSString* filename = [NSString stringWithFormat:@"%@-help-menu.png", mode];
            NSString* path = [directory stringByAppendingPathComponent:filename];
            NSTask* task = [[[NSTask alloc] init] autorelease];
            [task setExecutableURL:[NSURL fileURLWithPath:@"/usr/sbin/screencapture"]];
            [task setArguments:@[@"-x", @"-R", rectangle, path]];
            if ([task launchAndReturnError:NULL])
            {
                [task waitUntilExit];
                captured = [task terminationStatus] == 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
            }
        }
        @finally { [menu cancelTracking]; }
    }];
    [[NSRunLoop currentRunLoop] addTimer:captureTimer forMode:NSEventTrackingRunLoopMode];
    [menu popUpMenuPositioningItem:nil atLocation:point inView:content];
    [captureTimer invalidate];
    if (!captured) fprintf(stderr, "The runner could not capture the native Help popup; menu behaviour remains in the manual checklist.\n");
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
    id device = [[[NSClassFromString(@"ASNode") alloc] init] autorelease];
    id file = [[[NSClassFromString(@"ASFileNode") alloc] performSelector:NSSelectorFromString(@"initForDisplay")] autorelease];
    [device setValue:@"AlphaSmart Neo" forKey:@"displayName"];
    [device setValue:@"Device" forKey:@"displayKind"];
    [device setValue:[NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:nil] forKey:@"icon"];
    [file setValue:@"Example document.txt" forKey:@"displayName"];
    [file setValue:@"Text" forKey:@"displayKind"];
    [file setValue:aq_FormattedFileSize(12000) forKey:@"displaySize"];
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
    id root = [[controller valueForKey:@"deviceController"] valueForKey:@"systemRoot"];
    [root performSelector:@selector(addChild:) withObject:device];
    [controller performSelector:NSSelectorFromString(@"setStatusImmediateIdle")];
    checkInheritedAppearance([main contentView]);
    for (NSToolbarItem* item in [[main toolbar] items])
        if ([item action]) requireInterface([item image] != nil && [[item image] isTemplate], @"A toolbar icon is not a native template image.");

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
        [inspector performSelector:NSSelectorFromString(@"clearDisplay")];
        NSString* appearanceName = appearances[pass];
        NSAppearance* appearance = [NSAppearance appearanceNamed:appearanceName];
        // Only the test sets an appearance.  Production windows inherit macOS settings.
        [NSApp setAppearance:appearance];
        NSString* mode = pass == 1 ? @"dark" : (pass == 0 ? @"light" : @"light-again");
        [appearance performAsCurrentDrawingAppearance:^{
            checkContrast([[fileCell textField] textColor], [outline backgroundColor]);
            NSTextView* preview = [inspector valueForKey:@"outletPreviewAsText"];
            checkContrast([preview textColor], [preview backgroundColor]);
        }];
        [[controller valueForKey:@"outletAvailableMemory"] setStringValue:
            [NSString stringWithFormat:@"%@ available", aq_FormattedFileSize(299520)]];
        for (NSUInteger index = 0; index < [windows count]; ++index)
        {
            NSWindow* window = windows[index];
            NSString* actual = [[window effectiveAppearance] bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
            requireInterface([actual isEqualToString:appearanceName], @"A window did not follow an appearance change.");
            captureWindow(window, directory, [NSString stringWithFormat:@"%@-%@", mode, names[index]]);
        }
        NSSize mainSize = [[main contentView] bounds].size;
        [main setContentSize:NSMakeSize(680, mainSize.height)];
        captureWindow(main, directory, [mode stringByAppendingString:@"-main-wide"]);
        [main setContentSize:mainSize];
        [controller performSelector:NSSelectorFromString(@"setStatusBusy:") withObject:@"Reading files from the Neo…"];
        captureWindow(main, directory, [mode stringByAppendingString:@"-main-busy"]);
        [controller performSelector:NSSelectorFromString(@"displayStatusTimerDone")];
        captureHelpMenu(main, directory, mode);
        [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
        captureWindow(main, directory, [mode stringByAppendingString:@"-selection"]);
        [outline deselectAll:nil];
        [root performSelector:@selector(removeChild:) withObject:device];
        [controller performSelector:NSSelectorFromString(@"setStatusImmediateIdle")];
        checkConnectionLayout(controller);
        captureWindow(main, directory, [mode stringByAppendingString:@"-disconnected"]);
        [root performSelector:@selector(addChild:) withObject:device];
        [controller performSelector:NSSelectorFromString(@"setStatusImmediateIdle")];
        capturePreferenceStatus(controller, directory, mode);
        captureBackupResults(backup, directory, mode);
        captureFileViews(directory, mode);

        NSTextView* preview = [inspector valueForKey:@"outletPreviewAsText"];
        NSMutableString* text = [NSMutableString stringWithString:@"A text preview with £, café, and curly quotes: ‘Hello’.\n\n"];
        for (NSUInteger line = 0; line < 20; ++line)
            [text appendString:@"Long previews remain readable and can be scrolled and copied.\n"];
        [preview setString:text];
        // Display samples exercise compact sizes and grouped byte counts without device metadata.
        NSDictionary* sizes = @{
            @"outletSystemRAM": aq_FormattedFileSize(299520),
            @"outletSystemROM": aq_FormattedFileSize(1048576),
            @"outletSystemVersion": @"3.6",
            @"outletSystemBuild": @"System 3 Neo",
            @"outletSystemDate": @"2009-05-12",
            @"outletSystemInfo": @"AlphaSmart Neo system software",
            @"outletAppletDescription": @"AlphaWord Plus UK 3.3 (English (UK))",
            @"outletAppletInfo": @"Copyright (c) 2005–2009 by Renaissance Learning, Inc.",
            @"outletAppletFlags": @"Visible",
            @"outletAppletMinFileSize": aq_FormattedByteCount(512),
            @"outletAppletMaxFileSize": aq_FormattedByteCount(51200),
            @"outletAppletROM": aq_FormattedByteCount(106432),
            @"outletAppletRAM1": aq_FormattedByteCount(3472),
            @"outletAppletRAM2": aq_FormattedByteCount(31232),
            @"outletFileRam": aq_FormattedByteCount(31232),
            @"outletFilePassword": @"write",
            @"outletFileKey": @"F3"
        };
        for (NSString* outlet in sizes)
            [[inspector valueForKey:outlet] setStringValue:sizes[outlet]];
        NSArray* panels = @[@"device", @"applet", @"file"];
        NSArray* panelNames = @[@"AlphaSmart Neo", @"AlphaWord Plus UK", @"Example document.txt"];
        NSArray* panelSizes = @[@"", aq_FormattedFileSize(34704), aq_FormattedFileSize(31232)];
        NSArray* panelTypes = @[@"System 3.6", @"Version 3.3", @"AlphaWord Plus UK"];
        NSArray* panelIcons = @[@"icon-neo", @"icon-applet", @"icon-file-txt"];
        SEL selector = NSSelectorFromString(@"configurePanelsToShowSystem:showApplet:showFile:");
        for (NSUInteger index = 0; index < [panels count]; ++index)
        {
            [[inspector valueForKey:@"outletMainName"] setStringValue:panelNames[index]];
            [[inspector valueForKey:@"outletMainSize"] setStringValue:panelSizes[index]];
            [[inspector valueForKey:@"outletMainType"] setStringValue:panelTypes[index]];
            [[inspector valueForKey:@"outletMainRamRom"] setStringValue:index == 1 ? @"8 files" : @""];
            NSString* iconPath = [[NSBundle mainBundle] pathForResource:panelIcons[index] ofType:@"pdf"];
            NSImage* icon = [[[NSImage alloc] initWithContentsOfFile:iconPath] autorelease];
            [[inspector valueForKey:@"outletMainIcon"] setImage:icon];
            [[inspector valueForKey:@"outletPreviewAsIcon"] setImage:icon];
            [[inspector valueForKey:@"previewScrollView"] setHidden:index != 2];
            [[inspector valueForKey:@"outletPreviewAsIcon"] setHidden:index == 2];
            NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[inspector methodSignatureForSelector:selector]];
            [invocation setSelector:selector];
            for (NSUInteger panel = 0; panel < 3; ++panel)
            {
                BOOL show = panel == index;
                [invocation setArgument:&show atIndex:(NSInteger)panel + 2];
            }
            [invocation invokeWithTarget:inspector];
            [preview scrollRangeToVisible:NSMakeRange(0, 0)];
            captureWindow([inspector window], directory, [NSString stringWithFormat:@"%@-inspector-%@", mode, panels[index]]);
            checkInspectorLayout(inspector);
        }
    }
    [outline setDataSource:originalSource];
    [outline setDelegate:originalDelegate];
    [root performSelector:@selector(removeChild:) withObject:device];
    [outline reloadData];
    [controller performSelector:NSSelectorFromString(@"setStatusImmediateIdle")];
    [NSApp setAppearance:nil];
    puts("Native views, editing permissions, cancelled renames, contrast, and live appearance changes passed.");
}

static void checkHelpMenu(id controller)
{
    NSMenu* edit = [[[NSApp mainMenu] itemWithTitle:@"Edit"] submenu];
    requireInterface(edit && [[edit itemWithTitle:@"Copy"] action] == @selector(copy:) &&
                     [[edit itemWithTitle:@"Select All"] action] == @selector(selectAll:), @"Standard Edit commands are missing.");
    NSMenu* find = [[edit itemWithTitle:@"Find"] submenu];
    requireInterface([[find itemWithTitle:@"Find…"] action] == @selector(performTextFinderAction:), @"The native Find command is missing.");
    NSMenu* menu = [NSApp helpMenu];
    requireInterface(menu && [[[[NSApp mainMenu] itemArray] lastObject] submenu] == menu,
                     [NSString stringWithFormat:@"The native Help menu is not registered at the end of the menu bar.  Registered: %@; menus: %@; Help items: %@",
                         [menu title], [[[NSApp mainMenu] itemArray] valueForKey:@"title"], [[menu itemArray] valueForKey:@"identifier"]]);
    [menu update];
    NSMutableDictionary* items = [NSMutableDictionary dictionary];
    for (NSMenuItem* item in [menu itemArray])
        if ([[item identifier] hasPrefix:@"ASHelp"])
        {
            requireInterface([item view] == nil && [item isEnabled], @"A Help action is custom-drawn or unavailable without a Neo.");
            items[[item identifier]] = item;
        }
    NSMenuItem* guide = items[@"ASHelpGuide"];
    requireInterface([guide target] == NSApp && [guide action] == @selector(showHelp:) &&
                     [[guide keyEquivalent] isEqualToString:@"?"] && [guide keyEquivalentModifierMask] == NSEventModifierFlagCommand,
                     @"The standard Help command or shortcut is missing.");
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSMenuItem* notes = items[@"ASHelpReleaseNotes"];
    NSURL* releaseURL = [notes representedObject];
    requireInterface([[notes title] containsString:version] && [[releaseURL host] isEqualToString:@"github.com"] &&
                     [[releaseURL path] isEqualToString:[NSString stringWithFormat:@"/koralatov/alphasync/releases/tag/v%@", version]],
                     @"Release notes do not point to the installed app version.");
    NSMenuItem* licence = items[@"ASHelpLicence"];
    NSString* helpFolder = [[bundle resourcePath] stringByAppendingPathComponent:[bundle objectForInfoDictionaryKey:@"CFBundleHelpBookFolder"]];
    NSString* licenceHTML = [NSString stringWithContentsOfFile:[helpFolder stringByAppendingPathComponent:@"licence.html"] encoding:NSUTF8StringEncoding error:NULL];
    requireInterface([licence target] == controller && [licence action] == NSSelectorFromString(@"actionShowLicence:") &&
                     [licenceHTML containsString:@"name=\"alphasync-licence\""], @"The offline licence page or Help anchor is missing.");
    NSURL* repository = [items[@"ASHelpRepository"] representedObject];
    requireInterface([[repository absoluteString] isEqualToString:@"https://github.com/koralatov/alphasync"], @"The project link points to the wrong repository.");
    for (NSString* identifier in @[@"ASHelpReportIssue", @"ASHelpContact"])
    {
        NSMenuItem* item = items[identifier];
        requireInterface([item target] == controller && [item action] == NSSelectorFromString(@"actionOpenHelpLink:") &&
                         [[item title] hasSuffix:@"…"], @"A support command has the wrong target or omits its input ellipsis.");
        NSURLComponents* components = [NSURLComponents componentsWithURL:[item representedObject] resolvingAgainstBaseURL:NO];
        NSMutableDictionary* query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem* parameter in [components queryItems]) query[[parameter name]] = [parameter value];
        requireInterface([query[@"body"] containsString:[NSString stringWithFormat:@"AlphaSync %@ (build %@)", version,
            [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]]] && [query[@"body"] containsString:@"macOS:"],
            @"A support link lost its correctly encoded app and system details.");
        if ([identifier isEqualToString:@"ASHelpContact"])
            requireInterface([[components scheme] isEqualToString:@"mailto"] && [[components path] isEqualToString:@"mike@koralatov.com"] &&
                             [query[@"subject"] isEqualToString:[NSString stringWithFormat:@"AlphaSync %@ Support", version]],
                             @"Contact Us has the wrong recipient or subject.");
        else
            requireInterface([[components scheme] isEqualToString:@"https"] && [[components host] isEqualToString:@"github.com"] &&
                             [[components path] isEqualToString:@"/koralatov/alphasync/issues/new"] &&
                             [query[@"body"] containsString:@"steps to reproduce"] && [query[@"body"] containsString:@"Expected behaviour:"],
                             @"Issue reporting has the wrong destination or lost its report template.");
    }
    puts("Native Help registration, shortcut, offline licence, version-specific notes, and support-link destinations passed without opening external apps.");
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

        // Finish pending AppKit launch callbacks before inspecting the menu.
        NSDate* helpDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (![[[[NSApp helpMenu] itemArray] valueForKey:@"identifier"] containsObject:@"ASHelpGuide"] && [helpDeadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];

        fputs("Interface check: checking Help commands and destinations.\n", stderr);
        checkHelpMenu(controller);

        fputs("Interface check: checking connection window transitions.\n", stderr);
        checkConnectionStates(controller);
        fputs("Interface check: checking Clear warning default and button responses.\n", stderr);
        checkClearConfirmation(controller);

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
        checkInspectorLayout([controller valueForKey:@"inspectorController"]);
        fputs("Interface check: checking read-only file windows.\n", stderr);
        checkFileViews(controller);
        fputs("Interface check: checking Preferences settings and layout.\n", stderr);
        checkPreferences(controller);
        fputs("Interface check: creating the backup window.\n", stderr);
        NSWindowController* backup = [[NSClassFromString(@"ASBackupController") alloc] init];
        BOOL loaded = [backup window] != nil;
        requireInterface(loaded, @"The backup window did not load.");
        fputs("Interface check: checking backup results.\n", stderr);
        if (loaded) checkBackupResults(backup);
        if (loaded)
        {
            fputs("Interface check: checking optional backup logs.\n", stderr);
            checkBackupLogs(controller, backup);
        }
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
