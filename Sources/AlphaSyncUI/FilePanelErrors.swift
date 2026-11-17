import Foundation

func isFilePanelCancellation(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
}
