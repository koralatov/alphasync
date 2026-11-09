#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        if (argc == 2 && strcmp(argv[1], "--version") == 0)
        {
            NSBundle* bundle = [NSBundle mainBundle];
            NSString* version = [NSString stringWithFormat:@"AlphaSync %@ (build %@)",
                [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
            puts([version UTF8String]);
            return 0;
        }
        return NSApplicationMain(argc, (const char**)argv);
    }
}
