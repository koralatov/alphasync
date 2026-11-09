#ifndef ALPHASYNC_TEST_FILE_WRITE_DEVICE_H
#define ALPHASYNC_TEST_FILE_WRITE_DEVICE_H

#include "ASDevice.h"
#include "ASSettings.h"
#include <cstdlib>
#include <cstring>
#include <deque>
#include <vector>

// Simulate the USB protocol, keeping the production settings parser and write
// checks intact.  Any unexpected command fails instead of reaching hardware.
class FileWriteDevice : public ts::ASDevice
{
public:
    bool settingsReadable = true, memoryReadable = true, usageReadable = true, maximumPresent = true, filePresent = true;
    unsigned maximum = 51200, minimum = 512, maximumBytes = 4;
    unsigned freeRAM = 300 * 1024, allocation = 1024;
    unsigned attributeWrites = 0, fileWrites = 0;
    bool corruptReadback = false;
    std::vector<uint8_t> saved = std::vector<uint8_t>(1024, 'o');

    static ts::ASApplet alphaWord()
    {
        uint8_t header[kASAppletHeaderSize] = {};
        ts::as_EndianWriteU32(header + kASAppletHeaderOffsetSignature, kASAppletSignature);
        ts::as_EndianWriteU16(header + kASAppletHeaderOffsetAppletID, ts::kASAppletID_AlphaWord);
        ts::ASApplet applet;
        if (!applet.loadHeader(header)) std::abort();
        return applet;
    }

protected:
    bool read(void* buffer, unsigned length, unsigned* actual, unsigned timeout) override
    {
        (void)timeout;
        if (responses.empty()) std::abort();
        const auto data = responses.front();
        responses.pop_front();
        if (actual ? data.size() > length : data.size() != length) std::abort();
        if (!data.empty()) std::memcpy(buffer, data.data(), data.size());
        if (actual) *actual = static_cast<unsigned>(data.size());
        return true;
    }

    bool write(const void* buffer, unsigned length, unsigned timeout) override
    {
        (void)timeout;
        const auto* bytes = static_cast<const uint8_t*>(buffer);
        if (blockBytes)
        {
            if (length != blockBytes) std::abort();
            if (writingFile) pending.insert(pending.end(), bytes, bytes + length);
            blockBytes = 0;
            reply(ASMESSAGE_RESPONSE_BLOCK_WRITE_DONE);
            return true;
        }
        if (length == 1) { responses.push_back({0x02, 0x30}); return true; }
        if (length != 8) std::abort();
        if (bytes[0] == 0x3f)
        {
            if (bytes[1] == 'S') responses.push_back({'S','w','i','t','c','h','e','d'});
            return true; // Reset has no reply.
        }
        ts::ASMessage request;
        std::memcpy(request.rawData(), buffer, length);
        if (!request.valid()) std::abort();
        switch (request.command())
        {
            case ASMESSAGE_REQUEST_GET_SETTINGS:
            {
                if (!settingsReadable) { reply(ASMESSAGE_ERROR_PARAMETER); break; }
                uint8_t storage[64] = {};
                ts::ASSettings settings(storage, 0, sizeof storage);
                if (maximumPresent)
                {
                    if (!settings.newItem(kASSettingsType_Range32, kASSettingsIdent_AlphaWord_MaxFileSize)) std::abort();
                    uint8_t value[4];
                    ts::as_EndianWriteU32(value, maximum);
                    if (!settings.appendItemData(value, maximumBytes)) std::abort();
                }
                if (!settings.newItem(kASSettingsType_Range32, kASSettingsIdent_AlphaWord_MinFileSize) ||
                    !settings.appendItemData(uint32_t(minimum))) std::abort();
                replyData(ASMESSAGE_RESPONSE_GET_SETTINGS, storage, settings.size());
                break;
            }
            case ASMESSAGE_REQUEST_GET_AVAIL_SPACE:
            {
                if (!memoryReadable) { reply(ASMESSAGE_ERROR_PARAMETER); break; }
                ts::ASMessage response(ASMESSAGE_RESPONSE_GET_AVAIL_SPACE);
                response.setArgument(freeRAM / 256, 5, 2);
                enqueue(response);
                break;
            }
            case ASMESSAGE_REQUEST_GET_USED_SPACE:
            {
                if (!usageReadable) { reply(ASMESSAGE_ERROR_PARAMETER); break; }
                ts::ASMessage response(ASMESSAGE_RESPONSE_GET_USED_SPACE);
                response.setArgument(1, 5, 2);
                enqueue(response);
                break;
            }
            case ASMESSAGE_REQUEST_GET_FILE_ATTRIBUTES:
            {
                if (!filePresent || request.argument(1, 4) != 1) { reply(ASMESSAGE_ERROR_PARAMETER); break; }
                ts::ASFileAttributes attributes;
                attributes.setFileName("Existing");
                attributes.setAllocSize(allocation);
                replyData(ASMESSAGE_RESPONSE_GET_FILE_ATTRIBUTES, attributes.rawData(), kASFileAttributesSize);
                break;
            }
            case ASMESSAGE_REQUEST_SET_FILE_ATTRIBUTES:
                ++attributeWrites;
                writingFile = false;
                reply(ASMESSAGE_RESPONSE_SET_FILE_ATTRIBUTES);
                break;
            case ASMESSAGE_REQUEST_COMMIT:
                reply(ASMESSAGE_RESPONSE_COMMIT);
                break;
            case ASMESSAGE_REQUEST_WRITE_RAW_FILE:
                ++fileWrites;
                writingFile = true;
                pending.clear();
                reply(ASMESSAGE_RESPONSE_WRITE_FILE);
                break;
            case ASMESSAGE_REQUEST_BLOCK_WRITE:
                blockBytes = request.argument(1, 4);
                reply(ASMESSAGE_RESPONSE_BLOCK_WRITE);
                break;
            case ASMESSAGE_REQUEST_CONFIRM_WRITE_FILE:
                saved = pending;
                allocation = static_cast<unsigned>(saved.size());
                reply(ASMESSAGE_RESPONSE_CONFIRM_WRITE_FILE);
                break;
            case ASMESSAGE_REQUEST_READ_RAW_FILE:
            case ASMESSAGE_REQUEST_READ_FILE:
                readOffset = 0;
                readLimit = std::min(request.argument(1, 3), static_cast<unsigned>(saved.size()));
                reply(ASMESSAGE_RESPONSE_READ_FILE);
                break;
            case ASMESSAGE_REQUEST_BLOCK_READ:
            {
                unsigned count = std::min(1024u, readLimit - readOffset);
                if (!count) { reply(ASMESSAGE_RESPONSE_BLOCK_READ_EMPTY); break; }
                std::vector<uint8_t> block(saved.begin() + readOffset, saved.begin() + readOffset + count);
                if (corruptReadback && readOffset == 0) block[0] ^= 1;
                replyData(ASMESSAGE_RESPONSE_BLOCK_READ, block.data(), count);
                readOffset += count;
                break;
            }
            default: std::abort();
        }
        return true;
    }

private:
    std::deque<std::vector<uint8_t>> responses;
    std::vector<uint8_t> pending;
    bool writingFile = false;
    unsigned blockBytes = 0;
    unsigned readOffset = 0, readLimit = 0;

    void enqueue(const ts::ASMessage& message)
    {
        const auto* bytes = static_cast<const uint8_t*>(message.rawData());
        responses.emplace_back(bytes, bytes + message.rawSize());
    }
    void reply(unsigned command) { enqueue(ts::ASMessage(command)); }
    void replyData(unsigned command, const uint8_t* bytes, unsigned length)
    {
        unsigned checksum = 0;
        for (unsigned index = 0; index < length; ++index) checksum += bytes[index];
        ts::ASMessage response(command);
        response.setArgument(length, 1, 4);
        response.setArgument(checksum & 0xffff, 5, 2);
        enqueue(response);
        responses.emplace_back(bytes, bytes + length);
    }
};
#endif
