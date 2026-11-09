import Foundation
import XCTest
@testable import AlphaSyncCore

final class CoreTests: XCTestCase {
    private var limits: NeoFileLimits { get throws { try NeoFileLimits(minimum: 512, maximum: 51200) } }

    func testFrameMatchesKnownWireBytes() throws {
        var frame = NeoMessage(command: 0x1f)
        try frame.set(3, at: 1, width: 1)
        try frame.set(512, at: 2, width: 3)
        try frame.set(0xa000, at: 5, width: 2)
        XCTAssertEqual(Array(frame.data), [0x1f, 3, 0, 2, 0, 0xa0, 0, 0xc4])
        XCTAssertEqual(try NeoMessage(data: frame.data), frame)
        XCTAssertThrowsError(try frame.set(256, at: 1, width: 1))
        XCTAssertThrowsError(try frame.set(1, at: 6, width: 2))
    }

    func testDamagedAndTruncatedFramesFail() {
        for count in 0..<8 { XCTAssertThrowsError(try NeoMessage(data: Data(repeating: 0, count: count))) }
        XCTAssertThrowsError(try NeoMessage(data: Data([0x44, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertThrowsError(try NeoMessage(data: Data(repeating: 0, count: 9)))
    }

    func testReaderHandlesDataWithNonzeroStartIndex() throws {
        let source = Data([0xff, 0x12, 0x34, 0x56, 0x78]).dropFirst()
        let reader = BinaryReader(source)
        XCTAssertEqual(try reader.integer(at: 0, width: 4), 0x12345678)
        XCTAssertThrowsError(try reader.integer(at: Int.max, width: 4))
        XCTAssertThrowsError(try reader.data(at: -1, count: 1))
        XCTAssertThrowsError(try reader.data(at: 1, count: Int.max))
    }

    func testAlphaWordKnownEscapesAndPadding() throws {
        let encoded = try AlphaWordCodec.encode("A £\tB\nC", limits: limits)
        XCTAssertEqual(Array(encoded.prefix(10)), [65, 32, 0xb0, 0xa3, 0xb0, 9, 66, 13, 67, 0xa7])
        XCTAssertEqual(encoded.count, 512)
        XCTAssertEqual(try AlphaWordCodec.decode(encoded), "A £\tB\rC")
        XCTAssertEqual(try AlphaWordCodec.decode(AlphaWordCodec.encode("", limits: limits)), "")
    }

    func testAllRepresentableFontCharactersSurvive() throws {
        let text = String(String.UnicodeScalarView(NeoCharacters.unicode.compactMap(Unicode.Scalar.init)))
        let encoded = try AlphaWordCodec.encode(text, limits: limits)
        XCTAssertEqual(try AlphaWordCodec.decode(encoded), text)
        XCTAssertEqual(try AlphaWordCodec.decode(AlphaWordCodec.encode("ΦΠ", limits: limits)), "ΦΠ")
    }

    func testParagraphsAndWrapHintsPreserveText() throws {
        let source = "A\r\nB\nC\rD\r\n\r\nE"
        XCTAssertEqual(try AlphaWordCodec.decode(AlphaWordCodec.encode(source, limits: limits)), "A\rB\rC\rD\r\rE")
        for source in [String(repeating: "word - ", count: 100), String(repeating: "a", count: 100)] {
            XCTAssertEqual(try AlphaWordCodec.decode(AlphaWordCodec.encode(source, limits: limits)), source)
        }
    }

    func testUnsupportedTextAndOversizedConversionsFailBeforeWriting() throws {
        for text in ["≡", "🙂", "中", "\0"] {
            XCTAssertThrowsError(try AlphaWordCodec.encode(text, limits: limits))
        }
        XCTAssertThrowsError(try AlphaWordCodec.encode(String(repeating: "a", count: 60000), limits: limits))
        XCTAssertThrowsError(try AlphaWordCodec.decode(Data([0xb0])))
        XCTAssertThrowsError(try AlphaWordCodec.decode(Data([0xb0, 0xa7])))
    }

    func testDictionaryOffsetsDeduplicationAndAccents() throws {
        let encoded = try DictionaryCodec.encode("cats café, an cats. extraordinarilylongword")
        XCTAssertEqual(try BinaryReader(encoded).integer(at: 0, width: 2), 38)
        XCTAssertEqual(try DictionaryCodec.decode(encoded), "an café cats")
        XCTAssertEqual(try DictionaryCodec.decode(DictionaryCodec.encode("")), "")
        for index in 0..<19 {
            var malformed = encoded
            malformed[index * 2] = 0xff
            XCTAssertThrowsError(try DictionaryCodec.decode(malformed))
        }
    }

    func testDictionaryFullImportRejectsInsteadOfTruncating() {
        let text = (0..<7000).map { String(format: "word%06d", $0) }.joined(separator: " ")
        XCTAssertThrowsError(try DictionaryCodec.encode(text))
    }

    func testTextImportEncodingsAndExport() throws {
        let source = "£ café and ‘quotes’\n"
        for encoding: String.Encoding in [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .macOSRoman] {
            var bytes = try XCTUnwrap(source.data(using: encoding))
            if encoding == .utf16BigEndian { bytes = Data([0xfe, 0xff]) + bytes }
            if encoding == .utf16LittleEndian { bytes = Data([0xff, 0xfe]) + bytes }
            XCTAssertEqual(try TextFiles.decode(bytes), source)
        }
        XCTAssertThrowsError(try TextFiles.decode(Data([0xff, 0xfe, 0x41])))
        XCTAssertEqual(String(data: TextFiles.utf8("a\r\nb\rc"), encoding: .utf8), "a\nb\nc")
    }

    func testLimitsDoNotTrustMissingOrTruncatedSettings() throws {
        let settings = Data([1, 2, 0x10, 0x10, 0, 4, 0, 0, 0xc8, 0])
        XCTAssertEqual(try NeoSettings.alphaWordLimits(settings).maximum, 51200)
        XCTAssertThrowsError(try NeoSettings.alphaWordLimits(Data()))
        for count in 1..<settings.count {
            XCTAssertThrowsError(try NeoSettings.alphaWordLimits(Data(settings.prefix(count))))
        }
        XCTAssertThrowsError(try NeoSettings.alphaWordLimits(settings + settings))
        XCTAssertThrowsError(try NeoFileLimits(minimum: 1024, maximum: 512))
        let fileLimits = try self.limits
        XCTAssertNoThrow(try fileLimits.validate(512, allocation: 512, available: 0))
        XCTAssertThrowsError(try fileLimits.validate(512, allocation: 0, available: 1024))
        XCTAssertNoThrow(try fileLimits.validate(512, allocation: 0, available: 1536))
    }

    func testAttributesNeverTruncateNamesOrAcceptControls() throws {
        var attributes = try NeoFileAttributes(name: "File 1", fileSpace: 1)
        XCTAssertEqual(attributes.raw.count, 40)
        XCTAssertEqual(attributes.password, "write")
        XCTAssertEqual(attributes.fileSpace, 1)
        let original = attributes.raw
        for name in ["", "SixteenCharacters", "a\nb", "\0", "🙂"] {
            XCTAssertThrowsError(try attributes.rename(name))
            XCTAssertEqual(attributes.raw, original)
        }
        XCTAssertThrowsError(try NeoFileAttributes(raw: Data(repeating: 0, count: 39)))
    }
}
