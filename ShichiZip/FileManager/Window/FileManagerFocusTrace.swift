#if SHICHIZIP_FOCUS_TRACE
import AppKit
import Foundation
import QuartzCore

/// Temporary full-app diagnostics. Buffers only; no fieldEditor lookup or disk IO during focus/click handling.
@MainActor
enum FileManagerFocusTrace {
    private static var events: [[String: Any]] = []
    private static var exportScheduled = false

    static func record(_ stage: String, window: NSWindow?, field: NSTextField?, event: NSEvent? = nil,
                       requestedResponder: NSResponder? = nil, result: Bool? = nil) {
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
        if let currentEvent = NSApp.currentEvent {
            row["currentEventType"] = currentEvent.type.rawValue
            row["currentEventWindow"] = currentEvent.windowNumber
        }
        if stage.hasPrefix("responder.") {
            row["requestedResponder"] = identity(requestedResponder)
        }
        if let result { row["accepted"] = result }
        if let event {
            row["mouseType"] = event.type.rawValue
            row["mouseLocation"] = NSStringFromPoint(event.locationInWindow)
            row["clickCount"] = event.clickCount
        }
        if let field {
            row["fieldFrame"] = NSStringFromRect(field.frame)
            row["fieldBounds"] = NSStringFromRect(field.bounds)
            row["fieldInWindow"] = NSStringFromRect(field.convert(field.bounds, to: nil))
            if let event {
                let point = field.convert(event.locationInWindow, from: nil)
                row["mouseInField"] = NSStringFromPoint(point)
                row["mouseInsideField"] = field.bounds.contains(point)
            }
            row["fieldSuperview"] = identity(field.superview)
            row["bezeled"] = field.isBezeled
            row["bordered"] = field.isBordered
            row["controlSize"] = field.controlSize.rawValue
            row["cellShowsFirstResponder"] = field.cell?.showsFirstResponder ?? false
            row["cellHighlighted"] = field.cell?.isHighlighted ?? false
            row["fieldFocusRingType"] = field.focusRingType.rawValue
            // Read existing native views/layers only; never create or mutate them.
            var ancestors: [[String: Any]] = []
            var ancestor: NSView? = field
            while let view = ancestor, ancestors.count < 5 {
                var node: [String: Any] = [
                    "view": identity(view), "frame": NSStringFromRect(view.frame),
                    "hidden": view.isHidden, "alpha": view.alphaValue,
                    "needsLayout": view.needsLayout, "needsDisplay": view.needsDisplay,
                    "focusRingType": view.focusRingType.rawValue,
                ]
                if let layer = view.layer {
                    node["layer"] = identity(layer)
                    node["animations"] = (layer.animationKeys() ?? []).map { key in
                        let animation = layer.animation(forKey: key)
                        return ["key": key, "duration": animation?.duration ?? 0,
                                "beginTime": animation?.beginTime ?? 0] as [String: Any]
                    }
                }
                ancestors.append(node)
                ancestor = view.superview
            }
            row["nativeViewChain"] = ancestors
        }
        if let editor {
            row["editorFrame"] = NSStringFromRect(editor.frame)
            row["editorBounds"] = NSStringFromRect(editor.bounds)
            row["editorInWindow"] = NSStringFromRect(editor.convert(editor.bounds, to: nil))
            if let event {
                let point = editor.convert(event.locationInWindow, from: nil)
                row["mouseInEditor"] = NSStringFromPoint(point)
                row["mouseInsideEditor"] = editor.visibleRect.contains(point)
            }
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
                "traceVersion": 2,
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
