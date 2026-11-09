import XCTest
@testable import AlphaSyncCore

final class DictionaryImportTests: XCTestCase {
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
