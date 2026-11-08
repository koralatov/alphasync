/** @file   ASInspectorWindowController.mm
 *  @brief  Controller for the device info window.
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
#import "ASInspectorWindowController.h"
#import "ASDeviceNode.h"
#import "ASAppletNode.h"
#import "ASFileNode.h"
#import "ASDevice.h"
#import "AQFileUtilities.h"

using namespace ts;

// Replace colours archived by the old nib with semantic colours.  AppKit resolves
// these again when the system appearance or accessibility settings change.
static void useSystemColours(NSView* view)
{
    if ([view isKindOfClass:[NSTextField class]])
    {
        NSTextField* text = (NSTextField*)view;
        [text setTextColor:[NSColor labelColor]];
        [text setBackgroundColor:[NSColor textBackgroundColor]];
    }
    if ([view isKindOfClass:[NSBox class]])
        [[(NSBox*)view titleCell] setTextColor:[NSColor labelColor]];
    for (NSView* child in [view subviews]) useSystemColours(child);
}

@implementation ASInspectorWindowController


- (id)init
{
    return [self initWithDisplay:nil];
}


- (id)initWithDisplay:(NSArray*)nodes
{
    if ((self = [super initWithWindowNibName:@"Inspector"]))
    {
        displayNodes = [nodes retain];
        iconNothing = [[NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:@"No Selection"] retain];

        for (int i = 0; i < kASInspectorMaxBox; i++)  showBox[i] = TRUE;
    }
    return self;
}


- (void)dealloc
{
    [displayNodes release];
    [iconNothing release];
    [super dealloc];
}


- (void)configurePanelsToShowSystem:(BOOL)showSystem showApplet:(BOOL)showApplet showFile:(BOOL)showFile
{
    BOOL showPreview = ([outletShowPreviewDisclosure state] == NSControlStateValueOn);
    BOOL showDetail = ([outletShowDetailDisclosure state] == NSControlStateValueOn);

    for (int i = 0; i < kASInspectorMaxBox; i++)  showBox[i] = TRUE;
    showBox[kASInspectorBoxPreview] = showPreview;
    showBox[kASInspectorBoxDetailSystem] = showDetail && showSystem;
    showBox[kASInspectorBoxDetailApplet] = showDetail && showApplet;
    showBox[kASInspectorBoxDetailFile] = showDetail && showFile;


    // get the original settings for reestablishing later:
    NSUInteger sizingMasks[kASInspectorMaxBox];
    for (int i = 0; i < kASInspectorMaxBox; i++)
    {
        sizingMasks[i] = [boxes[i] autoresizingMask];
        [boxes[i] setAutoresizingMask:NSViewNotSizable];
    }

    float displacement = 0.0;

    NSRect dynamicFrame[kASInspectorMaxBox];
    for (int i = 0; i < kASInspectorMaxBox; i++) dynamicFrame[i] = boxFrame[i];

    for (int i = 0; i < kASInspectorMaxBox; i++)
    {
        if (!showBox[i])
        {
            for (int j = 0; j < i; j++)
            {
                dynamicFrame[j].origin.y -= boxFrame[i].size.height;
            }
            displacement += boxFrame[i].size.height;
            [boxes[i] setHidden:YES];
        }
        else
        {
            [boxes[i] setHidden:NO];
        }
    }

    for (int i = 0; i < kASInspectorMaxBox; i++)
    {
        [boxes[i] setFrame:dynamicFrame[i]];
    }

    NSRect currentWindowFrame = [[self window] frame];
    float oldHeight = currentWindowFrame.size.height;
    float newHeight = windowFrame.size.height - displacement;
    currentWindowFrame.size.height = newHeight;
    currentWindowFrame.origin.y -= (newHeight - oldHeight);

    [[self window] setFrame:currentWindowFrame display:YES];
    [[self window] display];

    for (int i = 0; i < kASInspectorMaxBox; i++)
    {
        [boxes[i] setAutoresizingMask:sizingMasks[i]];
    }
}


- (void)setDetailSystem:(ASDeviceNode*)deviceNode setMain:(BOOL)setMain
{
    NSString* mainName = @"";
    NSString* mainType = @"";
    NSString* mainSize = @"";
    NSString* mainRamRom = @"";
    NSString* systemVersion = @"";
    NSString* systemBuild = @"";
    NSString* systemDate = @"";
    NSString* systemInfo = @"";
    NSString* systemRAM = @"";
    NSString* systemROM = @"";

    if (deviceNode)
    {
        unsigned ram = [deviceNode availableRam];
        unsigned rom = [deviceNode availableRom];

        mainName = [deviceNode displayName];
        mainType = [NSString stringWithFormat:@"System %@",[deviceNode systemVersion]];
        mainRamRom = @"";
        mainSize = @"";

        systemVersion = [deviceNode systemVersion];
        systemBuild = [deviceNode systemBuild];
        systemDate = [deviceNode systemDate];
        systemInfo = [deviceNode systemInfo];
        systemRAM = aq_FormattedFileSize(ram);
        systemROM = aq_FormattedFileSize(rom);
    }

    if (setMain)
    {
        [outletMainName setStringValue:mainName];
        [outletMainType setStringValue:mainType];
        [outletMainRamRom setStringValue:mainRamRom];
        [outletMainSize setStringValue:mainSize];
    }

    [outletSystemVersion setStringValue:systemVersion];
    [outletSystemBuild setStringValue:systemBuild];
    [outletSystemDate setStringValue:systemDate];
    [outletSystemInfo setStringValue:systemInfo];
    [outletSystemRAM setStringValue:systemRAM];
    [outletSystemROM setStringValue:systemROM];
}


- (void)setDetailApplet:(ASAppletNode*)appletNode setMain:(BOOL)setMain
{
    NSString* mainName = @"";
    NSString* mainType = @"";
    NSString* mainSize = @"";
    NSString* mainRamRom = @"";
    NSString* appletDescription = @"";
    NSString* appletInfo = @"";
    NSString* appletFlags = @"";
    NSString* appletROM = @"";
    NSString* appletRAM1 = @"";
    NSString* appletRAM2 = @"";
    NSString* appletMinFileSize = @"";
    NSString* appletMaxFileSize = @"";

    if (appletNode)
    {
        const ASApplet* applet = [appletNode applet];
        char version[16];
        snprintf(version, sizeof version, "Version %u.%u%c", applet->appletVersionMajor(), applet->appletVersionMinor(), applet->appletVersionRevision());
        char description[256];
        snprintf(description, sizeof description, "%s %u.%u%c (%s)",
            applet->appletName(),
            applet->appletVersionMajor(), applet->appletVersionMinor(), applet->appletVersionRevision(),
            applet->appletLanguageName());
        unsigned flags = applet->appletFlags();
        BOOL isHidden = (flags & kASAppletFlagsHidden) != 0;

        mainName = [appletNode displayName];
        mainType = [NSString stringWithCString:version encoding:NSWindowsCP1252StringEncoding];
        unsigned long long totalRAM = static_cast<unsigned long long>([appletNode ramUsed]) + applet->appletRamSize();
        mainSize = aq_FormattedFileSize(totalRAM);
        unsigned fileCount = [appletNode fileCount];
        if (0 == fileCount) mainRamRom = @"";
        else if (1 == fileCount) mainRamRom = @"1 file";
        else mainRamRom = [NSString stringWithFormat:@"%u files", fileCount];

        appletDescription = [NSString stringWithCString:description encoding:NSWindowsCP1252StringEncoding];
        appletInfo = [NSString stringWithCString:applet->appletInfo() encoding:NSWindowsCP1252StringEncoding];
        appletFlags = (isHidden) ? @"hidden" : @"visible";

        unsigned min = [appletNode minFileSize];
        unsigned max = [appletNode maxFileSize];
        appletMinFileSize = [appletNode fileSizeLimitKnown] ? aq_FormattedByteCount(min) : @"unavailable";
        appletMaxFileSize = ![appletNode fileSizeLimitKnown] ? @"unavailable" :
                            ((max == UINT_MAX) ? @"unlimited" : aq_FormattedByteCount(max));

        appletROM = aq_FormattedByteCount(applet->appletRomSize());
        appletRAM1 = [NSString stringWithFormat:@"%@ (workspace)", aq_FormattedByteCount(applet->appletRamSize())];
        appletRAM2 = [NSString stringWithFormat:@"%@ (files)", aq_FormattedByteCount([appletNode ramUsed])];
    }

    if (setMain)
    {
        [outletMainName setStringValue:mainName];
        [outletMainType setStringValue:mainType];
        [outletMainRamRom setStringValue:mainRamRom];
        [outletMainSize setStringValue:mainSize];
    }

    [outletAppletDescription setStringValue:appletDescription];
    [outletAppletInfo setStringValue:appletInfo];
    [outletAppletFlags setStringValue:appletFlags];
    [outletAppletROM setStringValue:appletROM];
    [outletAppletRAM1 setStringValue:appletRAM1];
    [outletAppletRAM2 setStringValue:appletRAM2];
    [outletAppletMinFileSize setStringValue:appletMinFileSize];
    [outletAppletMaxFileSize setStringValue:appletMaxFileSize];
}


- (void)setDetailFile:(ASFileNode*)fileNode setMain:(BOOL)setMain
{
    NSString* mainName = @"";
    NSString* mainType = @"";
    NSString* mainSize = @"";
    NSString* mainRamRom = @"";
    NSString* filePassword = @"";
    NSString* fileRam = @"";
    NSString* fileKey = @"";

    if (fileNode)
    {
        ASAppletNode* appletNode = [fileNode appletNode];
        mainName = [fileNode displayName];
        mainType = (appletNode) ? [appletNode displayName] : @"";
        int fileSize = [fileNode fileSize];
        mainSize = [fileNode displaySize];
        mainRamRom = @"";

        filePassword = [fileNode password];
        fileRam = aq_FormattedByteCount(static_cast<unsigned>(MAX(fileSize, 0)));
        fileKey = [fileNode displayFileSpace];
    }

    if (setMain)
    {
        [outletMainName setStringValue:mainName];
        [outletMainType setStringValue:mainType];
        [outletMainRamRom setStringValue:mainRamRom];
        [outletMainSize setStringValue:mainSize];
    }

    [outletFilePassword setStringValue:filePassword];
    [outletFileRam setStringValue:fileRam];
    [outletFileKey setStringValue:fileKey];
}


- (void)configureDisplay
{
    if (!completedAwakeFromNib) return;

    if (nil == displayNodes || [displayNodes count] == 0)
    {
        // Nothing selected
        [self configurePanelsToShowSystem:NO showApplet:NO showFile:NO];
        [outletMainIcon setImage:iconNothing];
        [outletMainName setStringValue:@"nothing selected"];
        [outletMainType setStringValue:@""];
        [outletMainRamRom setStringValue:@""];
        [outletMainSize setStringValue:@""];
        [outletPreviewAsIcon setImage:iconNothing];
        [outletPreviewAsText setHidden:YES];
        [outletPreviewAsIcon setHidden:NO];
    }
    else if ([displayNodes count] == 1)
    {
        // Single selection
        id item = [displayNodes objectAtIndex:0];
        [outletMainIcon setImage:[item largeIcon]];

        NSString* previewString = nil;
        if ([item respondsToSelector:@selector(filePreview)]) previewString = [item filePreview];
        if (previewString)
        {
            [outletPreviewAsText setStringValue:previewString];
            [outletPreviewAsText setHidden:NO];
            [outletPreviewAsIcon setHidden:YES];
        }
        else
        {
            [outletPreviewAsIcon setImage:[item largeIcon]];
            [outletPreviewAsText setHidden:YES];
            [outletPreviewAsIcon setHidden:NO];
        }

        if ([item isMemberOfClass:[ASFileNode class]])
        {
            ASFileNode* fileNode = item;
            ASAppletNode* appletNode = [fileNode appletNode];
            ASDeviceNode* deviceNode = [appletNode deviceNode];
            [self configurePanelsToShowSystem:NO showApplet:NO showFile:YES];
            [self setDetailFile:fileNode setMain:YES];
            [self setDetailApplet:appletNode setMain:NO];
            [self setDetailSystem:deviceNode setMain:NO];
        }
        else if ([item isMemberOfClass:[ASAppletNode class]])
        {
            ASFileNode* fileNode = nil;
            ASAppletNode* appletNode = item;
            ASDeviceNode* deviceNode = [appletNode deviceNode];
            [self configurePanelsToShowSystem:NO showApplet:YES showFile:NO];
            [self setDetailFile:fileNode setMain:NO];
            [self setDetailApplet:appletNode setMain:YES];
            [self setDetailSystem:deviceNode setMain:NO];
        }
        else if ([item isMemberOfClass:[ASDeviceNode class]])
        {
            ASFileNode* fileNode = nil;
            ASAppletNode* appletNode = nil;
            ASDeviceNode* deviceNode = item;
            [self configurePanelsToShowSystem:YES showApplet:NO showFile:NO];
            [self setDetailFile:fileNode setMain:NO];
            [self setDetailApplet:appletNode setMain:NO];
            [self setDetailSystem:deviceNode setMain:YES];
        }
    }
    else
    {
        // Multiple selection
        [outletMainName setStringValue:@"multiple items"];
        [self configurePanelsToShowSystem:NO showApplet:NO showFile:NO];

    }
}

- (void)awakeFromNib
{
    useSystemColours([[self window] contentView]);
    [outletPreviewAsText setTextColor:[NSColor textColor]];
    windowFrame = [[self window] frame];
    boxes[kASInspectorBoxMain] = outletBox0;
    boxes[kASInspectorBoxShowPreview] = outletBox1;
    boxes[kASInspectorBoxPreview] = outletBox2;
    boxes[kASInspectorBoxShowDetail] = outletBox3;
    boxes[kASInspectorBoxDetailSystem] = outletBox4;
    boxes[kASInspectorBoxDetailApplet] = outletBox5;
    boxes[kASInspectorBoxDetailFile] = outletBox6;

    for (int i = 0; i < kASInspectorMaxBox; i++)
    {
        boxFrame[i] = [boxes[i] frame];
    }

    completedAwakeFromNib = TRUE;
    [self configureDisplay];
}


- (void)setDisplay:(NSArray*)nodes
{
    if (nodes != displayNodes)
    {
        [displayNodes release];
        displayNodes = [nodes retain];
        [self configureDisplay];
    }
}


- (void)clearDisplay
{
    if (displayNodes)
    {
        [displayNodes release];
        [self configureDisplay];

    }
}


#pragma mark    ----------  Actions  -----------

- (IBAction)actionPreviewDisclosure:(id)sender
{
    (void)sender;
    [self configureDisplay];
}


- (IBAction)actionDetailDisclosure:(id)sender
{
    (void)sender;
    [self configureDisplay];
}


@end


