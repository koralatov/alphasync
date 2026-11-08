#import "../AlphaSync/Application/ASFileNode.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "ASAlphaWordFile.h"
#include "file-write-device.h"
#import "AQFileUtilities.h"

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

@interface TestWritableFileNode : ASFileNode
- (id)initWithTestDevice:(FileWriteDevice*)value;
@end
@implementation TestWritableFileNode
- (id)initWithTestDevice:(FileWriteDevice*)value
{
    if ((self = [super initForDisplay]))
    {
        displayOnly = NO;
        device = value;
        applet = new ts::ASApplet(FileWriteDevice::alphaWord());
        fileIndex = 1;
        fileAttributes = new ts::ASFileAttributes;
        fileData = new ts::ASAlphaWordFile;
        fileIsPlainText = YES;
    }
    return self;
}
- (void)reload { /* The protocol stub covers writes, not preview downloads. */ }
@end

@interface TestImportAppletNode : ASAppletNode
- (id)initWithTestDevice:(FileWriteDevice*)value;
- (void)readLimits;
@end
@implementation TestImportAppletNode
- (id)initWithTestDevice:(FileWriteDevice*)value
{
    if ((self = [super initForDisplay]))
    {
        device = value;
        applet = new ts::ASApplet(FileWriteDevice::alphaWord());
    }
    return self;
}
- (void)refresh { /* Avoid unrelated UI refreshes after each import. */ }
- (void)readLimits { [super refresh]; }
@end

static void checkImportRejection(NSString* path, bool create, unsigned failure, NSString* expected)
{
    FileWriteDevice device;
    if (failure == 1) device.settingsReadable = false;
    if (failure == 2) device.maximumPresent = false;
    if (failure == 3) device.maximumBytes = 2;
    if (failure == 4) device.maximum = 0;
    if (failure == 5) device.freeRAM = 2048;
    if (failure == 6) device.memoryReadable = false;
    const auto original = device.saved;
    id node = create ? (id)[[TestImportAppletNode alloc] initWithTestDevice:&device] :
                       (id)[[TestWritableFileNode alloc] initWithTestDevice:&device];
    CHECK(![node loadFromPath:path]);
    CHECK([[(ASNode*)node operationError] containsString:expected]);
    CHECK(!device.attributeWrites && !device.fileWrites && device.saved == original);
    [node release];
}

static void checkImportLimits(NSString* directory)
{
    NSString* path = [directory stringByAppendingPathComponent:@"Large.txt"];
    for (bool create : {false, true})
    {
        // Both exceed the per-file limit; the smaller one still fits in free RAM.
        for (NSUInteger size : {NSUInteger(60000), NSUInteger(2 * 1024 * 1024)})
        {
            NSString* text = [@"a " stringByPaddingToLength:size withString:@"a " startingAtIndex:0];
            CHECK([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
            checkImportRejection(path, create, 0, aq_FormattedByteCount(51200));
        }
        CHECK([@"Small text" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        for (unsigned failure : {1u, 2u, 3u, 4u})
            checkImportRejection(path, create, failure, @"couldn’t read the Neo’s maximum file size");
        checkImportRejection(path, create, 6, @"couldn’t check the Neo’s available memory");
        NSString* growing = [@"a " stringByPaddingToLength:10000 withString:@"a " startingAtIndex:0];
        CHECK([growing writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        checkImportRejection(path, create, 5, @"enough free memory");
        CHECK([@"🙂" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        checkImportRejection(path, create, 0, @"unsupported characters");
        checkImportRejection([directory stringByAppendingPathComponent:@"Missing.txt"], create, 0, @"could not be read");
    }
    FileWriteDevice device;
    TestImportAppletNode* applet = [[TestImportAppletNode alloc] initWithTestDevice:&device];
    [applet readLimits];
    CHECK([applet fileSizeLimitKnown] && [applet maxFileSize] == 51200);
    device.settingsReadable = false;
    [applet readLimits];
    CHECK(![applet fileSizeLimitKnown]);
    ASAppletNode* copy = (ASAppletNode*)[applet copyForDisplay];
    CHECK(![copy fileSizeLimitKnown]);
    [copy release];
    [applet release];
    device.settingsReadable = true;
    TestWritableFileNode* file = [[TestWritableFileNode alloc] initWithTestDevice:&device];
    CHECK([@"Small text £\r\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    CHECK([file loadFromPath:path] && device.fileWrites == 1 && ![file operationError]);
    [file release];
}

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
        checkImportLimits(directory);
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
