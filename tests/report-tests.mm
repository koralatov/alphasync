#import "../AlphaSync/Application/ASBackupReport.h"
#include <cstdio>
#include <cstdlib>
#define CHECK(value) do { if (!(value)) { std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #value); std::abort(); } } while (false)

static NSDictionary* readReport(ASBackupReport* report)
{
    NSData* data = [NSData dataWithContentsOfURL:[report reportURL]];
    return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
}

int main()
{
    @autoreleasepool
    {
        NSFileManager* manager = [NSFileManager defaultManager];
        NSString* folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSArray* entries = @[@{@"file": @"One"}, @{@"file": @"Two"}];
        NSError* error = nil;
        ASBackupReport* report = [[ASBackupReport alloc] initWithFolder:folder files:entries error:&error];
        CHECK(report && !error);
        CHECK([[[report reportURL] path] isEqualToString:[folder stringByAppendingPathComponent:@"AlphaSync Backup Log.plist"]]);
        CHECK(![manager fileExistsAtPath:[folder stringByAppendingPathComponent:@"Backup Reports"]]);
        CHECK([readReport(report)[@"status"] isEqualToString:@"in progress"]);
        CHECK([readReport(report)[@"files"][0][@"status"] isEqualToString:@"pending"]);
        CHECK([report recordFileAtIndex:0 savedPath:@"One.txt" error:nil saveError:&error]);
        CHECK([report finishWithStatus:@"complete" message:@"Finished" error:&error]);
        CHECK([readReport(report)[@"status"] isEqualToString:@"completed with failures"]);
        CHECK([report recordFileAtIndex:1 savedPath:nil error:@"Device disconnected" saveError:&error]);
        CHECK([readReport(report)[@"files"][1][@"error"] isEqualToString:@"Device disconnected"]);
        CHECK([report finishWithStatus:@"disconnected" message:@"Stopped" error:&error]);
        CHECK([readReport(report)[@"status"] isEqualToString:@"disconnected"]);
        NSURL* firstURL = [[report reportURL] retain];
        NSData* firstContents = [NSData dataWithContentsOfURL:firstURL];
        [report release];
        report = [[ASBackupReport alloc] initWithFolder:folder files:entries error:&error];
        CHECK(report && !error && ![[report reportURL] isEqual:firstURL]);
        CHECK([firstContents isEqualToData:[NSData dataWithContentsOfURL:firstURL]]);
        [firstURL release];
        CHECK([report recordFileAtIndex:0 savedPath:@"One.txt" error:nil saveError:&error]);
        CHECK([report recordFileAtIndex:1 savedPath:@"Two.txt" error:nil saveError:&error]);
        CHECK([report finishWithStatus:@"complete" message:@"Finished" error:&error]);
        CHECK([readReport(report)[@"status"] isEqualToString:@"complete"]);
        [report release];
        CHECK([manager removeItemAtPath:folder error:nil]);
        CHECK([@"file" writeToFile:folder atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        report = [[ASBackupReport alloc] initWithFolder:folder files:entries error:&error];
        CHECK(!report && error);
        CHECK([manager removeItemAtPath:folder error:nil]);
        std::puts("All saved backup reports passed.");
    }
}
