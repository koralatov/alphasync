#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "ASAlphaWordFile.h"
#include "ASGenericFile.h"

// Keep these checks active in release builds, too.  A failed check must stop the test.
#define CHECK(condition) do { if (!(condition)) { \
    std::fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
    std::abort(); \
} } while (false)

static void testAlphaWordRoundTrip()
{
    const uint16_t input[] = {'T', 'e', 'x', 't', ' ', 0x00a3, ' ', 0x2018, 'o', 'k', 0x2019};
    ts::ASAlphaWordFile file;
    CHECK(file.importText(input, sizeof input));
    const uint16_t* output = nullptr;
    unsigned size = 0;
    CHECK(file.exportText(&output, &size));
    CHECK(size == sizeof input);
    CHECK(std::memcmp(input, output, size) == 0);
}

static void testGenericRoundTrip()
{
    const uint8_t input[] = {0, 1, 2, 0x7f, 0xff};
    ts::ASGenericFile source;
    ts::ASGenericFile target;
    source.setAppletInfo(0x1234, 1, 0);
    target.setAppletInfo(0x1234, 1, 0);
    CHECK(source.load(input, sizeof input));
    const uint16_t* text = nullptr;
    unsigned size = 0;
    CHECK(source.exportText(&text, &size));
    CHECK(target.importText(text, size));
    CHECK(target.fileSize() == sizeof input);
    CHECK(std::memcmp(target.fileData(), input, sizeof input) == 0);
}

int main()
{
    testAlphaWordRoundTrip();
    testGenericRoundTrip();
    std::puts("All core tests passed.");
}
