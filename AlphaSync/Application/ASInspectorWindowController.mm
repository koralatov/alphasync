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
#import "ASAppletNode.h"
#import "ASFileNode.h"
#import "AQFileUtilities.h"

using namespace ts;

static const CGFloat ASInspectorWidth = 320;

static NSTextField* ASInspectorValue(void)
{
    NSTextField* field = [NSTextField wrappingLabelWithString:@""];
    [field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [field setSelectable:YES];
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return field;
}

static NSTextField* ASInspectorHeading(NSString* title)
{
    NSTextField* field = [NSTextField labelWithString:title];
    [field setFont:[NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]];
    [field setAccessibilityRole:NSAccessibilityHeadingRole];
    return field;
}

static NSStackView* ASInspectorColumn(NSArray<NSView*>* views, CGFloat spacing)
{
    NSStackView* stack = [NSStackView stackViewWithViews:views];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setAlignment:NSLayoutAttributeLeading];
    [stack setDistribution:NSStackViewDistributionFill];
    [stack setSpacing:spacing];
    [stack setDetachesHiddenViews:YES];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    for (NSView* view in views)
        [[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
    return stack;
}

static NSView* ASInspectorInset(NSView* view, CGFloat vertical)
{
    NSView* container = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [[view leadingAnchor] constraintEqualToAnchor:[container leadingAnchor] constant:16],
        [[view trailingAnchor] constraintEqualToAnchor:[container trailingAnchor] constant:-16],
        [[view topAnchor] constraintEqualToAnchor:[container topAnchor] constant:vertical],
        [[view bottomAnchor] constraintEqualToAnchor:[container bottomAnchor] constant:-vertical]
    ]];
    return container;
}

static NSBox* ASInspectorSeparator(void)
{
    NSBox* box = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    [box setBoxType:NSBoxSeparator];
    [[box heightAnchor] constraintEqualToConstant:1].active = YES;
    return box;
}

static NSGridView* ASInspectorDetails(NSArray<NSString*>* labels, NSArray<NSTextField*>* values)
{
    NSMutableArray* rows = [NSMutableArray array];
    for (NSUInteger index = 0; index < [labels count]; ++index)
    {
        NSTextField* label = [NSTextField labelWithString:labels[index]];
        [label setAlignment:NSTextAlignmentRight];
        [rows addObject:@[label, values[index]]];
    }
    NSGridView* grid = [NSGridView gridViewWithViews:rows];
    [grid setColumnSpacing:6];
    [grid setRowSpacing:5];
    [grid setRowAlignment:NSGridRowAlignmentFirstBaseline];
    [[grid columnAtIndex:0] setWidth:104];
    [[grid columnAtIndex:0] setXPlacement:NSGridCellPlacementTrailing];
    [[grid columnAtIndex:1] setXPlacement:NSGridCellPlacementFill];
    return grid;
}

@interface ASInspectorWindowController ()
- (void)buildWindow;
- (void)fitWindowToContent;
- (void)configureDisplay;
- (void)configurePanelsToShowSystem:(BOOL)system showApplet:(BOOL)applet showFile:(BOOL)file;
@end

@implementation ASInspectorWindowController

- (id)init
{
    return [self initWithDisplay:nil];
}

- (id)initWithDisplay:(NSArray*)nodes
{
    if ((self = [super initWithWindow:nil]))
    {
        displayNodes = [nodes copy];
        iconNothing = [[NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:@"No Selection"] retain];
        [self buildWindow];
        [self configureDisplay];
        [[self window] center];
    }
    return self;
}

- (void)dealloc
{
    [displayNodes release];
    [iconNothing release];
    [super dealloc];
}

- (void)buildWindow
{
    NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, ASInspectorWidth, 500)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    [window setTitle:@"Inspector"];
    [window setReleasedWhenClosed:NO];
    [window setAutorecalculatesKeyViewLoop:YES];
    [self setWindow:window];

    outletMainIcon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
    [outletMainIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
    [[outletMainIcon widthAnchor] constraintEqualToConstant:48].active = YES;
    [[outletMainIcon heightAnchor] constraintEqualToConstant:48].active = YES;
    outletMainName = ASInspectorValue();
    [outletMainName setFont:[NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]];
    outletMainType = ASInspectorValue();
    [outletMainType setTextColor:[NSColor secondaryLabelColor]];
    outletMainSize = [NSTextField labelWithString:@""];
    [outletMainSize setFont:[NSFont systemFontOfSize:[NSFont systemFontSize] weight:NSFontWeightSemibold]];
    [outletMainSize setSelectable:YES];
    [outletMainSize setAlignment:NSTextAlignmentRight];
    [outletMainSize setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    outletMainRamRom = [NSTextField labelWithString:@""];
    [outletMainRamRom setAlignment:NSTextAlignmentRight];
    [outletMainRamRom setTextColor:[NSColor secondaryLabelColor]];
    NSGridView* summary = [NSGridView gridViewWithViews:@[@[outletMainName, outletMainSize], @[outletMainType, outletMainRamRom]]];
    [summary setColumnSpacing:8];
    [summary setRowSpacing:4];
    [summary setRowAlignment:NSGridRowAlignmentFirstBaseline];
    [[summary columnAtIndex:0] setXPlacement:NSGridCellPlacementFill];
    [[summary columnAtIndex:1] setXPlacement:NSGridCellPlacementTrailing];
    [summary setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView* header = [NSStackView stackViewWithViews:@[outletMainIcon, summary]];
    [header setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [header setAlignment:NSLayoutAttributeCenterY];
    [header setDistribution:NSStackViewDistributionFill];
    [header setSpacing:12];

    previewHeading = ASInspectorHeading(@"Preview:");
    detailsHeading = ASInspectorHeading(@"More Info:");
    previewContainer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [[previewContainer heightAnchor] constraintEqualToConstant:180].active = YES;
    previewScrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, ASInspectorWidth - 32, 180)] autorelease];
    [previewScrollView setBorderType:NSBezelBorder];
    [previewScrollView setHasVerticalScroller:YES];
    [previewScrollView setAutohidesScrollers:YES];
    NSSize previewSize = [previewScrollView contentSize];
    outletPreviewAsText = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, previewSize.width, previewSize.height)] autorelease];
    [outletPreviewAsText setEditable:NO];
    [outletPreviewAsText setSelectable:YES];
    [outletPreviewAsText setRichText:NO];
    [outletPreviewAsText setImportsGraphics:NO];
    [outletPreviewAsText setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
    [outletPreviewAsText setTextColor:[NSColor textColor]];
    [outletPreviewAsText setBackgroundColor:[NSColor textBackgroundColor]];
    [outletPreviewAsText setTextContainerInset:NSMakeSize(6, 6)];
    [outletPreviewAsText setMinSize:NSMakeSize(0, previewSize.height)];
    [outletPreviewAsText setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
    [outletPreviewAsText setVerticallyResizable:YES];
    [outletPreviewAsText setHorizontallyResizable:NO];
    [outletPreviewAsText setAutoresizingMask:NSViewWidthSizable];
    [[outletPreviewAsText textContainer] setContainerSize:NSMakeSize(previewSize.width, CGFLOAT_MAX)];
    [[outletPreviewAsText textContainer] setWidthTracksTextView:YES];
    [[outletPreviewAsText textContainer] setHeightTracksTextView:NO];
    [previewScrollView setDocumentView:outletPreviewAsText];
    [previewScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [previewContainer addSubview:previewScrollView];
    outletPreviewAsIcon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
    [outletPreviewAsIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
    [outletPreviewAsIcon setTranslatesAutoresizingMaskIntoConstraints:NO];
    [previewContainer addSubview:outletPreviewAsIcon];
    [NSLayoutConstraint activateConstraints:@[
        [[previewScrollView leadingAnchor] constraintEqualToAnchor:[previewContainer leadingAnchor]],
        [[previewScrollView trailingAnchor] constraintEqualToAnchor:[previewContainer trailingAnchor]],
        [[previewScrollView topAnchor] constraintEqualToAnchor:[previewContainer topAnchor]],
        [[previewScrollView bottomAnchor] constraintEqualToAnchor:[previewContainer bottomAnchor]],
        [[outletPreviewAsIcon widthAnchor] constraintEqualToConstant:128],
        [[outletPreviewAsIcon heightAnchor] constraintEqualToConstant:128],
        [[outletPreviewAsIcon centerXAnchor] constraintEqualToAnchor:[previewContainer centerXAnchor]],
        [[outletPreviewAsIcon centerYAnchor] constraintEqualToAnchor:[previewContainer centerYAnchor]]
    ]];

    outletSystemVersion = ASInspectorValue(); outletSystemBuild = ASInspectorValue();
    outletSystemDate = ASInspectorValue(); outletSystemInfo = ASInspectorValue();
    outletSystemRAM = ASInspectorValue(); outletSystemROM = ASInspectorValue();
    systemDetails = ASInspectorDetails(@[@"System version:", @"Build:", @"Build date:", @"Info:", @"Available RAM:", @"Available ROM:"],
                                      @[outletSystemVersion, outletSystemBuild, outletSystemDate, outletSystemInfo, outletSystemRAM, outletSystemROM]);
    outletAppletDescription = ASInspectorValue(); outletAppletInfo = ASInspectorValue();
    outletAppletFlags = ASInspectorValue(); outletAppletROM = ASInspectorValue();
    outletAppletRAM1 = ASInspectorValue(); outletAppletRAM2 = ASInspectorValue();
    outletAppletMinFileSize = ASInspectorValue(); outletAppletMaxFileSize = ASInspectorValue();
    appletDetails = ASInspectorDetails(@[@"Description:", @"Copyright:", @"Visibility:", @"Minimum size:", @"Maximum size:", @"ROM usage:", @"Workspace RAM:", @"File RAM:"],
                                      @[outletAppletDescription, outletAppletInfo, outletAppletFlags, outletAppletMinFileSize, outletAppletMaxFileSize,
                                        outletAppletROM, outletAppletRAM1, outletAppletRAM2]);
    outletFilePassword = ASInspectorValue(); outletFileRam = ASInspectorValue(); outletFileKey = ASInspectorValue();
    fileDetails = ASInspectorDetails(@[@"Password:", @"RAM usage:", @"Bound to key:"], @[outletFilePassword, outletFileRam, outletFileKey]);
    emptyDetails = [NSTextField wrappingLabelWithString:@"Select one item to view its information."];
    [emptyDetails setTextColor:[NSColor secondaryLabelColor]];
    NSStackView* details = ASInspectorColumn(@[systemDetails, appletDetails, fileDetails, emptyDetails], 0);
    NSStackView* sections = ASInspectorColumn(@[
        ASInspectorInset(header, 16), ASInspectorSeparator(),
        ASInspectorInset(ASInspectorColumn(@[previewHeading, previewContainer], 10), 12), ASInspectorSeparator(),
        ASInspectorInset(ASInspectorColumn(@[detailsHeading, details], 10), 12)
    ], 0);
    NSView* content = [window contentView];
    [content addSubview:sections];
    [NSLayoutConstraint activateConstraints:@[
        [[sections widthAnchor] constraintEqualToConstant:ASInspectorWidth],
        [[sections leadingAnchor] constraintEqualToAnchor:[content leadingAnchor]],
        [[sections trailingAnchor] constraintEqualToAnchor:[content trailingAnchor]],
        [[sections topAnchor] constraintEqualToAnchor:[content topAnchor]],
        [[sections bottomAnchor] constraintEqualToAnchor:[content bottomAnchor]]
    ]];
}

- (void)fitWindowToContent
{
    NSWindow* window = [self window];
    [[window contentView] layoutSubtreeIfNeeded];
    NSSize size = [[window contentView] fittingSize];
    NSRect frame = [window frame];
    [window setContentSize:size];
    [window setFrameOrigin:NSMakePoint(NSMinX(frame), NSMaxY(frame) - NSHeight([window frame]))];
}

- (void)configurePanelsToShowSystem:(BOOL)showSystem showApplet:(BOOL)showApplet showFile:(BOOL)showFile
{
    [systemDetails setHidden:!showSystem];
    [appletDetails setHidden:!showApplet];
    [fileDetails setHidden:!showFile];
    [emptyDetails setHidden:showSystem || showApplet || showFile];
    [self fitWindowToContent];
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
        appletRAM1 = aq_FormattedByteCount(applet->appletRamSize());
        appletRAM2 = aq_FormattedByteCount([appletNode ramUsed]);
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
    [self setDetailSystem:nil setMain:NO];
    [self setDetailApplet:nil setMain:NO];
    [self setDetailFile:nil setMain:NO];
    [outletMainName setStringValue:@"No Selection"];
    [outletMainType setStringValue:@"Select an item"];
    [outletMainRamRom setStringValue:@""];
    [outletMainSize setStringValue:@""];
    [outletMainIcon setImage:iconNothing];
    [outletPreviewAsIcon setImage:iconNothing];
    [outletPreviewAsText setString:@""];
    [previewScrollView setHidden:YES];
    [outletPreviewAsIcon setHidden:NO];
    BOOL system = NO, applet = NO, file = NO;
    if ([displayNodes count] == 1)
    {
        ASNode* item = [displayNodes objectAtIndex:0];
        NSImage* icon = [item largeIcon] ?: iconNothing;
        [outletMainIcon setImage:icon];
        [outletPreviewAsIcon setImage:icon];
        if ([item respondsToSelector:@selector(filePreview)])
        {
            NSString* preview = [(ASFileNode*)item filePreview];
            if (preview)
            {
                [outletPreviewAsText setString:preview];
                [outletPreviewAsText scrollRangeToVisible:NSMakeRange(0, 0)];
                [previewScrollView setHidden:NO];
                [outletPreviewAsIcon setHidden:YES];
            }
        }
        if ([item isKindOfClass:[ASFileNode class]])
        {
            file = YES;
            [self setDetailFile:(ASFileNode*)item setMain:YES];
        }
        else if ([item isKindOfClass:[ASAppletNode class]])
        {
            applet = YES;
            [self setDetailApplet:(ASAppletNode*)item setMain:YES];
        }
        else if ([item isKindOfClass:[ASDeviceNode class]])
        {
            system = YES;
            [self setDetailSystem:(ASDeviceNode*)item setMain:YES];
        }
    }
    else if ([displayNodes count] > 1)
    {
        [outletMainName setStringValue:@"Multiple Items"];
        [outletMainType setStringValue:[NSString stringWithFormat:@"%lu items selected", (unsigned long)[displayNodes count]]];
    }
    [self configurePanelsToShowSystem:system showApplet:applet showFile:file];
}

- (void)setDisplay:(NSArray*)nodes
{
    if (nodes != displayNodes)
    {
        [displayNodes release];
        displayNodes = [nodes copy];
    }
    [self configureDisplay];
}

- (void)clearDisplay
{
    [self setDisplay:nil];
}

@end
