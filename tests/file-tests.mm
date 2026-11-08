#import <Foundation/Foundation.h>
#import "AQFileUtilities.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dispatch/dispatch.h>

#define CHECK(value) do { if (!(value)) { std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #value); std::abort(); } } while (false)

int main()
{
    @autoreleasepool
    {
        NSFileManager* manager = [NSFileManager defaultManager];
        NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        CHECK([manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSData* original = [@"existing backup" dataUsingEncoding:NSUTF8StringEncoding];
        CHECK([original writeToFile:[directory stringByAppendingPathComponent:@"Notes.txt"] atomically:YES]);
        NSMutableData* data = [NSMutableData dataWithLength:256 * 1024];
        memset([data mutableBytes], 0x5a, [data length]);
        // Several exports racing for the same name must all survive without replacing an earlier file.
        dispatch_apply(12, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) {
            @autoreleasepool
            {
                (void)index;
                NSError* error = nil;
                NSString* filename = aq_WriteUniqueFile(directory, @"Notes", @"txt", data, &error);
                CHECK(filename && !error);
                CHECK([[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:filename]] isEqualToData:data]);
            }
        });
        CHECK([[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"Notes.txt"]] isEqualToData:original]);
        CHECK([[manager contentsOfDirectoryAtPath:directory error:nil] count] == 13);
        NSError* error = nil;
        CHECK(!aq_WriteUniqueFile(directory, @"Bad", [@"x" stringByPaddingToLength:300 withString:@"x" startingAtIndex:0], data, &error));
        CHECK(error);
        CHECK([[manager contentsOfDirectoryAtPath:directory error:nil] count] == 13);
        CHECK(aq_WriteUniqueFile(directory, @"Empty", @"txt", [NSData data], &error));
        CHECK(!error);
        CHECK(!aq_WriteUniqueFile([directory stringByAppendingPathComponent:@"missing"], @"Notes", @"txt", data, &error));
        CHECK(error);
        CHECK([manager removeItemAtPath:directory error:nil]);
        std::puts("All atomic file exports passed.");
    }
}
