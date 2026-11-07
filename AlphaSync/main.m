#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int checkInterface(void)
{
    @try
    {
        [NSApplication sharedApplication];
        NSNib* nib = [[[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:[NSBundle mainBundle]] autorelease];
        NSArray* objects = nil;
        if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) return 1;
        id controller = [NSApp delegate];
        if (!controller || ![controller valueForKey:@"outletMainWindow"] || ![controller valueForKey:@"outletFileView"]) return 1;

        // Load every window, so missing resources and broken outlet connections fail the check.
        [controller performSelector:NSSelectorFromString(@"actionShowPreferences:") withObject:nil];
        [controller performSelector:NSSelectorFromString(@"actionInfo:") withObject:nil];
        for (NSString* key in @[@"preferenceController", @"inspectorController"])
        {
            NSWindowController* windowController = [controller valueForKey:key];
            if (![windowController window]) return 1;
        }
        NSWindowController* backup = [[NSClassFromString(@"ASBackupController") alloc] init];
        BOOL loaded = [backup window] != nil;
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
