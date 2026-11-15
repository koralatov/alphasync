import XCTest
@testable import AlphaSyncCore

final class DictionaryImportTests: XCTestCase {
    func testLengthBucketsKeepTheExactLegacyDictionaryBytes() throws {
        var expected = Data([0, 38, 0, 42])
        for _ in 0..<17 { expected.append(contentsOf: [0, 45]) }
        expected.append(contentsOf: "aabbcat".utf8)
        let conversion = try DictionaryCodec.convert("bb aa cat bb")
        XCTAssertEqual(conversion.data, expected)
        XCTAssertEqual(conversion.report.acceptedWords, 3)
        XCTAssertEqual(conversion.report.omittedWords, 0)
        XCTAssertEqual(try DictionaryCodec.decode(expected), "aa bb cat")
    }

    func testAnImportLimitSizedOmittedWordKeepsOnlyAShortExample() throws {
        let text = String(repeating: "x", count: TextFiles.maximumImportBytes - 5) + " cats"
        let conversion = try DictionaryCodec.convert(text)
        XCTAssertEqual(conversion.report.acceptedWords, 1)
        XCTAssertEqual(conversion.report.omittedWords, 1)
        XCTAssertEqual(conversion.report.examples, [String(repeating: "x", count: 32) + "…"])
        XCTAssertEqual(try DictionaryCodec.decode(conversion.data), "cats")
    }

    func testBoundedExamplesDoNotTurnOverlongWordsIntoValidWords() throws {
        let valid = String(repeating: "x", count: 20)
        let omitted = [String(repeating: "x", count: 21), String(repeating: "y", count: 32), String(repeating: "z", count: 33)]
        let conversion = try DictionaryCodec.convert(([valid] + omitted + ["aa"]).joined(separator: " "))
        XCTAssertEqual(conversion.report.acceptedWords, 2)
        XCTAssertEqual(conversion.report.omittedWords, 3)
        XCTAssertEqual(conversion.report.examples, [omitted[0], omitted[1], String(repeating: "z", count: 32) + "…"])
        XCTAssertEqual(try DictionaryCodec.decode(conversion.data), "aa " + valid)
    }

    func testCharactersBeyondTheExampleLimitAreStillValidated() {
        XCTAssertThrowsError(try DictionaryCodec.convert(String(repeating: "x", count: 128) + "🙂 aa")) { error in
            guard let reason = error as? NeoError, case .unsupportedCharacter = reason else {
                return XCTFail("The unsupported character was ignored")
            }
        }
    }

    private var limits: NeoFileLimits { get throws { try NeoFileLimits(minimum: 0, maximum: DictionaryCodec.maximum) } }

    func testConversionReportsRejectedWordsWithoutChangingTheDictionaryFormat() throws {
        let text = "cats a café cats extraordinarilylongword"
        let conversion = try DictionaryCodec.convert(text)
        XCTAssertEqual(conversion.report.acceptedWords, 2)
        XCTAssertEqual(conversion.report.omittedWords, 2)
        XCTAssertEqual(conversion.report.examples, ["a", "extraordinarilylongword"])
        XCTAssertEqual(try DictionaryCodec.decode(conversion.data), "café cats")
    }

    func testOmissionsNeedConsentForTheExactSourceText() throws {
        let text = "cats a"
        do {
            _ = try FileCodec.converted(text, applet: NeoApplet.dictionary, limits: limits)
            XCTFail("Dictionary omissions were accepted without consent")
        } catch let warning as DictionaryImportWarning {
            XCTAssertEqual(warning.sourceText, text)
            XCTAssertEqual(warning.report.omittedWords, 1)
        }
        let data = try FileCodec.converted(text, applet: NeoApplet.dictionary, limits: limits, dictionaryConsent: text)
        XCTAssertEqual(try DictionaryCodec.decode(data), "cats")
        XCTAssertThrowsError(try FileCodec.converted("dogs a", applet: NeoApplet.dictionary, limits: limits, dictionaryConsent: text)) {
            XCTAssertTrue($0 is DictionaryImportWarning)
        }
    }

    func testNonemptyTextWithoutUsableWordsCannotEmptyTheDictionary() throws {
        for text in ["a I extraordinarilylongword", " , ; ", "\n\n"] {
            XCTAssertThrowsError(try FileCodec.converted(text, applet: NeoApplet.dictionary, limits: limits, dictionaryConsent: text)) {
                XCTAssertFalse($0 is DictionaryImportWarning)
            }
        }
        XCTAssertEqual(try DictionaryCodec.decode(FileCodec.converted("", applet: NeoApplet.dictionary, limits: limits)), "")
    }

    func testWarningExamplesRemainSmallForVeryLongWords() throws {
        let text = Array(repeating: String(repeating: "x", count: 1000), count: 5).joined(separator: " ") + " cats"
        let report = try DictionaryCodec.convert(text).report
        XCTAssertEqual(report.omittedWords, 5)
        XCTAssertEqual(report.examples.count, 3)
        XCTAssertTrue(report.examples.allSatisfy { $0.count <= 33 })
    }
}
