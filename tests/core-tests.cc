#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <climits>
#include <vector>
#include "ASSettings.h"

#include "ASAlphaWordFile.h"
#include "ASGenericFile.h"
#include "ASUserDictionaryFile.h"

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
        std::vector<uint16_t> input(text, text + std::strlen(text));
        ts::ASGenericFile file;
        CHECK(!file.importText(input.data(), input.size() * 2));
    }
    const std::string emptyTag = "<data></data>";
    std::vector<uint16_t> empty(emptyTag.begin(), emptyTag.end());
    ts::ASGenericFile file;
    CHECK(file.importText(empty.data(), empty.size() * 2));
    CHECK(file.fileSize() == 0);
    const uint16_t* output = nullptr;
    unsigned size = 0;
    CHECK(file.exportText(&output, &size));
    ts::ASGenericFile target;
    CHECK(target.importText(output, size));
    CHECK(target.fileSize() == 0);
}

class MockDevice : public ts::ASDevice
{
public:
    std::vector<std::vector<uint8_t>> replies;
    unsigned reads = 0;
    using ts::ASDevice::rawReadFile;

    void reply(unsigned command, unsigned length = 0, unsigned checksum = 0)
    {
        ts::ASMessage message(command);
        message.setArgument(length, 1, 4);
        message.setArgument(checksum, 5, 2);
        const uint8_t* data = static_cast<const uint8_t*>(message.rawData());
        replies.emplace_back(data, data + message.rawSize());
    }

    bool read(void* buffer, unsigned length, unsigned* actual, unsigned timeout) override
    {
        (void)timeout;
        CHECK(reads < replies.size());
        const auto& data = replies[reads++];
        CHECK(length == data.size());
        std::memcpy(buffer, data.data(), data.size());
        if (actual) *actual = data.size();
        return true;
    }
    bool write(const void* buffer, unsigned length, unsigned timeout) override
    {
        (void)buffer;
        (void)length;
        (void)timeout;
        return true;
    }
};

static void testUSBReadBounds()
{
    for (unsigned length : {0u, 8u})
    {
        MockDevice device;
        device.reply(ASMESSAGE_RESPONSE_BLOCK_READ);
        device.reply(ASMESSAGE_RESPONSE_BLOCK_READ, length);
        uint8_t output[4] = {};
        unsigned actual = 99;
        CHECK(!device.rawReadFile(output, sizeof output, &actual, 0, 0));
        CHECK(actual == 0 && device.reads == 2);
    }
    MockDevice device;
    device.reply(ASMESSAGE_RESPONSE_BLOCK_READ);
    device.reply(ASMESSAGE_RESPONSE_BLOCK_READ, 2, 3);
    device.replies.push_back({1, 2});
    device.reply(ASMESSAGE_RESPONSE_BLOCK_READ, 2, 7);
    device.replies.push_back({3, 4});
    uint8_t output[4] = {};
    unsigned actual = 0;
    CHECK(device.rawReadFile(output, sizeof output, &actual, 0, 0));
    CHECK(actual == sizeof output && device.reads == 5);
    CHECK(output[0] == 1 && output[3] == 4);

    MockDevice badChecksum;
    badChecksum.reply(ASMESSAGE_RESPONSE_BLOCK_READ);
    badChecksum.replies[0][7] ^= 1;
    CHECK(!badChecksum.rawReadFile(output, sizeof output, &actual, 0, 0));
    CHECK(actual == 0 && badChecksum.reads == 1);
}

class MutableFile : public ts::ASFile
{
public:
    using ts::ASFile::appendData;
};

class ValidatedFile : public ts::ASFile
{
protected:
    bool confirmLoad() override
    {
        return fileSize() > 0 && byteData()[0] == 1;
    }
};

static void testRejectedLoadPreservesData()
{
    const uint8_t original[] = {1, 2, 3};
    const uint8_t invalid[] = {0, 4};
    ValidatedFile file;
    CHECK(file.load(original, sizeof original));
    CHECK(!file.load(invalid, sizeof invalid));
    CHECK(file.fileSize() == sizeof original);
    CHECK(std::memcmp(file.fileData(), original, sizeof original) == 0);
}

static void testFileBufferFailures()
{
    MutableFile file;
    uint8_t data[] = {1, 2, 3, 4};
    CHECK(file.load(data, sizeof data));
    CHECK(!file.load(nullptr, 4));
    CHECK(file.fileSize() == 4);
    CHECK(std::memcmp(file.fileData(), data, 4) == 0);
    CHECK(!file.appendData(data, UINT_MAX));
    CHECK(file.fileSize() == 4);
    CHECK(file.load(static_cast<const uint8_t*>(file.fileData()) + 1, 2));
    CHECK(file.fileSize() == 2);
    CHECK(static_cast<const uint8_t*>(file.fileData())[0] == 2);
    MockDevice device;
    CHECK(!file.load(&device, nullptr, "missing"));
    CHECK(device.reads == 0);
}

static void testUnicodeByteOrder()
{
    const uint16_t native[] = {0xfeff, 'a', 'l', 'p', 'h', 'a', '\n', 'b', 'e', 't', 'a'};
    std::vector<uint16_t> swapped;
    for (uint16_t value : native) swapped.push_back((value >> 8) | (value << 8));
    const uint16_t* inputs[] = {native, swapped.data()};
    for (const uint16_t* input : inputs)
    {
        ts::ASUserDictionaryFile dictionary;
        CHECK(dictionary.importText(input, sizeof native));
        CHECK(dictionary.wordCount() == 2);
        CHECK(dictionary.containsWord("alpha") && dictionary.containsWord("beta"));
        ts::ASAlphaWordFile word;
        CHECK(word.importText(input, sizeof native));
        const uint16_t* output = nullptr;
        unsigned size = 0;
        CHECK(word.exportText(&output, &size));
        CHECK(size == sizeof native - 2);
        CHECK(output[0] == 'a' && output[9] == 'a');
    }
    ts::ASAlphaWordFile file;
    CHECK(!file.importText(nullptr, 2));
    CHECK(!file.importText(native, 3));
}

static std::vector<uint8_t> dictionaryBytes(unsigned size, unsigned offset)
{
    std::vector<uint8_t> bytes(size, 'a');
    for (unsigned i = 0; i < 19; ++i) ts::as_EndianWriteU16(bytes.data() + i * 2, offset);
    return bytes;
}

static void testMalformedDictionaries()
{
    ts::ASUserDictionaryFile file;
    CHECK(file.addWord("original"));

    auto partialWord = dictionaryBytes(39, 39);
    ts::as_EndianWriteU16(partialWord.data(), 38);
    CHECK(!file.load(partialWord.data(), partialWord.size()));
    CHECK(file.wordCount() == 1 && file.containsWord("original"));

    auto descending = dictionaryBytes(44, 44);
    ts::as_EndianWriteU16(descending.data(), 40);
    ts::as_EndianWriteU16(descending.data() + 2, 38);
    CHECK(!file.load(descending.data(), descending.size()));

    auto headerWord = dictionaryBytes(38, 0);
    CHECK(!file.load(headerWord.data(), headerWord.size()));
    auto outside = dictionaryBytes(38, 40);
    CHECK(!file.load(outside.data(), outside.size()));

    auto embeddedNull = dictionaryBytes(40, 40);
    ts::as_EndianWriteU16(embeddedNull.data(), 38);
    embeddedNull[38] = 0;
    CHECK(!file.load(embeddedNull.data(), embeddedNull.size()));

    for (unsigned size = 0; size < 38; ++size)
    {
        std::vector<uint8_t> shortFile(size);
        CHECK(!file.load(shortFile.data(), size));
    }
    CHECK(file.wordCount() == 1 && file.containsWord("original"));

    auto valid = dictionaryBytes(40, 40);
    ts::as_EndianWriteU16(valid.data(), 38);
    valid[38] = 'a';
    valid[39] = 'b';
    CHECK(file.load(valid.data(), valid.size()));
    CHECK(file.wordCount() == 1 && file.containsWord("ab"));
}

int main()
{
    testAlphaWordRoundTrip();
    testGenericRoundTrip();
    testSettingsBounds();
    testMalformedGenericFiles();
    testUSBReadBounds();
    testFileBufferFailures();
    testRejectedLoadPreservesData();
    testUnicodeByteOrder();
    testMalformedDictionaries();
    std::puts("All core tests passed.");
}
