import Foundation
import XCTest
@testable import AlphaSyncCore

final class OperationFailureTests: XCTestCase {
    func testValidationBeforeAnyWriteReportsUnchangedContents() {
        let failure = OperationFailure(NeoError.unsupportedCharacter("🙂"), action: .add)
        XCTAssertEqual(failure.completedFiles, 0)
        XCTAssertFalse(failure.currentFileMayHaveChanged)
        XCTAssertTrue(failure.localizedDescription.contains("No device files were changed."))
    }

    func testLaterValidationFailureRetainsEarlierCompletedFiles() {
        let child = OperationFailure(NeoError.limitsUnavailable, action: .add)
        let batch = OperationFailure(child, action: .add, completedFiles: 2)
        XCTAssertEqual(batch.completedFiles, 2)
        XCTAssertFalse(batch.currentFileMayHaveChanged)
        XCTAssertFalse(batch.localizedDescription.contains("No device files were changed."))
    }

    func testVerifiedCreationIsCountedEvenIfItsRefreshFails() {
        let child = OperationFailure(NeoError.disconnected, action: .add, completedFiles: 1)
        let batch = OperationFailure(child, action: .add, completedFiles: 2)
        XCTAssertEqual(batch.completedFiles, 3)
    }

    func testUnverifiedWriteKeepsRecoveryAndItsOriginalError() {
        let folder = URL(fileURLWithPath: "/Recovery Copies/Original")
        let write = NeoWriteError(underlying: NeoError.verificationFailed)
        let child = OperationFailure(write, action: .change, recoveryFolder: folder)
        let batch = OperationFailure(child, action: .change, completedFiles: 1)
        XCTAssertEqual(batch.completedFiles, 1)
        XCTAssertTrue(batch.currentFileMayHaveChanged)
        XCTAssertEqual(batch.recoveryFolder, folder)
        XCTAssertEqual(batch.underlying as? NeoError, .verificationFailed)
        XCTAssertFalse(batch.localizedDescription.contains("No device files were changed."))
    }
}
