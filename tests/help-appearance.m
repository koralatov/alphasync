#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface HelpNavigation : NSObject <WKNavigationDelegate>
@property BOOL finished;
@property (retain) NSError* error;
@end

@implementation HelpNavigation
- (void)dealloc { [_error release]; [super dealloc]; }
- (void)webView:(WKWebView*)view didFinishNavigation:(WKNavigation*)navigation
{
    (void)view; (void)navigation;
    self.finished = YES;
}
- (void)webView:(WKWebView*)view didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
    (void)view; (void)navigation;
    self.error = error;
    self.finished = YES;
}
- (void)webView:(WKWebView*)view didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
    [self webView:view didFailNavigation:navigation withError:error];
}
@end

static void require(BOOL passed, NSString* message)
{
    if (!passed) [NSException raise:@"HelpAppearanceCheck" format:@"%@", message];
}

static void waitFor(BOOL (^finished)(void))
{
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!finished() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    require(finished(), @"WebKit did not finish the Help check in time.");
}

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        @try
        {
            require(argc == 3, @"Supply the built Help folder and screenshot folder.");
            [NSApplication sharedApplication];
            NSURL* folder = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
            NSString* output = [NSString stringWithUTF8String:argv[2]];
            NSArray* pages = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:NULL];
            require([pages count] > 0, @"The built Help folder is empty.");
            NSWindow* window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 700)
                                                          styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
            WKWebView* web = [[[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 760, 700)] autorelease];
            HelpNavigation* navigation = [[[HelpNavigation alloc] init] autorelease];
            [web setNavigationDelegate:navigation];
            [window setContentView:web];
            [window makeKeyAndOrderFront:nil];
            NSMutableDictionary* lightColours = [NSMutableDictionary dictionary];
            NSUInteger checked = 0;
            for (NSUInteger pass = 0; pass < 3; ++pass)
            {
                BOOL dark = pass == 1;
                [NSApp setAppearance:[NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
                NSString* mode = dark ? @"dark" : (pass == 0 ? @"light" : @"light-again");
                for (NSURL* page in pages)
                {
                    if (![[page pathExtension] isEqualToString:@"html"]) continue;
                    [navigation setFinished:NO];
                    [navigation setError:nil];
                    [web loadFileURL:page allowingReadAccessToURL:folder];
                    waitFor(^BOOL { return [navigation finished]; });
                    require([navigation error] == nil, [[navigation error] localizedDescription]);
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    __block BOOL evaluated = NO;
                    __block NSDictionary* styles = nil;
                    [web evaluateJavaScript:@"({dark: matchMedia('(prefers-color-scheme: dark)').matches, scheme: getComputedStyle(document.documentElement).colorScheme, colour: getComputedStyle(document.body).color, fixed: document.body.hasAttribute('bgcolor')})"
                          completionHandler:^(id result, NSError* error) {
                        require(error == nil, [error localizedDescription]);
                        styles = [result retain];
                        evaluated = YES;
                    }];
                    waitFor(^BOOL { return evaluated; });
                    require([styles[@"dark"] boolValue] == dark, @"Help did not follow the current appearance.");
                    require([styles[@"scheme"] containsString:@"light"] && [styles[@"scheme"] containsString:@"dark"], @"Help is missing adaptive colours.");
                    require(![styles[@"fixed"] boolValue], @"Help still has a fixed page background.");
                    NSString* name = [[page lastPathComponent] stringByDeletingPathExtension];
                    if (pass == 0) lightColours[name] = styles[@"colour"];
                    else require([styles[@"colour"] isEqual:lightColours[name]] != dark, @"Help text did not change colour with the appearance.");
                    [styles release];
                    __block BOOL captured = NO;
                    [web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage* image, NSError* error) {
                        require(image != nil && error == nil, [error localizedDescription] ?: @"Help could not be rendered.");
                        NSBitmapImageRep* bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
                        NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                        NSString* filename = [NSString stringWithFormat:@"%@-help-%@.png", mode, name];
                        require([png writeToFile:[output stringByAppendingPathComponent:filename] atomically:YES], @"A Help screenshot could not be saved.");
                        captured = YES;
                    }];
                    waitFor(^BOOL { return captured; });
                    ++checked;
                }
            }
            require(checked >= 30, @"Some Help pages were not checked.");
            printf("Help pages followed Light, Dark, and restored Light appearance (%lu checks).\n", (unsigned long)checked);
            return 0;
        }
        @catch (NSException* exception)
        {
            fprintf(stderr, "Help appearance check failed: %s\n", [[exception description] UTF8String]);
            return 1;
        }
    }
}
