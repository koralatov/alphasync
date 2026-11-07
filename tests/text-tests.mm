#import "../AlphaSync/Application/ASFileNode.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

#define CHECK(value) do { if (!(value)) { std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #value); std::abort(); } } while (false)

// Replace only device access.  The tests use the real file-reading and export paths.
@interface ASNode (TestConstruction)
- (id)initForDisplay;
@end
@interface TestTextFileNode : ASFileNode
- (id)initWithText:(NSString*)text plainText:(BOOL)plain;
@end
@implementation TestTextFileNode
- (id)initWithText:(NSString*)text plainText:(BOOL)plain
{
    if ((self = [super initForDisplay]))
    {
        displayOnly = YES;
        fileIsPlainText = plain;
        filePreview = [text copy];
    }
    return self;
}
- (void)getFileNameBase:(NSString**)basename extension:(NSString**)extension
{
    *basename = @"Export";
    *extension = fileIsPlainText ? @"txt" : @"xml";
}
- (BOOL)setFileData:(NSString*)text error:(NSString**)error
{
    if (error) *error = nil;
    [filePreview release];
    filePreview = [text copy];
    return YES;
}
@end

static void checkExport(ASFileNode* node, NSString* directory, NSData* expected)
{
    NSString* error = nil;
    NSString* filename = [node saveUnderPath:directory error:&error];
    CHECK(filename && !error);
    NSData* actual = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:filename]];
    CHECK([actual isEqualToData:expected]);
}

static NSData* withPrefix(const unsigned char* prefix, NSUInteger size, NSData* contents)
{
    NSMutableData* result = [NSMutableData dataWithBytes:prefix length:size];
    [result appendData:contents];
    return result;
}

int main()
{
    @autoreleasepool
    {
        NSFileManager* manager = [NSFileManager defaultManager];
        NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        CHECK([manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSUserDefaults* preferences = [NSUserDefaults standardUserDefaults];
        id previous = [[preferences objectForKey:@"TextEncoding"] retain];

        // Every saved preference from older versions must still produce UTF-8 bytes,
        // including characters the old Mac Roman and plain ASCII choices could lose.
        NSString* text = @"£ café ‘hello’ Σ\n";
        const char* utf8 = u8"£ café ‘hello’ Σ\n";
        NSData* expected = [NSData dataWithBytes:utf8 length:std::strlen(utf8)];
        for (NSInteger option = 0; option < 4; ++option)
        {
            [preferences setInteger:option forKey:@"TextEncoding"];
            for (NSNumber* plain in @[@YES, @NO])
            {
                ASFileNode* node = [[TestTextFileNode alloc] initWithText:text plainText:[plain boolValue]];
                checkExport(node, directory, expected);
                [node release];
            }
        }
        ASFileNode* empty = [[TestTextFileNode alloc] initWithText:@"" plainText:YES];
        checkExport(empty, directory, [NSData data]);
        [empty release];

        NSString* imported = @"café £ ‘hello’\r\n";
        const char* importedUTF8 = u8"café £ ‘hello’\r\n";
        NSData* expectedImport = [NSData dataWithBytes:importedUTF8 length:std::strlen(importedUTF8)];
        const unsigned char utf8BOM[] = {0xef, 0xbb, 0xbf};
        const unsigned char littleBOM[] = {0xff, 0xfe};
        const unsigned char bigBOM[] = {0xfe, 0xff};
        NSArray* fixtures = @[
            [imported dataUsingEncoding:NSMacOSRomanStringEncoding],
            expectedImport,
            withPrefix(utf8BOM, sizeof utf8BOM, expectedImport),
            withPrefix(littleBOM, sizeof littleBOM, [imported dataUsingEncoding:NSUTF16LittleEndianStringEncoding]),
            withPrefix(bigBOM, sizeof bigBOM, [imported dataUsingEncoding:NSUTF16BigEndianStringEncoding])
        ];
        for (NSData* data in fixtures)
        {
            NSString* path = [directory stringByAppendingPathComponent:@"Import.txt"];
            CHECK([data writeToFile:path atomically:YES]);
            ASFileNode* node = [[TestTextFileNode alloc] initWithText:@"unchanged" plainText:YES];
            CHECK([node loadFromPath:path]);
            CHECK([[node fileData] isEqualToString:imported]);
            checkExport(node, directory, expectedImport);
            [node release];
        }

        if (previous) [preferences setObject:previous forKey:@"TextEncoding"];
        else [preferences removeObjectForKey:@"TextEncoding"];
        [previous release];
        CHECK([manager removeItemAtPath:directory error:nil]);
        std::puts("All text imports and UTF-8 exports passed.");
    }
}
