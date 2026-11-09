#import "ASFileViewWindowController.h"
#import "ASDeviceController.h"
#import "ASFileNode.h"

static NSString* const ASFileViewMonospacedKey = @"FileViewerMonospaced";

@interface ASFileViewWindowController ()
- (void)applyFont;
- (void)showText:(NSString*)text error:(NSString*)error;
@end

@implementation ASFileViewWindowController

- (id)initWithFileName:(NSString*)name
{
    NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    if ((self = [super initWithWindow:window]))
    {
        [window setTitle:name];
        [window setReleasedWhenClosed:NO];
        [window setContentMinSize:NSMakeSize(400, 300)];
        [window setDelegate:self];

        NSTextField* fontLabel = [NSTextField labelWithString:@"Font:"];
        fontStyle = [NSSegmentedControl segmentedControlWithLabels:@[@"Regular", @"Monospaced"]
                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                           target:self action:@selector(changeFontStyle:)];
        [fontStyle setAccessibilityLabel:@"Text font"];
        [fontStyle setSelectedSegment:[[NSUserDefaults standardUserDefaults] boolForKey:ASFileViewMonospacedKey] ? 1 : 0];
        NSStackView* fontBar = [NSStackView stackViewWithViews:@[fontLabel, fontStyle]];
        [fontBar setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        [fontBar setAlignment:NSLayoutAttributeCenterY];
        [fontBar setSpacing:8];

        scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)] autorelease];
        [scrollView setBorderType:NSBezelBorder];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setHasHorizontalScroller:NO];
        [scrollView setAutohidesScrollers:YES];
        [scrollView setBackgroundColor:[NSColor textBackgroundColor]];
        NSSize textSize = [scrollView contentSize];
        textView = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, textSize.width, textSize.height)] autorelease];
        [textView setEditable:NO];
        [textView setSelectable:YES];
        [textView setRichText:NO];
        [textView setImportsGraphics:NO];
        [textView setAllowsUndo:NO];
        [textView setUsesFindBar:YES];
        [textView setIncrementalSearchingEnabled:YES];
        [textView setTextColor:[NSColor textColor]];
        [textView setBackgroundColor:[NSColor textBackgroundColor]];
        [textView setTextContainerInset:NSMakeSize(16, 16)];
        [textView setMinSize:NSMakeSize(0, 0)];
        [textView setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
        [textView setVerticallyResizable:YES];
        [textView setHorizontallyResizable:NO];
        [textView setAutoresizingMask:NSViewWidthSizable];
        [[textView textContainer] setContainerSize:NSMakeSize(textSize.width, CGFLOAT_MAX)];
        [[textView textContainer] setWidthTracksTextView:YES];
        [[textView textContainer] setHeightTracksTextView:NO];
        [scrollView setDocumentView:textView];
        [self applyFont];

        progress = [[[NSProgressIndicator alloc] initWithFrame:NSZeroRect] autorelease];
        [progress setStyle:NSProgressIndicatorStyleSpinning];
        [progress setControlSize:NSControlSizeSmall];
        [progress setDisplayedWhenStopped:NO];
        [[progress widthAnchor] constraintEqualToConstant:16].active = YES;
        [[progress heightAnchor] constraintEqualToConstant:16].active = YES;
        statusLabel = [NSTextField wrappingLabelWithString:@"Reading from Neo…"];
        [statusLabel setSelectable:YES];
        [statusLabel setTextColor:[NSColor secondaryLabelColor]];
        [statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [statusLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        NSStackView* statusBar = [NSStackView stackViewWithViews:@[progress, statusLabel]];
        [statusBar setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        [statusBar setAlignment:NSLayoutAttributeCenterY];
        [statusBar setSpacing:8];
        [statusBar setDetachesHiddenViews:YES];

        NSView* content = [window contentView];
        for (NSView* view in @[fontBar, scrollView, statusBar])
        {
            [view setTranslatesAutoresizingMaskIntoConstraints:NO];
            [content addSubview:view];
        }
        [NSLayoutConstraint activateConstraints:@[
            [[fontBar leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:12],
            [[fontBar topAnchor] constraintEqualToAnchor:[content topAnchor] constant:12],
            [[fontBar trailingAnchor] constraintLessThanOrEqualToAnchor:[content trailingAnchor] constant:-12],
            [[scrollView topAnchor] constraintEqualToAnchor:[fontBar bottomAnchor] constant:12],
            [[scrollView leadingAnchor] constraintEqualToAnchor:[content leadingAnchor]],
            [[scrollView trailingAnchor] constraintEqualToAnchor:[content trailingAnchor]],
            [[scrollView heightAnchor] constraintGreaterThanOrEqualToConstant:160],
            [[scrollView bottomAnchor] constraintEqualToAnchor:[statusBar topAnchor] constant:-8],
            [[statusBar leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:12],
            [[statusBar trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-12],
            [[statusBar bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-10]
        ]];
        [window setInitialFirstResponder:textView];
        [window center];
    }
    return self;
}

- (void)dealloc
{
    [[self window] setDelegate:nil];
    [super dealloc];
}

- (void)applyFont
{
    // A zero size asks AppKit for the system default, including for the monospace font.
    NSFont* font = [fontStyle selectedSegment] == 1 ?
        [NSFont monospacedSystemFontOfSize:0 weight:NSFontWeightRegular] : [NSFont systemFontOfSize:0];
    [textView setFont:font];
}

- (IBAction)changeFontStyle:(id)sender
{
    (void)sender;
    [self applyFont];
    [[NSUserDefaults standardUserDefaults] setBool:[fontStyle selectedSegment] == 1 forKey:ASFileViewMonospacedKey];
}

- (void)loadFile:(ASFileNode*)file controller:(ASDeviceController*)controller
{
    [progress startAnimation:self];
    [controller performTaskForNode:file refresh:NO task:^id(ASNode* working) {
        NSString* text = [(ASFileNode*)working fileData];
        if (!text)
            [working setOperationError:@"AlphaSync couldn’t read the text in this file.  Check the USB connection, then close this window and open the file again."];
        return text;
    } completion:^(id result, NSString* error) {
        // Closing a loading window must not reopen it when the USB read finishes.
        if (!closed) [self showText:result error:error];
    }];
}

- (void)showText:(NSString*)text error:(NSString*)error
{
    [progress stopAnimation:self];
    [progress setHidden:YES];
    [textView setString:error ? @"" : (text ?: @"")];
    [self applyFont];
    [textView scrollRangeToVisible:NSMakeRange(0, 0)];
    [statusLabel setStringValue:error ?: ([text length] ? @"Read-only" : @"This file is empty.  Read-only.")];
    [statusLabel setTextColor:error ? [NSColor labelColor] : [NSColor secondaryLabelColor]];
}

- (void)windowWillClose:(NSNotification*)notification
{
    (void)notification;
    closed = YES;
}

@end
