// Fork-only diagnostic: visual properties only, not an alternate production editor.

@MainActor
private final class EmptyNativeCell: NSTextFieldCell {}

@MainActor
private final class GlyphReferenceCell: NSTextFieldCell {
    nonisolated private func inset(_ rect: NSRect, in bounds: NSRect) -> NSRect {
        var result = rect
        result.origin.x = bounds.minX + 9
        result.size.width = max(0, bounds.maxX - 9 - result.minX)
        return result
    }
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        inset(super.titleRect(forBounds: rect), in: rect)
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        inset(super.drawingRect(forBounds: rect), in: rect)
    }
}

@MainActor
private final class AlignmentContainer: NSView {
    override var alignmentRectInsets: NSEdgeInsets {
        subviews.first?.alignmentRectInsets ?? super.alignmentRectInsets
    }
}

@MainActor
private struct Entry {
    let id: String
    let label: String
    let field: FileManagerTitlePathField
    let container: NSView?
}

@MainActor
private final class ComparisonController: NSObject, NSToolbarDelegate {
    private struct Phase {
        let layout: String
        let modeName: String
        let mode: NSToolbar.DisplayMode
        let focusID: String?
    }
    private let output: URL
    private var window: NSWindow!
    private var toolbar: NSToolbar!
    private var entries: [Entry] = []
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let status = NSTextField(labelWithString: "Preparing comparison")
    private var records: [[String: Any]] = []
    private var widths: [String: NSLayoutConstraint] = [:]
    private var activeIdentifiers: [NSToolbarItem.Identifier] = []
    private var phases: [Phase] = []
    private var currentLayout = ""
    private var sharedWidth: CGFloat = 0
    private var step = 0
    private var captureFailures = 0
    private let path = "/Users"
    private let modes: [(String, NSToolbar.DisplayMode)] = [
        ("icon-and-text", .iconAndLabel), ("icon-only", .iconOnly),
    ]

    init(output: URL) { self.output = output }

    private func configureFrameField(_ field: FileManagerTitlePathField) {
        field.stringValue = path
        field.isEditable = true
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingHead
        field.isAutomaticTextCompletionEnabled = false
        field.controlSize = .large
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.delegate = field
    }

    func start() {
        guard let screen = NSScreen.main else { fatalError("No graphical screen available") }
        let width = min(1400, screen.visibleFrame.width - 32)
        let height = min(640, screen.visibleFrame.height - 32)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Native Path Field Comparison"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.center()

        let variants = [("a", "A Current"), ("b", "B Frame"), ("c", "C No clip"),
                        ("d", "D Insets"), ("e", "E Cell"), ("f", "F Exterior"),
                        ("g", "G XL"), ("h", "H Glyph")]
        let slotWidth = max(64, floor((width - 140) / CGFloat(variants.count)) - 24)
        sharedWidth = slotWidth
        for (id, label) in variants {
            let field: FileManagerTitlePathField
            if id == "b" || id == "h" {
                field = FileManagerTitlePathField(frame: .zero)
                configureFrameField(field)
            } else {
                field = FileManagerTitlePathField(path: path)
            }
            if id == "e" {
                field.cell = EmptyNativeCell(textCell: path)
                configureFrameField(field)
            }
            if id == "f" { field.focusRingType = .exterior }
            if id == "g" { field.controlSize = .extraLarge }
            if id == "h" {
                field.cell = GlyphReferenceCell(textCell: path)
                configureFrameField(field)
                field.controlSize = .extraLarge
                field.font = .systemFont(ofSize: 13.5)
                field.allowsEditingTextAttributes = true
            }
            field.setAccessibilityIdentifier("comparison.\(id)")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
            let content: NSView = id == "d" ? AlignmentContainer() : NSView()
            content.addSubview(field)
            let widthConstraint = content.widthAnchor.constraint(equalToConstant: slotWidth)
            widths[id] = widthConstraint
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                field.topAnchor.constraint(equalTo: content.topAnchor),
                field.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                widthConstraint,
            ])
            if id == "c" {
                field.clipsToBounds = false
                content.clipsToBounds = false
            }
            let identifier = NSToolbarItem.Identifier("comparison.\(id)")
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = content
            item.label = label
            item.isBordered = false
            items[identifier] = item
            entries.append(Entry(id: id, label: label, field: field, container: content))
        }
        installToolbar(layout: "a", mode: modes[0].1)

        let body = window.contentView!
        let legend = NSTextField(wrappingLabelWithString: """
        Native titlebar field comparison — same window, no custom focus-ring drawing

        A  Current ShichiZip field and transparent container
        B  init(frame:) instead of init(string:), otherwise the same configuration
        C  Current field with clipping disabled on the field and transparent container
        D  Container shares the field's native alignmentRectInsets; no fixed height
        E  Empty NSTextFieldCell subclass, otherwise the same configuration
        F  Explicit native exterior focus-ring setting
        G  Native extraLarge control size, otherwise the same configuration
        H  Glyph Atlas visual reference: frame initializer, cell text insets, extraLarge, 13.5pt

        I  Below: the current field outside the toolbar, as a clipping/appearance reference.
        One field receives native focus at a time. All toolbar fields remain visible.
        """)
        legend.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(legend)
        let reference = FileManagerTitlePathField(path: path)
        reference.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(reference)
        entries.append(Entry(id: "i", label: "I Content", field: reference, container: nil))
        status.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(status)
        NSLayoutConstraint.activate([
            legend.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 24),
            legend.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -24),
            legend.topAnchor.constraint(equalTo: body.topAnchor, constant: 24),
            reference.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 24),
            reference.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 20),
            reference.widthAnchor.constraint(equalToConstant: min(500, width - 48)),
            status.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 24),
            status.topAnchor.constraint(equalTo: reference.bottomAnchor, constant: 24),
            status.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -24),
        ])
        // Solo captures control for the tallest item changing the whole toolbar height.
        for (id, _) in variants {
            for mode in modes {
                phases.append(Phase(layout: id, modeName: mode.0, mode: mode.1, focusID: id))
            }
        }
        for mode in modes {
            phases.append(Phase(layout: "combined", modeName: mode.0, mode: mode.1, focusID: nil))
            for entry in entries {
                phases.append(Phase(layout: "combined", modeName: mode.0, mode: mode.1, focusID: entry.id))
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.advance() }
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        activeIdentifiers
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? { items[identifier] }

    private func installToolbar(layout: String, mode: NSToolbar.DisplayMode) {
        if layout == currentLayout {
            toolbar.displayMode = mode
            return
        }
        window.makeFirstResponder(nil)
        if let toolbar {
            for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
        }
        let visible = layout == "combined" ? Array(entries.prefix(8)) : entries.filter { $0.id == layout }
        activeIdentifiers = visible.map { NSToolbarItem.Identifier("comparison.\($0.id)") }
        for entry in entries.prefix(8) {
            widths[entry.id]?.constant = layout == "combined" ? sharedWidth : max(100, window.frame.width - 140)
        }
        let next = NSToolbar(identifier: "NativeFocusComparison.\(layout)")
        next.delegate = self
        next.allowsUserCustomization = false
        next.autosavesConfiguration = false
        next.displayMode = mode
        window.toolbar = next
        toolbar = next
        currentLayout = layout
    }

    private func viewInfo(_ view: NSView) -> [String: Any] {
        let insets = view.alignmentRectInsets
        var value: [String: Any] = [
            "class": NSStringFromClass(type(of: view)), "frame": NSStringFromRect(view.frame),
            "bounds": NSStringFromRect(view.bounds), "visibleRect": NSStringFromRect(view.visibleRect),
            "windowFrame": NSStringFromRect(view.convert(view.bounds, to: nil)),
            "alignmentRect": NSStringFromRect(view.alignmentRect(forFrame: view.frame)),
            "alignmentInsets": ["top": insets.top, "left": insets.left, "bottom": insets.bottom, "right": insets.right],
            "clipsToBounds": view.clipsToBounds, "wantsLayer": view.wantsLayer,
            "focusRingType": view.focusRingType.rawValue,
            "focusRingMaskBounds": NSStringFromRect(view.focusRingMaskBounds),
        ]
        if let layer = view.layer { value["layerMasksToBounds"] = layer.masksToBounds }
        if let field = view as? NSTextField {
            value["intrinsicSize"] = NSStringFromSize(field.intrinsicContentSize)
            value["fittingSize"] = NSStringFromSize(field.fittingSize)
            value["controlSize"] = field.controlSize.rawValue
            value["bezeled"] = field.isBezeled
            value["bordered"] = field.isBordered
            value["maximumNumberOfLines"] = field.maximumNumberOfLines
            value["editable"] = field.isEditable
            if let font = field.font { value["font"] = font.fontName; value["fontSize"] = font.pointSize }
            if let cell = field.cell {
                value["cellClass"] = NSStringFromClass(type(of: cell))
                value["cellFocusRingType"] = cell.focusRingType.rawValue
                value["cellDrawingRect"] = NSStringFromRect(cell.drawingRect(forBounds: field.bounds))
            }
        }
        return value
    }

    private func ancestors(of view: NSView) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var parent = view.superview
        while let value = parent { result.append(viewInfo(value)); parent = value.superview }
        return result
    }

    private func advance() {
        guard step < phases.count else { finish(); return }
        let phase = phases[step]
        installToolbar(layout: phase.layout, mode: phase.mode)
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        if let id = phase.focusID, let entry = entries.first(where: { $0.id == id }) {
            entry.field.selectText(nil)
            status.stringValue = "\(phase.layout) / \(phase.modeName) — focused: \(entry.label)"
        } else {
            window.makeFirstResponder(nil)
            status.stringValue = "\(phase.layout) / \(phase.modeName) — idle"
        }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.capture(phase: phase) }
    }

    private func capture(phase: Phase) {
        let suffix = phase.focusID ?? "idle"
        let filename = String(format: "%02d-", step) + phase.layout + "-" + phase.modeName + "-" + suffix + ".png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(filename).path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        var code: Int32 = -1
        var captureError = ""
        do {
            try process.run()
            process.waitUntilExit()
            code = process.terminationStatus
            errorPipe.fileHandleForWriting.closeFile()
            captureError = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { captureError = String(describing: error) }
        if code != 0 { captureFailures += 1 }
        var fields: [[String: Any]] = []
        for entry in entries {
            var field = viewInfo(entry.field)
            field["id"] = entry.id; field["label"] = entry.label
            field["ancestors"] = ancestors(of: entry.field)
            field["hasFieldEditor"] = entry.field.currentEditor() != nil
            if let container = entry.container { field["container"] = viewInfo(container) }
            if let item = items[NSToolbarItem.Identifier("comparison.\(entry.id)")] {
                field["toolbarItemBordered"] = item.isBordered
                field["toolbarItemVisible"] = item.isVisible
            }
            fields.append(field)
        }
        records.append(["screenshot": filename, "displayMode": phase.modeName,
                        "layout": phase.layout, "focused": phase.focusID ?? "none",
                        "contentLayoutRect": NSStringFromRect(window.contentLayoutRect),
                        "windowFrame": NSStringFromRect(window.frame), "isKeyWindow": window.isKeyWindow,
                        "appActive": NSApp.isActive, "captureExit": code, "captureError": captureError,
                        "fields": fields])
        print("Captured \(filename), status=\(code)")
        step += 1
        advance()
    }

    private func finish() {
        do {
            let payload: [String: Any] = ["osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                                         "screenFrame": NSStringFromRect(NSScreen.main!.frame),
                                         "captureFailures": captureFailures, "records": records]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("geometry-and-clipping.json"), options: .atomic)
            print("Completed \(records.count) native focus comparisons; failures=\(captureFailures)")
            exit(captureFailures == 0 ? 0 : 1)
        } catch { print("Could not save diagnostic data: \(error)"); exit(2) }
    }
}

@main
private struct NativeFocusComparison {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected output directory") }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .aqua)
        let controller = ComparisonController(output: URL(fileURLWithPath: CommandLine.arguments[1]))
        controller.start()
        withExtendedLifetime(controller) { app.run() }
    }
}
