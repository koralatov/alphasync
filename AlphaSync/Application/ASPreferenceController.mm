/** @file   ASPreferenceController.mm
 *  @brief
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

#import "ASPreferenceController.h"
#import "ASApplicationContoller.h"
#import <ServiceManagement/ServiceManagement.h>

static NSTextField* ASPreferenceNote(NSString* text)
{
    NSTextField* field = [NSTextField wrappingLabelWithString:text];
    [field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [field setTextColor:[NSColor secondaryLabelColor]];
    return field;
}

static NSStackView* ASPreferenceColumn(NSArray<NSView*>* views, CGFloat spacing)
{
    NSStackView* stack = [NSStackView stackViewWithViews:views];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setDistribution:NSStackViewDistributionFill];
    [stack setAlignment:NSLayoutAttributeLeading];
    [stack setSpacing:spacing];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    for (NSView* view in views)
        [[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
    return stack;
}

static NSStackView* ASPreferenceSection(NSString* title, NSArray<NSView*>* views)
{
    NSTextField* heading = [NSTextField labelWithString:title];
    [heading setFont:[NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]];
    return ASPreferenceColumn([@[heading] arrayByAddingObjectsFromArray:views], 8);
}

static NSBox* ASPreferenceSeparator(void)
{
    NSBox* separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    [separator setBoxType:NSBoxSeparator];
    [[separator heightAnchor] constraintEqualToConstant:1].active = YES;
    return separator;
}

@interface ASPreferenceController ()
- (void)updateBackupFolder;
- (void)fitWindowToContent;
@end

@implementation ASPreferenceController


/** Raise an error if the default constructor is used.
 */
- (id)init
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}


- (id)initWithAppController:(ASApplicationController*)controller
{
    if ((self = [super initWithWindow:nil]))
    {
        applicationController = [controller retain];
    }
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [applicationController release];
    [super dealloc];
}


- (NSInteger)displayOption
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:kASPreferenceKeyFilter];
}


- (NSString*)backupFolder
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kASPreferenceKeyBackupFolder];
}

- (BOOL)autoRun
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kASPreferenceKeyAutoRun];
}



- (void)loadWindow
{
    NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 600)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    [window setTitle:@"AlphaSync Preferences"];
    [window setReleasedWhenClosed:NO];
    [window setAutorecalculatesKeyViewLoop:YES];
    [self setWindow:window];

    outletFilterOption = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
    NSArray* filters = @[@"AlphaWord files", @"AlphaWord and dictionary", @"All files"];
    for (NSUInteger index = 0; index < [filters count]; ++index)
    {
        [outletFilterOption addItemWithTitle:filters[index]];
        [[outletFilterOption lastItem] setTag:(NSInteger)index];
    }
    [outletFilterOption setTarget:self];
    [outletFilterOption setAction:@selector(actionFilterOption:)];
    [outletFilterOption setAccessibilityLabel:@"Files shown and backed up"];

    outputFormatField = [NSTextField labelWithString:@"UTF-8"];
    [outputFormatField setAccessibilityLabel:@"Export format"];
    NSGridView* files = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"Show:"], outletFilterOption],
        @[[NSGridCell emptyContentView], ASPreferenceNote(@"Quick Backup includes the files shown in the main window.")],
        @[[NSTextField labelWithString:@"Save as:"], outputFormatField],
        @[[NSGridCell emptyContentView], ASPreferenceNote(@"Exports and backups use UTF-8.  Imports accept MacASCII (Mac Roman), UTF-8, and UTF-16.")]
    ]];
    [files setColumnSpacing:12];
    [files setRowSpacing:6];
    [files setRowAlignment:NSGridRowAlignmentFirstBaseline];
    [[files columnAtIndex:0] setXPlacement:NSGridCellPlacementTrailing];
    [[files columnAtIndex:1] setXPlacement:NSGridCellPlacementFill];
    [[files rowAtIndex:1] setBottomPadding:8];

    backupFolderPath = [[[NSPathControl alloc] initWithFrame:NSZeroRect] autorelease];
    [backupFolderPath setPathStyle:NSPathStyleStandard];
    [backupFolderPath setEditable:NO];
    [backupFolderPath unregisterDraggedTypes];
    [backupFolderPath setAccessibilityLabel:@"Quick Backup folder"];
    [backupFolderPath setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [backupFolderPath setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [[backupFolderPath widthAnchor] constraintGreaterThanOrEqualToConstant:100].active = YES;
    chooseFolderButton = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(actionBackupFolder:)];
    [chooseFolderButton setAccessibilityLabel:@"Choose a Quick Backup folder"];
    [chooseFolderButton setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* folder = [NSStackView stackViewWithViews:@[backupFolderPath, chooseFolderButton]];
    [folder setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [folder setDistribution:NSStackViewDistributionFill];
    [folder setAlignment:NSLayoutAttributeCenterY];
    [folder setSpacing:8];

    outletAutoRun = [NSButton checkboxWithTitle:@"Open AlphaSync when a NEO is connected" target:self action:@selector(actionAutoRun:)];

    automaticLaunchStatusField = [NSTextField wrappingLabelWithString:@""];
    [automaticLaunchStatusField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [automaticLaunchStatusField setTextColor:[NSColor secondaryLabelColor]];
    [automaticLaunchStatusField setSelectable:YES];
    loginItemsButton = [NSButton buttonWithTitle:@"Open Login Items Settings" target:self action:@selector(openLoginItemsSettings:)];
    NSStackView* settings = [NSStackView stackViewWithViews:@[loginItemsButton]];
    [settings setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [settings setAlignment:NSLayoutAttributeLeading];

    NSButton* help = [NSButton buttonWithTitle:@"" target:self action:@selector(actionPreferenceHelp:)];
    [help setBezelStyle:NSBezelStyleHelpButton];
    [help setToolTip:@"Preferences Help"];
    [help setAccessibilityLabel:@"Preferences Help"];
    NSView* spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    NSStackView* footer = [NSStackView stackViewWithViews:@[ASPreferenceNote(@"Changes take effect immediately."), spacer, help]];
    [footer setDistribution:NSStackViewDistributionFill];
    [footer setAlignment:NSLayoutAttributeCenterY];
    [footer setSpacing:8];

    NSStackView* form = ASPreferenceColumn(@[
        ASPreferenceSection(@"Files", @[files]),
        ASPreferenceSeparator(),
        ASPreferenceSection(@"Backups", @[folder, ASPreferenceNote(@"Quick Backup saves a separate copy of your files in this folder.")]),
        ASPreferenceSeparator(),
        ASPreferenceSection(@"Automatic opening", @[outletAutoRun, automaticLaunchStatusField, settings]),
        ASPreferenceSeparator(),
        footer
    ], 18);
    NSView* content = [window contentView];
    [content addSubview:form];
    [NSLayoutConstraint activateConstraints:@[
        [[form widthAnchor] constraintEqualToConstant:512],
        [[form leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:24],
        [[form trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-24],
        [[form topAnchor] constraintEqualToAnchor:[content topAnchor] constant:24],
        [[form bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-20]
    ]];
    [window setInitialFirstResponder:outletFilterOption];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [outletFilterOption selectItemWithTag:[self displayOption]];
    [self updateBackupFolder];
    [outletAutoRun setState:[self autoRun] ? NSControlStateValueOn : NSControlStateValueOff];
    [self refreshAutomaticLaunchStatus:nil];
    [[self window] center];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAutomaticLaunchStatus:)
                                                name:NSApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAutomaticLaunchStatus:)
                                                name:NSWindowDidBecomeKeyNotification object:[self window]];
}

- (void)updateBackupFolder
{
    NSString* folder = [self backupFolder];
    [backupFolderPath setURL:[NSURL fileURLWithPath:folder isDirectory:YES]];
    [backupFolderPath setToolTip:folder];
}

- (void)fitWindowToContent
{
    NSWindow* window = [self window];
    NSSize size = [[window contentView] fittingSize];
    // Preserve the top edge when a system status needs more (or less) room.
    NSRect frame = [window frame];
    [window setContentSize:size];
    NSRect resized = [window frame];
    [window setFrameOrigin:NSMakePoint(NSMinX(frame), NSMaxY(frame) - NSHeight(resized))];
}

- (void)refreshAutomaticLaunchStatus:(NSNotification*)notification
{
    (void)notification;
    [automaticLaunchStatusField setStringValue:[applicationController automaticLaunchStatus]];
    if (@available(macOS 13.0, *)) [loginItemsButton setHidden:NO];
    else [loginItemsButton setHidden:YES];
    [self fitWindowToContent];
}

- (void)openLoginItemsSettings:(id)sender
{
    (void)sender;
    if (@available(macOS 13.0, *)) [SMAppService openSystemSettingsLoginItems];
}




- (IBAction)actionFilterOption:(id)sender
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSInteger oldOption = [defaults integerForKey:kASPreferenceKeyFilter];

    NSInteger newOption;

    switch ([sender selectedTag])
    {
        case 0:     newOption = kASPreferenceOptionFilterAlphawordOnly;             break;
        case 1:     newOption = kASPreferenceOptionFilterAlphawordAndDictionary;    break;
        case 2:     newOption = kASPreferenceOptionFilterAll;                       break;
        default:
            assert(0);  // invalid UI tag
            newOption = kASPreferenceOptionFilterAlphawordOnly;
            break;
    }

    if (newOption != oldOption)
    {
        [defaults setInteger:newOption forKey:kASPreferenceKeyFilter];
        [defaults synchronize];
        [applicationController reloadDeviceData:self];
    }
}



- (IBAction)actionBackupFolder:(id)sender
{
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:YES];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setTitle:@"Choose a Quick Backup folder"];
    [panel setPrompt:@"Choose"];

    [panel setDirectoryURL:[NSURL fileURLWithPath:[self backupFolder] isDirectory:YES]];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && [panel URL])
        {
            [[NSUserDefaults standardUserDefaults] setObject:[[panel URL] path]
                                                     forKey:kASPreferenceKeyBackupFolder];
            [self updateBackupFolder];
        }
    }];
}

- (IBAction)actionAutoRun:(id)sender
{
    NSControlStateValue state = [(NSButton*)sender state];
    [[NSUserDefaults standardUserDefaults] setBool:((NSControlStateValueOn == state) ? YES : NO) forKey:kASPreferenceKeyAutoRun];
    [outletAutoRun setState:[self autoRun] ? NSControlStateValueOn : NSControlStateValueOff];
    [applicationController setupAutoRun:0.0];
    [self refreshAutomaticLaunchStatus:nil];
}

- (IBAction)actionPreferenceHelp:(id)sender
{
    (void)sender;

    CFBundleRef applicationBundle = CFBundleGetMainBundle();
    if (applicationBundle)
    {
        CFTypeRef bookName = CFBundleGetValueForInfoDictionaryKey(applicationBundle, CFSTR("CFBundleHelpBookName"));
        if (bookName && CFGetTypeID(bookName) == CFStringGetTypeID())
        {
            // Display the help.
            [[NSHelpManager sharedHelpManager] openHelpAnchor:(NSString*)kASPreferenceHelpAnchor inBook:(NSString*)bookName];
        }
    }
}


@end
