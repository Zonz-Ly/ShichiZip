import AppKit
import ShichiZipQuickActionCore

@MainActor
final class AppFileServicesProvider: NSObject {
    private let handleRequest: (ShichiZipQuickActionRequest) throws -> Void

    init(handleRequest: @escaping (ShichiZipQuickActionRequest) throws -> Void) {
        self.handleRequest = handleRequest
    }

    @objc func performFileAction(_ pasteboard: NSPasteboard,
                                userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString?>)
    {
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.record("service.received", ["userData": userData ?? "nil",
                "types": pasteboard.types?.map { $0.rawValue } ?? [], "mainThread": Thread.isMainThread])
        #endif
        do {
            guard let userData, let action = ShichiZipQuickAction(rawValue: userData) else {
                throw ShichiZipQuickActionError.invalidPayload
            }
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty
            else {
                throw CocoaError(.fileReadInvalidFileName)
            }

            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("service.selection-decoded", ["action": action.rawValue, "count": urls.count])
            #endif
            try handleRequest(ShichiZipQuickActionRequest(action: action, fileURLs: urls))
            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("service.request-handler-returned")
            #endif
        } catch let failure {
            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("service.failed", ["error": String(describing: failure)])
            #endif
            error.pointee = failure.localizedDescription as NSString
        }
    }
}
