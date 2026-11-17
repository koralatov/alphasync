import XCTest
@testable import AlphaSyncUI

final class AppMetadataTests: XCTestCase {
    func testPrivateNotesUseTheExplicitSourceReferenceBeforePublication() {
        let url = AppMetadata.releaseNotesURL(version: "2.0.5", tag: "v2.0.5", development: false, sourceRef: "master")
        XCTAssertEqual(url.absoluteString, "https://github.com/koralatov/alphasync/blob/master/releases/2.0.5.md")
    }

    func testPublishedNotesRetainTheExactReleaseTag() {
        for sourceRef in [nil, ""] as [String?] {
            let url = AppMetadata.releaseNotesURL(version: "2.0.2", tag: "v2.0.2-build.152", development: false, sourceRef: sourceRef)
            XCTAssertEqual(url.absoluteString, "https://github.com/koralatov/alphasync/releases/tag/v2.0.2-build.152")
        }
    }

    func testDevelopmentNotesRetainTheSourceFallback() {
        let url = AppMetadata.releaseNotesURL(version: "2.0.5", tag: "v2.0.5", development: true, sourceRef: nil)
        XCTAssertEqual(url.absoluteString, "https://github.com/koralatov/alphasync/blob/master/releases/2.0.5.md")
    }
}
