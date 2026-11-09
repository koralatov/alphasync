#import "ASAboutWindowController.h"

static NSTextField* ASAboutLabel(NSString* text, CGFloat size, NSColor* colour)
{
    NSTextField* label = [NSTextField wrappingLabelWithString:text];
    [label setAlignment:NSTextAlignmentCenter];
    [label setFont:[NSFont systemFontOfSize:size]];
    [label setTextColor:colour];
    return label;
}

static NSStackView* ASAboutColumn(NSArray<NSView*>* views, CGFloat spacing)
{
    NSStackView* stack = [NSStackView stackViewWithViews:views];
    [stack setOrientation:NSUserInterfaceLayoutOrientationVertical];
    [stack setDistribution:NSStackViewDistributionFill];
    [stack setAlignment:NSLayoutAttributeCenterX];
    [stack setSpacing:spacing];
    [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
    for (NSView* view in views)
        [[view widthAnchor] constraintEqualToAnchor:[stack widthAnchor]].active = YES;
    return stack;
}

@interface ASAboutWindowController ()
- (void)openLink:(NSButton*)sender;
@end

@implementation ASAboutWindowController

- (id)init
{
    NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 540)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO] autorelease];
    if ((self = [super initWithWindow:window]))
    {
        NSBundle* bundle = [NSBundle mainBundle];
        NSString* name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
        NSString* version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString* build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        [window setTitle:[NSString stringWithFormat:@"About %@", name]];
        [window setReleasedWhenClosed:NO];
        [window setExcludedFromWindowsMenu:YES];

        NSImageView* icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
        [icon setImage:[NSApp applicationIconImage]];
        [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
        [[icon heightAnchor] constraintEqualToConstant:96].active = YES;

        NSTextField* title = ASAboutLabel(name, 24, [NSColor labelColor]);
        [title setFont:[NSFont systemFontOfSize:24 weight:NSFontWeightBold]];
        NSTextField* versionLabel = ASAboutLabel([NSString stringWithFormat:@"Version %@ (%@)", version, build],
                                                [NSFont systemFontSize], [NSColor labelColor]);
        [versionLabel setIdentifier:@"about-version"];
        NSTextField* compatibility = ASAboutLabel([bundle objectForInfoDictionaryKey:@"ASCompatibilityDescription"],
                                                 [NSFont systemFontSize], [NSColor secondaryLabelColor]);
        [compatibility setIdentifier:@"about-compatibility"];
        NSStackView* identity = ASAboutColumn(@[title, versionLabel, compatibility], 6);

        NSTextField* description = ASAboutLabel(@"Transfer and back up\nAlphaSmart Neo files.",
                                                [NSFont systemFontSize], [NSColor labelColor]);
        NSBox* separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
        [separator setBoxType:NSBoxSeparator];
        [[separator heightAnchor] constraintEqualToConstant:1].active = YES;
        NSTextField* copyright = ASAboutLabel([bundle objectForInfoDictionaryKey:@"NSHumanReadableCopyright"],
                                              [NSFont smallSystemFontSize], [NSColor labelColor]);
        [copyright setIdentifier:@"about-copyright"];
        NSTextField* credits = ASAboutLabel(@"Original application by tSoniq\nMaintained by Koralatov",
                                            [NSFont smallSystemFontSize], [NSColor secondaryLabelColor]);

        NSArray* titles = @[@"Project", @"Release notes", @"Licence"];
        NSMutableArray* buttons = [NSMutableArray array];
        for (NSUInteger index = 0; index < [titles count]; ++index)
        {
            NSButton* button = [NSButton buttonWithTitle:titles[index] target:self action:@selector(openLink:)];
            [button setTag:(NSInteger)index];
            [button setBordered:NO];
            [button setBezelStyle:NSBezelStyleInline];
            [button setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
            [button setAttributedTitle:[[[NSAttributedString alloc] initWithString:titles[index] attributes:@{
                NSFontAttributeName: [button font], NSForegroundColorAttributeName: [NSColor linkColor]
            }] autorelease]];
            [button setAccessibilityRole:NSAccessibilityLinkRole];
            [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
            [buttons addObject:button];
        }
        NSStackView* links = [NSStackView stackViewWithViews:buttons];
        [links setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        [links setDistribution:NSStackViewDistributionEqualSpacing];
        [links setAlignment:NSLayoutAttributeCenterY];
        [links setSpacing:16];

        NSStackView* content = ASAboutColumn(@[icon, identity, description, separator, copyright, credits, links], 20);
        NSView* container = [window contentView];
        [container addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [[content widthAnchor] constraintEqualToConstant:356],
            [[content leadingAnchor] constraintEqualToAnchor:[container leadingAnchor] constant:32],
            [[content trailingAnchor] constraintEqualToAnchor:[container trailingAnchor] constant:-32],
            [[content topAnchor] constraintEqualToAnchor:[container topAnchor] constant:32],
            [[content bottomAnchor] constraintEqualToAnchor:[container bottomAnchor] constant:-28]
        ]];
        [window setContentSize:[container fittingSize]];
        [window center];
    }
    return self;
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    // Start with neutral focus each time, while keeping the links in the key-view loop.
    [[self window] makeFirstResponder:nil];
}

- (void)openLink:(NSButton*)sender
{
    NSArray* urls = @[@"https://github.com/koralatov/alphasync",
                      @"https://github.com/koralatov/alphasync/releases",
                      @"https://github.com/koralatov/alphasync/blob/master/LICENSE"];
    NSInteger index = [sender tag];
    if (index >= 0 && (NSUInteger)index < [urls count])
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urls[(NSUInteger)index]]];
}

@end
