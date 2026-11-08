/** @file   ASApplicationContoller.mm
 *  @brief  Application controller class. This is responsible for creating and managing the device
 *          driver and user interface.
 *
 *
 *  Copyright (c) 2008-2013, tSoniq. http://tsoniq.com
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *
 *  	*	Redistributions of source code must retain the above copyright notice, this list of
 *  	    conditions and the following disclaimer.
 *  	*	Redistributions in binary form must reproduce the above copyright notice, this list
 *  	    of conditions and the following disclaimer in the documentation and/or other materials
 *  	    provided with the distribution.
 *  	*	Neither the name of tSoniq nor the names of its contributors may be used to endorse
 *  	    or promote products derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 *  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "ASApplicationContoller.h"
#import "ASInspectorWindowController.h"
#import "ASAboutWindowController.h"
#import "AQFileUtilities.h"
#import "aq_launcher.h"
#import "aq_launcherconfig.h"

using namespace ts;

#pragma mark    Forward Declarations

/** The launcher application name.
 */

/** The application's bundle ID. This is used by the launcher to start the application
 *  when a device is connected. It must match the value in the applications info.plist file.
 */
#define kASApplicationBundleID      @"com.tsoniq.AlphaSync"


/** The name of the application support folder.
 */
#define kASApplicationSupportFolder @"~/Library/Application Support/AlphaSync"


/** Enumeration used to select the colour of the status indicator light.
 */
enum ASAlertStatus
{
    kASAlertStatusGreen,        /**< Device is idle or functioning correctly. */
    kASAlertStatusYellow,       /**< Device is connecting and functioning correctly. */
    kASAlertStatusRed           /**< Last operation returned an error status. */
};

@interface ASApplicationController(PrivateAPI)
- (void)uninstall;
- (void)deviceControllerNotification:(NSNotification*)notification;
- (void)displayMemoryStatus;
- (void)displayStatusTimerDone;
- (void)setStatusBusy:(NSString*)actionName;
- (void)setStatusBusy:(NSString*)actionName timeout:(float)seconds alertStatus:(ASAlertStatus)alertStatus;
- (void)setStatusError:(NSString*)errorName;
- (void)setStatusIdle;
- (void)setStatusImmediateIdle;
- (void)setupToolbar;
- (void)setupConnectionView;
- (void)updateMainWindowConnectionState;
- (void)resizeMainWindowToSize:(NSSize)size;
- (void)updateInspectorDisplay;
@end


static NSString* kToolbarIdentifierMainWindow   = @"Toolbar:MainWindow";
static NSString* kToolbarItemIdentifierInfo     = @"ToolbarItem:Info";
static NSString* kToolbarItemIdentifierBackup   = @"ToolbarItem:Backup";
static NSString* kToolbarItemIdentifierDelete   = @"ToolbarItem:Delete";

static const NSInteger kMenuItemTagBackup   = 100;


@implementation ASApplicationController


/** Class initialisation. This is called once before any objects are instantiated by the class.
 *  It is used here to initialise the user defaults.
 */
+ (void)initialize
{
    NSMutableDictionary* defaults = [NSMutableDictionary dictionary];

    NSNumber* defaultFilter = [NSNumber numberWithInt:kASPreferenceDefaultFilter];
    NSString* defaultBackupFolder = [kASPreferenceDefaultBackupFolder stringByExpandingTildeInPath];

    [defaults setObject:defaultFilter forKey:kASPreferenceKeyFilter];
    [defaults setObject:defaultBackupFolder forKey:kASPreferenceKeyBackupFolder];

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}




- (id)init
{
    if ((self = [super init]))
    {
        appIsUninstalling = FALSE;
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [fileViewerContentView release];
    [connectionContentView release];
    [toolbar release];
    [preferenceController release];
    [aboutController release];
    [deviceController release];
    [statusDisplayTimer invalidate];
    [launcherInstallPath release];
    [automaticLaunchError release];
    [iconDisconnected release];
    [iconRed release];
    [iconYellow release];
    [iconGreen release];
    [iconToolbarInfo release];
    [iconToolbarBackup release];
    [iconToolbarDelete release];
    [super dealloc];
}


- (void)awakeFromNib
{
    [outletMainWindow setDelegate:self];
    [NSApp setDelegate:self];

    iconDisconnected = [[NSImage imageNamed:NSImageNameStatusNone] retain];
    iconRed = [[NSImage imageNamed:NSImageNameStatusUnavailable] retain];
    iconYellow = [[NSImage imageNamed:NSImageNameStatusPartiallyAvailable] retain];
    iconGreen = [[NSImage imageNamed:NSImageNameStatusAvailable] retain];
    iconToolbarInfo = [[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:@"Information"] retain];
    iconToolbarBackup = [[NSImage imageWithSystemSymbolName:@"externaldrive" accessibilityDescription:@"Back Up"] retain];
    iconToolbarDelete = [[NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"Clear Files"] retain];

    [outletStatusImage setImageFrameStyle:NSImageFrameNone];
    [outletStatusImage setImageAlignment:NSImageAlignCenter];
    [outletStatusImage setImageScaling:NSImageScaleProportionallyDown];

    [outletProgressIndicator stopAnimation:self];
    [outletProgressIndicator setUsesThreadedAnimation:YES];
    [self setStatusImmediateIdle];

    [self setupToolbar];

    [self setupAutoRun:0.0];

    [outletFileView setRowSizeStyle:NSTableViewRowSizeStyleDefault];
    // Older nibs stored a white background instead of an adaptive AppKit colour.
    [outletFileView setBackgroundColor:[NSColor controlBackgroundColor]];
    [[outletFileView enclosingScrollView] setBackgroundColor:[NSColor controlBackgroundColor]];
    for (NSTableColumn* column in [outletFileView tableColumns])
    {
        [[column headerCell] setTextColor:[NSColor labelColor]];
        [[column headerCell] setBackgroundColor:[NSColor controlColor]];
    }

    // Setup drag and drop.
    [outletFileView registerForDraggedTypes:[NSArray arrayWithObjects:NSPasteboardTypeString, NSPasteboardTypeFileURL, nil]];
    [outletFileView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
    [outletFileView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
    [outletFileView setAutoresizesOutlineColumn:NO];

    // Keep the initial window compact, with most of its width available for names.
    [outletFileView setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
    [[outletFileView tableColumnWithIdentifier:@"Size"] setWidth:130.0];
    NSSize initialSize = [[outletMainWindow contentView] bounds].size;
    initialSize.width = 480.0;
    [outletMainWindow setContentSize:initialSize];

    deviceController = [[ASDeviceController alloc] init];
    if (!deviceController)
    {
        // REVIEW: display error dialogue and exit
        NSLog(@"Failed to initialise device controller");
    }
    [[deviceController systemRoot] setDelegate:self];     // This object will receive ASDeviceAccessProtocol delgate events

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerDeviceDetected object:nil];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerDeviceConnected object:nil];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerDeviceDisconnected object:nil];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerDataChanged object:nil];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerTaskChanged object:nil];
    [nc addObserver:self selector:@selector(deviceControllerNotification:) name:kASDeviceControllerError object:nil];

    dataSource = [[ASNodeDataSource alloc] init];
    [dataSource setDeviceController:deviceController];
    [outletFileView setDataSource:dataSource];
    [outletFileView setDelegate:self];

    [self setupConnectionView];
    [self updateMainWindowConnectionState];

    // Interface checks must not capture a connected NEO or change login-item registration.
    if (![[[NSProcessInfo processInfo] arguments] containsObject:@"--smoke-test"])
        [deviceController enable];
    [dataSource reloadData:outletFileView];

    [self displayMemoryStatus];
}


/** Keep the original file viewer intact while the same window waits for a NEO.
 */
- (void)setupConnectionView
{
    fileViewerContentView = [[outletMainWindow contentView] retain];
    fileViewerWindowSize = [outletMainWindow frame].size;
    fileViewerMinSize = [outletMainWindow contentMinSize];
    showingFileViewer = YES;
    fileViewerToolbarVisible = [toolbar isVisible];

    connectionContentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 200)];
    connectionSymbol = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
    NSImage* symbol = [NSImage imageWithSystemSymbolName:@"cable.connector" accessibilityDescription:@"USB connection"];
    [connectionSymbol setImage:[symbol imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:36 weight:NSFontWeightRegular]]];
    [connectionSymbol setContentTintColor:[NSColor secondaryLabelColor]];
    [connectionSymbol setImageScaling:NSImageScaleProportionallyUpOrDown];

    connectionTitle = [NSTextField labelWithString:@"No NEO connected"];
    [connectionTitle setFont:[NSFont systemFontOfSize:14 weight:NSFontWeightSemibold]];
    [connectionTitle setAlignment:NSTextAlignmentCenter];
    connectionMessage = [NSTextField wrappingLabelWithString:@"Connect your AlphaSmart NEO\nwith a USB cable to view your files."];
    [connectionMessage setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [connectionMessage setTextColor:[NSColor secondaryLabelColor]];
    [connectionMessage setAlignment:NSTextAlignmentCenter];
    [connectionMessage setPreferredMaxLayoutWidth:312];

    connectionStack = [NSStackView stackViewWithViews:@[connectionSymbol, connectionTitle, connectionMessage]];
    [connectionStack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [connectionStack setAlignment:NSLayoutAttributeCenterX];
    [connectionStack setSpacing:12];
    [connectionStack setTranslatesAutoresizingMaskIntoConstraints:NO];
    [connectionContentView addSubview:connectionStack];
    [NSLayoutConstraint activateConstraints:@[
        [[connectionSymbol widthAnchor] constraintEqualToConstant:48],
        [[connectionSymbol heightAnchor] constraintEqualToConstant:48],
        [[connectionMessage widthAnchor] constraintEqualToConstant:312],
        [[connectionStack widthAnchor] constraintEqualToConstant:312],
        [[connectionStack centerXAnchor] constraintEqualToAnchor:[connectionContentView centerXAnchor]],
        [[connectionStack centerYAnchor] constraintEqualToAnchor:[connectionContentView centerYAnchor]]
    ]];
}

- (void)resizeMainWindowToSize:(NSSize)size
{
    // Keep a full-screen window in its Space until the user leaves full screen.
    if ([outletMainWindow styleMask] & NSWindowStyleMaskFullScreen) return;
    NSRect frame = [outletMainWindow frame];
    if (NSEqualSizes(frame.size, size)) return;
    frame.origin.x += (frame.size.width - size.width) / 2;
    frame.origin.y += frame.size.height - size.height;
    frame.size = size;
    if ([outletMainWindow screen]) frame = [outletMainWindow constrainFrameRect:frame toScreen:[outletMainWindow screen]];
    BOOL animate = [outletMainWindow isVisible] && ![[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion] &&
                   ![[[NSProcessInfo processInfo] arguments] containsObject:@"--smoke-test"];
    [outletMainWindow setFrame:frame display:YES animate:animate];
}

- (void)updateMainWindowConnectionState
{
    if (!connectionContentView) return;
    BOOL connected = [[deviceController systemRoot] numberOfChildren] > 0;
    // Let a backup result or file panel finish before shrinking its parent.
    if (!connected && [outletMainWindow attachedSheet]) return;

    if (connected != showingFileViewer)
    {
        [outletMainWindow makeFirstResponder:nil];
        if (connected)
        {
            [outletMainWindow setContentMinSize:fileViewerMinSize];
            [outletMainWindow setContentView:fileViewerContentView];
            [outletMainWindow setToolbar:toolbar];
            [toolbar setVisible:fileViewerToolbarVisible];
        }
        else
        {
            if (!([outletMainWindow styleMask] & NSWindowStyleMaskFullScreen))
                fileViewerWindowSize = [outletMainWindow frame].size;
            fileViewerToolbarVisible = [toolbar isVisible];
            [outletFileView deselectAll:self];
            [self updateInspectorDisplay];
            [outletMainWindow setToolbar:nil];
            [outletMainWindow setContentView:connectionContentView];
            [outletMainWindow setContentMinSize:NSMakeSize(360, 200)];
        }
        showingFileViewer = connected;
        if (connected)
        {
            [self resizeMainWindowToSize:fileViewerWindowSize];
            [outletMainWindow makeFirstResponder:outletFileView];
        }
    }

    if (!connected)
    {
        NSSize size = NSMakeSize(360, MAX(200.0, [connectionStack fittingSize].height + 48));
        [outletMainWindow setContentMinSize:size];
        NSRect frame = [outletMainWindow frameRectForContentRect:NSMakeRect(0, 0, size.width, size.height)];
        [self resizeMainWindowToSize:frame.size];
    }
}



#pragma Device Controller Notifications



/** Handle notifications from the device controller.
 */
- (void)deviceControllerNotification:(NSNotification*)notification
{
    NSString* name = [notification name];
    if (NSOrderedSame == [name compare:kASDeviceControllerDeviceDetected])
    {
        [self setStatusBusy:@"Connecting" timeout:10.0 alertStatus:kASAlertStatusYellow];
    }
    else if (NSOrderedSame == [name compare:kASDeviceControllerDeviceConnected])
    {
        [self setStatusImmediateIdle];
        [dataSource reloadData:outletFileView];
    }
    else if (NSOrderedSame == [name compare:kASDeviceControllerDeviceDisconnected])
    {
        [self setStatusImmediateIdle];
        [dataSource reloadData:outletFileView];
    }
    else if ([name isEqualToString:kASDeviceControllerDataChanged])
    {
        [dataSource reloadData:outletFileView];
        [self updateInspectorDisplay];
    }
    else if ([name isEqualToString:kASDeviceControllerError]) [self setStatusError:[notification object]];

    [outletFileView setEnabled:![deviceController isBusy]];
    [toolbar validateVisibleItems];
    [self updateMainWindowConnectionState];
}


#pragma mark -
#pragma mark Inspector

- (void)updateInspectorDisplay
{
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:16];
    NSIndexSet* selectedRows = [outletFileView selectedRowIndexes];
    NSUInteger row = [selectedRows firstIndex];
    while (NSNotFound != row)
    {
        id item = [outletFileView itemAtRow:(NSInteger)row];
        [array addObject:item];
        row = [selectedRows indexGreaterThanIndex:row];
    }

    [inspectorController setDisplay:array];
}


#pragma mark -
#pragma mark Actions


- (IBAction)actionDelete:(id)sender
{
    (void)sender;

    if ([deviceController isBusy] || [outletFileView numberOfSelectedRows] != 1) return;
    ASNode* selected = [outletFileView itemAtRow:[outletFileView selectedRow]];
    if (![selected conformsToProtocol:@protocol(ASDeleteProtocol)] || ![self deviceWillDelete:selected sender:selected]) return;
    [deviceController performTaskForNode:selected refresh:YES task:^id(ASNode* working) {
        return @([(id<ASDeleteProtocol>)working deleteSelf]);
    } completion:^(id result, NSString* error) {
        (void)result;
        [self deviceDidDelete:selected error:error sender:selected];
    }];
}


- (IBAction)actionInfo:(id)sender
{
    (void)sender;

    if (! inspectorController) inspectorController = [[ASInspectorWindowController alloc] init];
    [self updateInspectorDisplay];
    [inspectorController showWindow:self];
}


- (IBAction)actionBackup:(id)sender
{
    (void)sender;

    if (!backupController) backupController = [[ASBackupController alloc] init];
    [backupController runBackupFor:[deviceController systemRoot] controller:deviceController modalForWindow:outletMainWindow];
}


- (IBAction)actionOpenBackupFolder:(id)sender
{
    (void)sender;

    NSString* path = [[NSUserDefaults standardUserDefaults] stringForKey:kASPreferenceKeyBackupFolder];
	[[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}



- (IBAction)actionShowPreferences:(id)sender
{
    (void)sender;

    if (!preferenceController) preferenceController = [[ASPreferenceController alloc] initWithAppController:self];
    [preferenceController showWindow:self];
}

- (IBAction)actionShowAbout:(id)sender
{
    (void)sender;
    if (!aboutController) aboutController = [[ASAboutWindowController alloc] init];
    [aboutController showWindow:self];
}


- (IBAction)actionUninstall:(id)sender
{
    (void)sender;
    NSAlert* alert = [[NSAlert alloc] init];
    [alert setAlertStyle:NSAlertStyleCritical];
    [[alert addButtonWithTitle:@"Cancel"] setKeyEquivalent:@"\033"];
    [[alert addButtonWithTitle:@"Uninstall"] setKeyEquivalent:@"\r"];
    [alert setMessageText:@"Uninstall AlphaSync?"];
    [alert setInformativeText:@"The application and supporting files will be moved to the trash."];

    NSModalResponse button = [alert runModal];
    BOOL shouldProceed = (button == NSAlertSecondButtonReturn);
    [alert release];

    if (shouldProceed) [self uninstall];
}


- (IBAction)reloadDeviceData:(id)sender
{
    (void)sender;
    [outletFileView deselectAll:self];
    [deviceController reloadAllDevices];
    [dataSource reloadData:outletFileView];

    [self displayMemoryStatus];
    [self updateInspectorDisplay];
}


#pragma mark -
#pragma mark Status bar handling


/** Update the available memory display.
 */
- (void)displayMemoryStatus
{
    NSMutableArray* array = [NSMutableArray arrayWithCapacity:16];
    NSIndexSet* selectedRows = [outletFileView selectedRowIndexes];
    NSUInteger row = [selectedRows firstIndex];
    while (NSNotFound != row)
    {
        id item = [[outletFileView itemAtRow:(NSInteger)row] ancestorOfClass:[ASDeviceNode class]];;
        if (!item) break;
        [array addObject:item];
        row = [selectedRows indexGreaterThanIndex:row];
    }

    NSUInteger count = [array count];
    if (0 == count)
    {
        [outletAvailableMemory setStringValue:@""];
    }
    else if (1 == count)
    {
        ASDeviceNode* deviceNode = [array objectAtIndex:0];
        double availableRam = double([deviceNode availableRam]) / 1024.0;
        [outletAvailableMemory setStringValue:[NSString stringWithFormat:@"%3.1lf kbytes available", availableRam]];
    }
    else
    {
        [outletAvailableMemory setStringValue:@"multiple devices selected"];
    }
}


/** Callback on expiry of the status display timer. Flip back to idle.
 */
- (void)displayStatusTimerDone
{
    [statusDisplayTimer invalidate];
    statusDisplayTimer = nil;
    [self setStatusIdle];
}


/** Set busy status. The status will be maintained for a few seconds or until an explicit change is invoked.
 */
- (void)setStatusBusy:(NSString*)actionName
{
    [self setStatusBusy:actionName timeout:2.0 alertStatus:kASAlertStatusGreen];
}


/** Set busy status. The status will be maintained for the specified time or
 *  until one of setStatusIdle or setStatusBusy is invoked.
 */
- (void)setStatusBusy:(NSString*)actionName timeout:(float)seconds alertStatus:(ASAlertStatus)alertStatus
{
    NSImage* icon;

    switch (alertStatus)
    {
        case kASAlertStatusRed:
            icon = iconRed;
            [outletProgressIndicator stopAnimation:self];
            [outletProgressIndicator setHidden:YES];
            break;

        case kASAlertStatusYellow:
            icon = iconYellow;
            [outletProgressIndicator startAnimation:self];
            [outletProgressIndicator setHidden:NO];
            break;

        case kASAlertStatusGreen:
        default:
            [outletProgressIndicator startAnimation:self];
            [outletProgressIndicator setHidden:NO];
            if ([[deviceController systemRoot] numberOfChildren] > 0) icon = iconGreen;
            else icon = iconDisconnected;

    }

    [outletStatusImage setImage:icon];
    [outletStatusText setStringValue:actionName];

    if ([[deviceController systemRoot] numberOfChildren] == 0)
    {
        [connectionTitle setStringValue:alertStatus == kASAlertStatusYellow ? @"Connecting to NEO…" : @"No NEO connected"];
        [connectionMessage setStringValue:alertStatus == kASAlertStatusRed ? actionName :
            (alertStatus == kASAlertStatusYellow ? @"Wait while AlphaSync reads your files." :
             @"Connect your AlphaSmart NEO\nwith a USB cable to view your files.")];
        [self updateMainWindowConnectionState];
    }

    [outletStatusImage display];
    [outletStatusText display];
    [outletProgressIndicator display];

    if (nil != statusDisplayTimer) [statusDisplayTimer invalidate];
    statusDisplayTimer = [NSTimer scheduledTimerWithTimeInterval:seconds target:self selector:@selector(displayStatusTimerDone) userInfo:nil repeats:NO];
}


/** Set an error status. The status will be maintained for a few seconds or until an explicit change is invoked.
 */
- (void)setStatusError:(NSString*)errorName
{
    [self setStatusBusy:errorName timeout:8.0 alertStatus:kASAlertStatusRed];
}


/** Set idle status. The status is updated immediately.
 */
- (void)setStatusIdle
{
    [outletProgressIndicator stopAnimation:self];
    [outletProgressIndicator setHidden:YES];

    if (nil == statusDisplayTimer) [self setStatusImmediateIdle];
    // else wait for the last display timer to fire and call us later
}


/** Set idle status. The status is updated immediately and the display timer (if any) is canceled.
 */
- (void)setStatusImmediateIdle
{
    [connectionTitle setStringValue:@"No NEO connected"];
    [connectionMessage setStringValue:@"Connect your AlphaSmart NEO\nwith a USB cable to view your files."];
    [self updateMainWindowConnectionState];
    if (nil != statusDisplayTimer)
    {
        [statusDisplayTimer invalidate];
        statusDisplayTimer = nil;
    }


    NSString* statusName;
    NSImage* statusIcon;

    NSUInteger deviceCount = [[deviceController systemRoot] numberOfChildren];

    if (deviceCount == 0)
    {
        statusName = @"Disconnected";
        statusIcon = iconDisconnected;
    }
    else if (deviceCount == 1)
    {
        statusName = @"Connected";
        statusIcon = iconGreen;
    }
    else
    {
        statusName = [NSString stringWithFormat:@"Connected to %u devices", (unsigned)deviceCount];
        statusIcon = iconGreen;
    }

    [outletStatusText setStringValue:statusName];
    [outletStatusImage setImage:statusIcon];
    [outletProgressIndicator stopAnimation:self];
    [outletProgressIndicator setHidden:YES];

    [outletStatusText display];
    [outletStatusImage display];
    [outletProgressIndicator display];
}



#pragma mark -
#pragma mark Toolbar handling

- (void)setupToolbar
{
    toolbar = [[NSToolbar alloc] initWithIdentifier: kToolbarIdentifierMainWindow];

    [toolbar setAllowsUserCustomization: YES];
    [toolbar setAutosavesConfiguration: YES];
    [toolbar setDelegate:self];
    [outletMainWindow setToolbar:toolbar];
}



- (NSToolbarItem*)toolbar:(NSToolbar*)tbar itemForItemIdentifier:(NSString*)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted
{
    (void)tbar;
    (void)willBeInserted;

    NSToolbarItem *toolbarItem = nil;

    if ([itemIdent isEqual:kToolbarItemIdentifierInfo])
    {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdent] autorelease];

        [toolbarItem setLabel:@"Info"];
        [toolbarItem setPaletteLabel:@"Info"];
        [toolbarItem setToolTip:@"Show inspector"];
        [toolbarItem setImage:iconToolbarInfo];
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(actionInfo:)];
    }
    else if ([itemIdent isEqual:kToolbarItemIdentifierBackup])
    {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdent] autorelease];

        [toolbarItem setLabel:@"Backup"];
        [toolbarItem setPaletteLabel:@"Backup"];
        [toolbarItem setToolTip:@"Backup all files"];
        [toolbarItem setImage:iconToolbarBackup];
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(actionBackup:)];
    }
    else if ([itemIdent isEqual:kToolbarItemIdentifierDelete])
    {
        toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdent] autorelease];

        [toolbarItem setLabel:@"Clear"];
        [toolbarItem setPaletteLabel:@"Clear"];
        [toolbarItem setToolTip:@"Clear a single file, or all files belonging to an applet"];
        [toolbarItem setImage:iconToolbarDelete];
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(actionDelete:)];
    }

    return toolbarItem;
}


- (NSArray*)toolbarDefaultItemIdentifiers:(NSToolbar*)tbar
{
    (void)tbar;

    // Required delegate method:  Returns the ordered list of items to be shown in the toolbar by default
    // If during the toolbar's initialization, no overriding values are found in the user defaults, or if the
    // user chooses to revert to the default items this set will be used
    return [NSArray arrayWithObjects:
            kToolbarItemIdentifierBackup,
            NSToolbarFlexibleSpaceItemIdentifier,
            kToolbarItemIdentifierDelete,
            NSToolbarSpaceItemIdentifier,
            kToolbarItemIdentifierInfo,
            nil];
}


- (NSArray*)toolbarAllowedItemIdentifiers:(NSToolbar*)tbar
{
    (void)tbar;

    // Required delegate method:  Returns the list of all allowed items by identifier.  By default, the toolbar
    // does not assume any items are allowed, even the separator.  So, every allowed item must be explicitly listed
    // The set of allowed items is used to construct the customization palette
    return [NSArray arrayWithObjects:
            kToolbarItemIdentifierBackup,
            kToolbarItemIdentifierInfo,
            kToolbarItemIdentifierDelete,
            NSToolbarSpaceItemIdentifier,
            NSToolbarFlexibleSpaceItemIdentifier,
            NSToolbarSpaceItemIdentifier,
            nil];
}


- (BOOL)validateToolbarItem:(NSToolbarItem*)toolbarItem
{
    if ([deviceController isBusy]) return NO;
    BOOL enable = NO;

    if ([[toolbarItem itemIdentifier] isEqual:kToolbarItemIdentifierInfo])
    {
        enable = YES;
    }
    else if ([[toolbarItem itemIdentifier] isEqual:kToolbarItemIdentifierDelete])
    {
        // Only enable the delete option if there is only one item selected and that item supports the delete protocol
        if ([outletFileView numberOfSelectedRows] == 1)
        {
            id selectedItem = [outletFileView itemAtRow:[outletFileView selectedRow]];
            enable = [selectedItem conformsToProtocol:@protocol(ASDeleteProtocol)] && [selectedItem deletePermitted];
            if ([selectedItem isMemberOfClass:[ASFileNode class]])
            {
                [toolbarItem setToolTip:@"Clear the contents of a single file"];
            }
            else if ([selectedItem isMemberOfClass:[ASAppletNode class]])
            {
                [toolbarItem setToolTip:@"Clear all files belonging to an applet"];
            }
            else
            {
                [toolbarItem setToolTip:@"Clear the thing that is selected"];
            }
        }
        if (!enable)
        {
            [toolbarItem setToolTip:@"Clear the contents of one or more files"];
        }
    }
    else if ([[toolbarItem itemIdentifier] isEqual:kToolbarItemIdentifierBackup])
    {
        // Enable backup only if and when at least one device is connected
        if (0 != [[deviceController systemRoot] numberOfChildren]) enable = true;
    }

    return enable;
}



#pragma mark -
#pragma mark Menu handling


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];
    if ([deviceController isBusy] && (action == @selector(actionDelete:) || action == @selector(actionBackup:) ||
        action == @selector(reloadDeviceData:) || action == @selector(actionUninstall:))) return NO;
    BOOL enable = TRUE;
    if ([menuItem tag] == kMenuItemTagBackup)
    {
        // Enable backup only if and when at least one device is connected
        if (0 == [[deviceController systemRoot] numberOfChildren]) enable = FALSE;
    }
    return enable;
}




#pragma mark -
#pragma mark ASDeviceAccessProtocol


- (BOOL)deviceWillSave:(ASNode*)source to:(NSString*)path sender:(id)sender
{
    (void)source;

    NSString* statusText = [NSString stringWithFormat:@"Saving %@ to %@", [sender displayName], [path lastPathComponent]];
    [self setStatusBusy:statusText];
    return YES;
}


- (BOOL)deviceWillLoad:(NSString*)path sender:(id)sender
{
    (void)sender;

    NSString* statusText = [NSString stringWithFormat:@"Loading %@", [path lastPathComponent]];
    [self setStatusBusy:statusText];
    return YES;
}


- (BOOL)deviceWillReplace:(ASNode*)target with:(NSString*)path sender:(id)sender
{
    (void)path;
    (void)sender;

    NSAlert* alert = [[NSAlert alloc] init];
    [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@"\r"];
    [[alert addButtonWithTitle:@"Cancel"] setKeyEquivalent:@"\033"];
    [alert setMessageText:[NSString stringWithFormat:@"Overwrite file %@?", [target displayName]]];
    [alert setInformativeText:@"This operation can not be undone."];
    [alert setAlertStyle:NSAlertStyleWarning];

    NSModalResponse button = [alert runModal];
    BOOL shouldProceed = (button == NSAlertFirstButtonReturn);
    [alert release];

    if (shouldProceed)
    {
        NSString* statusText = [NSString stringWithFormat:@"Loading %@", [target displayName]];
        [self setStatusBusy:statusText];
    }
    return shouldProceed;
}



- (BOOL)deviceWillDelete:(ASNode*)target sender:(id)sender
{
    (void)sender;

    NSAlert* alert = [[NSAlert alloc] init];
    [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@""];
    NSButton* cancel = [alert addButtonWithTitle:@"Cancel"];
    [cancel setKeyEquivalent:@"\r"];

    if ([target isMemberOfClass:[ASFileNode class]])
    {
        [alert setMessageText:[NSString stringWithFormat:@"Clear file %@?", [target displayName]]];
        [alert setInformativeText:@"This operation can not be undone."];
        [alert setAlertStyle:NSAlertStyleWarning];
    }
    else if ([target isMemberOfClass:[ASAppletNode class]])
    {
        [alert setMessageText:[NSString stringWithFormat:@"Clear all files for %@?", [target displayName]]];
        [alert setInformativeText:@"This operation can not be undone."];
        [alert setAlertStyle:NSAlertStyleCritical];
    }
    else
    {
        [alert setMessageText:[NSString stringWithFormat:@"Clear %@?", [target displayName]]];
        [alert setInformativeText:@"This operation can not be undone."];
        [alert setAlertStyle:NSAlertStyleWarning];
    }

    [alert layout];
    [[alert window] setDefaultButtonCell:[cancel cell]];
    [[alert window] setInitialFirstResponder:cancel];
    NSModalResponse button = [alert runModal];
    BOOL shouldProceed = (button == NSAlertFirstButtonReturn);
    [alert release];

    if (shouldProceed)
    {
        NSString* statusText = [NSString stringWithFormat:@"Deleting %@", [target displayName]];
        [self setStatusBusy:statusText];
    }
    return shouldProceed;
}


- (void)deviceDidLoad:(NSString*)path error:(NSString*)error sender:(id)sender
{
    (void)path;
    (void)sender;

    if (!error) [self setStatusIdle];
    else
    {
        [self setStatusError:error];
        NSAlert* alert = [[NSAlert alloc] init];
        [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@"\r"];
        [alert setMessageText:[NSString stringWithFormat:@"Failed to load %@", [path lastPathComponent]]];
        [alert setInformativeText:error];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        [alert release];
    }

    [self displayMemoryStatus];
    [self updateInspectorDisplay];
    [outletFileView reloadData];
}


- (void)deviceDidSave:(ASNode*)source error:(NSString*)error sender:(id)sender
{
    (void)source;
    (void)sender;

    if (!error) [self setStatusIdle];
    else
    {
        [self setStatusError:error];
        NSAlert* alert = [[NSAlert alloc] init];
        [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@"\r"];
        [alert setMessageText:[NSString stringWithFormat:@"Failed to save %@", [source displayName]]];
        [alert setInformativeText:error];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        [alert release];
    }

    [self displayMemoryStatus];
    [self updateInspectorDisplay];
    [outletFileView reloadData];
}


- (void)deviceDidReplace:(ASNode*)target error:(NSString*)error sender:(id)sender
{
    (void)target;
    (void)sender;

    if (!error) [self setStatusIdle];
    else
    {
        [self setStatusError:error];
        NSAlert* alert = [[NSAlert alloc] init];
        [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@"\r"];
        [alert setMessageText:[NSString stringWithFormat:@"Failed to replace file %@", [target displayName]]];
        [alert setInformativeText:error];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        [alert release];
    }


    [self displayMemoryStatus];
    [self updateInspectorDisplay];
    [outletFileView reloadData];
}


- (void)deviceDidDelete:(ASNode*)node error:(NSString*)error sender:(id)sender
{
    (void)node;
    (void)sender;

    if (!error) [self setStatusIdle];
    else
    {
        [self setStatusError:error];
        NSAlert* alert = [[NSAlert alloc] init];
        [[alert addButtonWithTitle:@"OK"] setKeyEquivalent:@"\r"];
        [alert setMessageText:[NSString stringWithFormat:@"Failed to delete file %@", [node displayName]]];
        [alert setInformativeText:error];
        [alert setAlertStyle:NSAlertStyleWarning];
        [alert runModal];
        [alert release];
    }

    [self displayMemoryStatus];
    [self updateInspectorDisplay];
    [outletFileView reloadData];
}





#pragma mark -
#pragma mark NSOutlineView Delegate Methods



// Maintain enable state for toolbar and menu items as the displayed selection changes.
- (void)outlineViewSelectionDidChange:(NSNotification*)notification
{
    (void)notification;
    [toolbar validateVisibleItems];
    [self displayMemoryStatus];
    [self updateInspectorDisplay];
}


- (NSView*)outlineView:(NSOutlineView*)outlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item
{
    BOOL isName = [[tableColumn identifier] isEqualToString:@"Name"];
    NSTableCellView* cell = [outlineView makeViewWithIdentifier:[tableColumn identifier] owner:self];
    if (!cell)
    {
        cell = [[[NSTableCellView alloc] initWithFrame:NSZeroRect] autorelease];
        [cell setIdentifier:[tableColumn identifier]];
        NSTextField* text = [NSTextField labelWithString:@""];
        [text setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
        [text setLineBreakMode:NSLineBreakByTruncatingTail];
        [text setTranslatesAutoresizingMaskIntoConstraints:NO];
        [cell addSubview:text];
        [cell setTextField:text];

        NSLayoutXAxisAnchor* leading = [cell leadingAnchor];
        if (isName)
        {
            NSImageView* image = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
            [image setImageScaling:NSImageScaleProportionallyDown];
            [image setTranslatesAutoresizingMaskIntoConstraints:NO];
            [cell addSubview:image];
            [cell setImageView:image];
            [NSLayoutConstraint activateConstraints:@[
                [[image leadingAnchor] constraintEqualToAnchor:[cell leadingAnchor] constant:2],
                [[image centerYAnchor] constraintEqualToAnchor:[cell centerYAnchor]],
                [[image widthAnchor] constraintEqualToConstant:16],
                [[image heightAnchor] constraintEqualToConstant:16]
            ]];
            leading = [image trailingAnchor];
            [text setDelegate:self];
        }
        [NSLayoutConstraint activateConstraints:@[
            [[text leadingAnchor] constraintEqualToAnchor:leading constant:4],
            [[text trailingAnchor] constraintEqualToAnchor:[cell trailingAnchor] constant:-4],
            [[text centerYAnchor] constraintEqualToAnchor:[cell centerYAnchor]]
        ]];
    }

    [cell setObjectValue:item];
    [[cell textField] setStringValue:[dataSource outlineView:outlineView objectValueForTableColumn:tableColumn byItem:item] ?: @""];
    [[cell textField] setEditable:isName && [item isMemberOfClass:[ASFileNode class]]];
    [[cell imageView] setImage:isName ? [item smallIcon] : nil];
    return cell;
}


- (BOOL)control:(NSControl*)control textShouldBeginEditing:(NSText*)editor
{
    (void)editor;
    NSTableCellView* cell = (NSTableCellView*)[control superview];
    return ![deviceController isBusy] && [[cell objectValue] isMemberOfClass:[ASFileNode class]];
}


- (void)controlTextDidEndEditing:(NSNotification*)notification
{
    NSTextField* text = [notification object];
    NSTableCellView* cell = (NSTableCellView*)[text superview];
    id item = [cell objectValue];
    if ([[notification userInfo][@"NSTextMovement"] integerValue] != NSCancelTextMovement &&
        ![[text stringValue] isEqualToString:[item displayName]])
    {
        NSTableColumn* column = [outletFileView tableColumnWithIdentifier:@"Name"];
        [dataSource outlineView:outletFileView setObjectValue:[text stringValue] forTableColumn:column byItem:item];
    }
    // Show the cached name until the existing queued rename publishes its result.
    [text setStringValue:[item displayName]];
}



#pragma mark -
#pragma mark Window Delegate Methods


- (void)windowDidEndSheet:(NSNotification*)notification
{
    (void)notification;
    [self updateMainWindowConnectionState];
}

- (void)windowDidExitFullScreen:(NSNotification*)notification
{
    (void)notification;
    [self updateMainWindowConnectionState];
}


- (void)windowWillClose:(NSNotification*)notification
{
    (void)notification;
    [NSApp terminate:self];
}



#pragma mark -
#pragma mark Application Support and Auto Run


/** Return the path to the application support folder.
 */
- (NSString*)appSupportFolderPath
{
    NSString* path = @"~/Library/Application Support/AlphaSync";
    path = [path stringByExpandingTildeInPath];
    return path;
}


/** Return the path to the (installed) launcher application.
 */
- (NSString*)launcherInstallPath
{
    return [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"Contents/Library/LoginItems/AlphaSyncLauncher.app"];
}

/** Setup the auto-run configuration.
 *
 *  @param  secondsToWait   The number of seconds to wait before enabling auto-launching.
 */
- (void)setupAutoRun:(float)secondsToWait
{
    if (!launcherInstallPath) launcherInstallPath = [[self launcherInstallPath] retain];
    if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--smoke-test"]) return;
    BOOL shouldAutoRun = [[NSUserDefaults standardUserDefaults] boolForKey:kASPreferenceKeyAutoRun];
    if (!launcherInstallPath) return;

    [automaticLaunchError release];
    automaticLaunchError = nil;
    AQLauncherRef launcher = aq_LauncherOpen((CFStringRef)launcherInstallPath);
    if (launcher)
    {
        if (shouldAutoRun)
        {
            NSString* appID = kASApplicationBundleID;
            aq_LauncherClearLaunchItems(launcher);
            aq_LauncherAddLaunchItem(launcher, (CFStringRef)appID, 0x081e, 0xbd04);    // REVIEW: symbolic constants for the USB IDs and remove
            aq_LauncherAddLaunchItem(launcher, (CFStringRef)appID, 0x081e, 0xbd01);    // REVIEW: duplication with the USB device factory
            CFStringRef errorMessage = NULL;
            if (!aq_LauncherInstall(launcher, &errorMessage))
            {
                automaticLaunchError = [(NSString*)errorMessage copy];
                if (errorMessage) CFRelease(errorMessage);
                [self setStatusError:automaticLaunchError];
                aq_LauncherClose(launcher);
                return;
            }

            if (aq_LauncherGetStatus(launcher) == AQLauncherStatusRequiresApproval)
            {
                [self setStatusError:@"Automatic launching is awaiting approval in System Settings."];
                aq_LauncherClose(launcher);
                return;
            }
            if (secondsToWait <= 0.0) aq_LauncherStart(launcher);
            else aq_LauncherPause(launcher, secondsToWait);
        }
        else
        {
            aq_LauncherStop(launcher);          // stop existing application launching
            CFStringRef errorMessage = NULL;
            if (!aq_LauncherUninstall(launcher, &errorMessage))
            {
                automaticLaunchError = [(NSString*)errorMessage copy];
                if (errorMessage) CFRelease(errorMessage);
                [self setStatusError:automaticLaunchError];
            }
        }

        aq_LauncherClose(launcher);
    }
}


- (NSString*)automaticLaunchStatus
{
    if (automaticLaunchError) return [@"Automatic launching failed: " stringByAppendingString:automaticLaunchError];
    AQLauncherRef launcher = aq_LauncherOpen((CFStringRef)[self launcherInstallPath]);
    AQLauncherStatus status = aq_LauncherGetStatus(launcher);
    aq_LauncherClose(launcher);
    switch (status)
    {
        case AQLauncherStatusEnabled: return @"Automatic launching is enabled.";
        case AQLauncherStatusRequiresApproval: return @"Automatic launching is awaiting approval in System Settings.";
        case AQLauncherStatusUnavailable: return @"The bundled launcher could not be found.  Keep the app bundle intact.";
        case AQLauncherStatusDisabled: return @"Automatic launching is off.";
        case AQLauncherStatusUnknown:
            return [[NSUserDefaults standardUserDefaults] boolForKey:kASPreferenceKeyAutoRun] ?
                @"Automatic launching is selected.  The launcher is not running yet." : @"Automatic launching is off.";
    }
    return @"The automatic-launch status is unavailable.";
}



#pragma mark -
#pragma mark Application Delegate Methods




- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
    (void)sender;
    if (terminationPending) return NSTerminateLater;
    terminationPending = YES;
    if (!appIsUninstalling) [self setupAutoRun:60.0];
    [backupController requestStopForTermination];
    [deviceController shutdownWithCompletion:^{
        if (!appIsUninstalling) [self setupAutoRun:8.0];
        [NSApp replyToApplicationShouldTerminate:YES];
    }];
    return NSTerminateLater;
}


#pragma mark -
#pragma mark Uninstall

- (void)uninstall
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kASPreferenceKeyAutoRun];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString* applicationSupportPath = [self appSupportFolderPath];
    NSString* launcherPath = [self launcherInstallPath];

    AQLauncherRef launcher = aq_LauncherOpen((CFStringRef)launcherPath);
    if (launcher)
    {
        aq_LauncherUninstall(launcher, NULL);
        aq_LauncherClose(launcher);
    }

    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    NSURL* applicationURL = [[NSBundle mainBundle] bundleURL];
    NSMutableArray* urls = [NSMutableArray arrayWithObject:applicationURL];
    if ([[NSFileManager defaultManager] fileExistsAtPath:applicationSupportPath])
        [urls addObject:[NSURL fileURLWithPath:applicationSupportPath isDirectory:YES]];
    [workspace recycleURLs:urls completionHandler:^(NSDictionary* newURLs, NSError* error) {
        (void)newURLs;
        if (error) [self setStatusError:[error localizedDescription]];
        else
        {
            appIsUninstalling = YES;
            [NSApp terminate:self];
        }
    }];
}


@end
