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
    if ((self = [super initWithWindowNibName:@"Preferences"]))
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



- (void)windowDidLoad
{
    [outletFilterOption selectItemWithTag:[self displayOption]];
    [outletBackupFolder setTitle:[self backupFolder]];
    [outletTextEncoding removeAllItems];
    [outletTextEncoding addItemWithTitle:@"UTF-8"];
    [outletTextEncoding setEnabled:NO];
    [outletTextEncoding setToolTip:@"Exported files always use UTF-8.  Imports accept MacASCII, UTF-8, and UTF-16."];
    [outletAutoRun setState:[self autoRun] ? NSControlStateValueOn : NSControlStateValueOff];

    // Keep the older nib intact and add enough room for the actual system status.
    NSWindow* window = [self window];
    NSView* content = [window contentView];
    NSSize size = [content frame].size;
    [content setAutoresizesSubviews:NO];
    [window setContentSize:NSMakeSize(size.width, size.height + 100)];
    for (NSView* view in [content subviews])
    {
        NSRect frame = [view frame];
        frame.origin.y += 100;
        [view setFrame:frame];
    }
    [content setAutoresizesSubviews:YES];

    automaticLaunchStatusField = [NSTextField wrappingLabelWithString:@""];
    [automaticLaunchStatusField setFrame:NSMakeRect(20, 42, size.width - 40, 48)];
    [automaticLaunchStatusField setFont:[NSFont systemFontOfSize:12]];
    [automaticLaunchStatusField setAutoresizingMask:NSViewWidthSizable];
    [content addSubview:automaticLaunchStatusField];
    loginItemsButton = [NSButton buttonWithTitle:@"Open Login Items Settings" target:self action:@selector(openLoginItemsSettings:)];
    [loginItemsButton setFrame:NSMakeRect(16, 8, 210, 28)];
    [content addSubview:loginItemsButton];
    [self refreshAutomaticLaunchStatus:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAutomaticLaunchStatus:)
                                                name:NSApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshAutomaticLaunchStatus:)
                                                name:NSWindowDidBecomeKeyNotification object:window];
}

- (void)refreshAutomaticLaunchStatus:(NSNotification*)notification
{
    (void)notification;
    [automaticLaunchStatusField setStringValue:[applicationController automaticLaunchStatus]];
    if (@available(macOS 13.0, *)) [loginItemsButton setHidden:NO];
    else [loginItemsButton setHidden:YES];
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
    [panel setTitle:@"Select new backup folder"];
    [panel setPrompt:@"Select"];

    [panel setDirectoryURL:[NSURL fileURLWithPath:[self backupFolder] isDirectory:YES]];
    [panel beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && [panel URL])
        {
            [[NSUserDefaults standardUserDefaults] setObject:[[panel URL] path]
                                                     forKey:kASPreferenceKeyBackupFolder];
            [outletBackupFolder setTitle:[self backupFolder]];
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

// Keep the action connected by the existing nib; the format field is read-only.
- (IBAction)actionTextEncoding:(id)sender
{
    (void)sender;
    [outletTextEncoding selectItemAtIndex:0];
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
