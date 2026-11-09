#import <Cocoa/Cocoa.h>

@class ASDeviceController, ASFileNode;

@interface ASFileViewWindowController : NSWindowController <NSWindowDelegate>
{
    NSTextView* textView;
    NSScrollView* scrollView;
    NSSegmentedControl* fontStyle;
    NSTextField* statusLabel;
    NSProgressIndicator* progress;
    NSImageView* readOnlyIcon;
    BOOL closed;
}

- (id)initWithFileName:(NSString*)name;
- (void)loadFile:(ASFileNode*)file controller:(ASDeviceController*)controller;
- (IBAction)changeFontStyle:(id)sender;

@end
