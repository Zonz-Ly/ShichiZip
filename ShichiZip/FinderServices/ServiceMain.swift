import AppKit
import ShichiZipQuickActionCore

@main
struct FinderServiceMain {
    @MainActor static func main() {
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.bootstrap("finder-service")
        #endif
        let app = NSApplication.shared
        let provider = AppFileServicesProvider { request in
            let launchURL = try ShichiZipQuickActionTransport.launchURL(for: request)
            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("service.launch-request", ["action": request.action.rawValue,
                    "count": request.paths.count, "url": launchURL,
                    "resolvedApplication": NSWorkspace.shared.urlForApplication(toOpen: launchURL)?.path ?? "missing"])
            #endif
            let opened = NSWorkspace.shared.open(launchURL)
            #if SHICHIZIP_DIAGNOSTICS
                SZServiceDiagnostics.record("service.workspace-open", ["accepted": opened])
            #endif
            guard opened else {
                ShichiZipQuickActionTransport.releasePayload(for: launchURL)
                throw ShichiZipQuickActionError.launchFailed
            }
        }
        app.servicesProvider = provider
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.record("service.provider-installed", [
                "responds": provider.responds(to: #selector(AppFileServicesProvider.performFileAction(_:userData:error:)))])
            DispatchQueue.main.async { SZServiceDiagnostics.record("service.main-runloop-active") }
        #endif
        app.run()
        #if SHICHIZIP_DIAGNOSTICS
            SZServiceDiagnostics.record("service.run-returned")
        #endif
    }
}
