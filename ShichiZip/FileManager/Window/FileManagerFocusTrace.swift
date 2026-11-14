#if SHICHIZIP_FOCUS_TRACE
import AppKit
import Foundation

/// Temporary full-app diagnostics. Buffers only; no fieldEditor lookup or disk IO during focus/click handling.
@MainActor
enum FileManagerFocusTrace {
    private static var events: [[String: Any]] = []
    private static var exportScheduled = false

    static func record(_ stage: String, window: NSWindow?, field: NSTextField?, event: NSEvent? = nil) {
        guard events.count < 1000 else { return }
        func identity(_ object: AnyObject?) -> String {
            guard let object else { return "nil" }
            return "\(type(of: object)) \(ObjectIdentifier(object))"
        }
        let editor = field?.currentEditor() as? NSTextView
        var row: [String: Any] = [
            "stage": stage, "uptime": ProcessInfo.processInfo.systemUptime,
            "window": window?.windowNumber ?? -1,
            "appActive": NSApp.isActive, "keyWindow": window?.isKeyWindow ?? false,
            "mainWindow": window?.isMainWindow ?? false,
            "firstResponder": identity(window?.firstResponder),
            "field": identity(field), "editor": identity(editor),
            "editorIsFirstResponder": editor != nil && window?.firstResponder === editor,
            "toolbar": window?.toolbar?.identifier ?? "nil",
            "toolbarStyle": window?.toolbarStyle.rawValue ?? -1,
            "toolbarMode": window?.toolbar?.displayMode.rawValue ?? -1,
        ]
        if let event {
            row["mouseType"] = event.type.rawValue
            row["mouseLocation"] = NSStringFromPoint(event.locationInWindow)
            row["clickCount"] = event.clickCount
        }
        if let field {
            row["fieldFrame"] = NSStringFromRect(field.frame)
            row["fieldBounds"] = NSStringFromRect(field.bounds)
            row["fieldSuperview"] = identity(field.superview)
            row["bezeled"] = field.isBezeled
            row["bordered"] = field.isBordered
            row["controlSize"] = field.controlSize.rawValue
            row["cellShowsFirstResponder"] = field.cell?.showsFirstResponder ?? false
            row["cellHighlighted"] = field.cell?.isHighlighted ?? false
        }
        if let editor {
            row["editorFrame"] = NSStringFromRect(editor.frame)
            row["editorBounds"] = NSStringFromRect(editor.bounds)
            row["editorSuperview"] = identity(editor.superview)
            row["editorDelegate"] = identity(editor.delegate as AnyObject?)
            row["editorInset"] = NSStringFromSize(editor.textContainerInset)
            row["selection"] = NSStringFromRange(editor.selectedRange())
        }
        events.append(row)
    }

    static func exportAfterInteraction() {
        guard !exportScheduled else { return }
        exportScheduled = true
        // Diagnostic export only: does not delay or schedule any focus/layout operation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            exportScheduled = false
            export()
        }
    }

    private static func export() {
        do {
            let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
            let folder = desktop.appendingPathComponent("ShichiZip-Full-App-Focus", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let report: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "build": Bundle.main.object(forInfoDictionaryKey: "ShichiZipGitShortHash") ?? "unknown",
                "pid": ProcessInfo.processInfo.processIdentifier,
                "note": "Original full-app flow; no fieldEditor prewarming, no focus fix, no typed text logged.",
                "events": events,
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            let file = folder.appendingPathComponent("focus-\(ProcessInfo.processInfo.processIdentifier).json")
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("[FullAppFocusTrace] Export failed: %@", String(describing: error))
        }
    }
}
#endif
