import AppKit

@MainActor
final class BackgroundComparison: NSObject, NSApplicationDelegate {
    private let output: URL
    private var window: NSWindow?
    private var controller: FileManagerPathToolbar?
    private var field: FileManagerTitlePathField?
    private var index = 0
    private var records: [[String: Any]] = []
    private var failures: [String] = []
    private let variants = ["current", "toolbar-border", "field-background", "restore-bezel"]
    private let modes: [(String, NSToolbar.DisplayMode)] = [
        ("icon-only", .iconOnly), ("icon-and-text", .iconAndLabel), ("text-only", .labelOnly),
    ]

    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        next()
    }

    private func properties(_ field: NSTextField) -> [String: Any] {
        ["bezeled": field.isBezeled, "bordered": field.isBordered,
         "drawsBackground": field.drawsBackground, "controlSize": field.controlSize.rawValue,
         "fittingSize": NSStringFromSize(field.fittingSize),
         "frame": NSStringFromRect(field.frame), "bounds": NSStringFromRect(field.bounds),
         "hasEditor": field.currentEditor() != nil,
         "fontSize": field.font?.pointSize ?? 0]
    }

    private func next() {
        controller = nil
        field = nil
        window?.close()
        window = nil
        guard index < variants.count * modes.count * 2 * 2 else { finish(); return }
        let variant = variants[index % variants.count]
        let focused = (index / variants.count) % 2 == 1
        let mode = modes[(index / (variants.count * 2)) % modes.count]
        let dark = index / (variants.count * 2 * modes.count) == 1
        let appearance = dark ? "dark" : "light"

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 320),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Native Path Background Comparison"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.toolbarStyle = .unified
        let original = NSToolbar(identifier: "BackgroundComparisonOriginal")
        original.displayMode = mode.1
        window.toolbar = original
        window.center()
        let label = NSTextField(wrappingLabelWithString: """
        \(variant) · \(appearance) · \(mode.0) · \(focused ? "focused" : "idle")

        current: production code, unchanged.
        toolbar-border: enable NSToolbarItem.isBordered after installation.
        field-background: enable NSTextField.drawsBackground after installation.
        restore-bezel: set NSTextField.isBezeled again after installation.

        Actual production path field and toolbar classes. No custom drawing, background colors, containers, fonts or heights.
        """)
        label.frame = NSRect(x: 24, y: 32, width: 950, height: 240)
        label.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(label)
        let field = FileManagerTitlePathField(path: "/Users/runner/Documents/資料夾")
        let before = properties(field)
        let controller = FileManagerPathToolbar(window: window, field: field)
        controller.install()
        let afterInstallation = properties(field)
        switch variant {
        case "toolbar-border": window.toolbar?.items.first?.isBordered = true
        case "field-background": field.drawsBackground = true
        case "restore-bezel": field.isBezeled = true
        default: break
        }
        self.window = window
        self.field = field
        self.controller = controller
        window.makeKeyAndOrderFront(nil)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            if focused { field.beginPathEditing() } else { window.makeFirstResponder(nil) }
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                let name = String(format: "%02d", index) + "-\(variant)-\(appearance)-\(mode.0)-\(focused ? "focused" : "idle").png"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(name).path]
                do { try process.run(); process.waitUntilExit() } catch { failures.append(error.localizedDescription) }
                if process.terminationStatus != 0 { failures.append("Capture failed: \(name)") }
                if focused && field.currentEditor() == nil { failures.append("Focus missing: \(name)") }
                records.append(["variant": variant, "appearance": appearance, "mode": mode.0,
                                "focused": focused, "screenshot": name,
                                "beforeToolbar": before, "afterInstallation": afterInstallation,
                                "final": properties(field),
                                "toolbarItemBordered": window.toolbar?.items.first?.isBordered ?? false,
                                "windowKey": window.isKeyWindow])
                index += 1
                next()
            }
        }
    }

    private func finish() {
        let report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "records": records, "failures": failures]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("results.json"))
        } catch { print(error) }
        print("Captured \(records.count) states; failures: \(failures)")
        NSApplication.shared.terminate(nil)
    }
}

@main
struct BackgroundComparisonMain {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = BackgroundComparison(output: output)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
