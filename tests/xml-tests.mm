#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>
#include "ASGenericFile.h"

#define CHECK(condition) do { if (!(condition)) { \
    std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
    std::abort(); \
} } while (false)

static void checkDocument(bool metadata, bool empty, bool bom)
{
    const uint8_t bytes[] = {0, 1, 2, 0x7f, 0xff};
    ts::ASGenericFile file;
    if (metadata) file.setAppletInfo(0x1234, 1, 0);
    CHECK(file.load(bytes, empty ? 0 : sizeof bytes));
    const uint16_t* text = nullptr;
    unsigned size = 0;
    CHECK(file.exportText(&text, &size, bom));
    NSString* xml = [[[NSString alloc] initWithCharacters:text length:size / sizeof(uint16_t)] autorelease];
    NSError* error = nil;
    NSXMLDocument* document = [[[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error] autorelease];
    CHECK(document && !error);
    NSXMLElement* root = [document rootElement];
    CHECK(root && [[root elementsForName:@"data"] count] == 1);
    CHECK([[root elementsForName:@"appletID"] count] == static_cast<NSUInteger>(metadata));
}

int main()
{
    @autoreleasepool
    {
        for (bool metadata : {false, true})
            for (bool empty : {false, true})
                for (bool bom : {false, true}) checkDocument(metadata, empty, bom);
        std::puts("All XML exports passed Foundation’s parser.");
    }
}
