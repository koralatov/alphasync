#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <climits>
#include <vector>
#include "ASSettings.h"

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

static void testSettingsBounds()
{
    const uint8_t raw[] = {0x80, 2, 0x12, 0x34, 0, 2, 0x12, 0x34};
    for (unsigned size = 0; size <= sizeof raw; ++size)
    {
        std::vector<uint8_t> buffer(raw, raw + size);
        ts::ASSettings settings(buffer.data(), size);
        ts::ASSettingsItem item;
        CHECK(settings.getSettingsItemAtIndex(&item, 0) == (size == sizeof raw));
        CHECK(!settings.getSettingsItemAtIndex(&item, 1));
        if (size == sizeof raw)
        {
            CHECK(settings.getSettingsItemAtIndex(&item, 0));
            CHECK(item.dataU16() == 0x1234);
            CHECK(item.dataU16(1) == 0);
            CHECK(item.dataU16(UINT_MAX) == 0);
            CHECK(item.dataU32(UINT_MAX) == 0);
        }
    }
    uint8_t buffer[16] = {};
    ts::ASSettings settings(buffer, 0, sizeof buffer);
    CHECK(settings.newItem(0x8002, 0x1234));
    CHECK(settings.appendItemData(uint8_t(0x12)));
    CHECK(settings.appendItemData(uint8_t(0x34)));
    CHECK(settings.newItem(1, 2));
    CHECK(settings.appendItemData(uint8_t(0x56)));
    CHECK(!settings.appendItemData(uint32_t(0x12345678)));
    ts::ASSettingsItem item;
    CHECK(settings.getSettingsItemAtIndex(&item, 0));
    CHECK(item.dataU16() == 0x1234);
    CHECK(settings.getSettingsItemAtIndex(&item, 1));
    CHECK(item.length() == 1 && item.dataU8() == 0x56);
    CHECK(!settings.getSettingsItemAtIndex(&item, 2));
    CHECK(settings.clearAllItems());
    CHECK(!settings.appendItemData(uint8_t(0x78)));
}

static void testMalformedGenericFiles()
{
    const char* invalid[] = {"hello", "<data>", "</data>", "<data>0</data>",
                             "<data>01f</data>", "<data>xy</data>"};
    for (const char* text : invalid)
    {
        std::u16string input(text, text + std::strlen(text));
        ts::ASGenericFile file;
        CHECK(!file.importText(reinterpret_cast<const uint16_t*>(input.data()), input.size() * 2));
    }
    std::u16string empty = u"<data></data>";
    ts::ASGenericFile file;
    CHECK(file.importText(reinterpret_cast<const uint16_t*>(empty.data()), empty.size() * 2));
    CHECK(file.fileSize() == 0);
    const uint16_t* output = nullptr;
    unsigned size = 0;
    CHECK(file.exportText(&output, &size));
    ts::ASGenericFile target;
    CHECK(target.importText(output, size));
    CHECK(target.fileSize() == 0);
}

int main()
{
    testAlphaWordRoundTrip();
    testGenericRoundTrip();
    testSettingsBounds();
    testMalformedGenericFiles();
    std::puts("All core tests passed.");
}
