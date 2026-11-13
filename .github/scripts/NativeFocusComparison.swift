// Fork-only experiment. No custom cell, editor hooks, or comparison UI enters the product branch.
@MainActor
private final class NinePointCell: NSTextFieldCell {
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
private final class NativeInsetField: NSTextField {
    private weak var insetEditor: NSTextView?
    private var originalEditorInset: NSSize?
    private var extraInset: CGFloat {
        9 - ((cell?.drawingRect(forBounds: bounds).minX ?? bounds.minX) - bounds.minX)
    }

    override func layout() {
        super.layout()
        updateDisplayInsets()
    }

    private func updateDisplayInsets() {
        guard currentEditor() == nil, !stringValue.isEmpty else { return }
        let paragraph = (attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                         as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        let delta = extraInset
        guard paragraph.headIndent != delta || paragraph.firstLineHeadIndent != delta || paragraph.tailIndent != -delta else { return }
        paragraph.headIndent = delta
        paragraph.firstLineHeadIndent = delta
        paragraph.tailIndent = -delta
        paragraph.lineBreakMode = lineBreakMode
        let text = NSMutableAttributedString(attributedString: attributedStringValue)
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        attributedStringValue = text
    }

    private func updateEditorInsets() {
        guard let editor = currentEditor() as? NSTextView else { return }
        if insetEditor !== editor {
            insetEditor = editor
            originalEditorInset = editor.textContainerInset
        }
        editor.textStorage?.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: (editor.string as NSString).length))
        var attributes = editor.typingAttributes
        attributes.removeValue(forKey: .paragraphStyle)
        editor.typingAttributes = attributes
        editor.defaultParagraphStyle = nil
        editor.textContainerInset = NSSize(width: extraInset, height: originalEditorInset?.height ?? 0)
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        updateEditorInsets()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { updateEditorInsets() }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        updateEditorInsets()
    }
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        updateEditorInsets()
    }
    override func textDidEndEditing(_ notification: Notification) {
        if let editor = insetEditor, let originalEditorInset {
            editor.textContainerInset = originalEditorInset
        }
        insetEditor = nil
        originalEditorInset = nil
        super.textDidEndEditing(notification)
        updateDisplayInsets()
    }
}

@MainActor
private final class ComparisonController: NSObject, NSToolbarDelegate {
    private struct Entry {
        let id: String
        let label: String
        let field: NSTextField
        let width: NSLayoutConstraint
    }
    private struct Phase {
        let layout: String
        let modeName: String
        let mode: NSToolbar.DisplayMode
        let text: String
        let focusID: String?
        let state: String
    }
    private let output: URL
    private var window: NSWindow!
    private var toolbar: NSToolbar!
    private var entries: [Entry] = []
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let status = NSTextField(labelWithString: "Preparing comparison")
    private var phases: [Phase] = []
    private var records: [[String: Any]] = []
    private var activeIdentifiers: [NSToolbarItem.Identifier] = []
    private var step = 0
    private var captureFailures = 0
    private var validationFailures: [String] = []
    private var previousEditorInsetAfterRelease = "none"
    private let texts = ["/Users/zonz", "/Users/zonz/Documents/資料/" + String(repeating: "Long-folder-漢字-", count: 12) + "archive.zip/nested"]
    private let modes: [(String, NSToolbar.DisplayMode)] = [("icon-and-text", .iconAndLabel), ("icon-only", .iconOnly)]

    init(output: URL) { self.output = output }

    func start() {
        guard let screen = NSScreen.main else { fatalError("No graphical screen") }
        let width = min(1400, screen.visibleFrame.width - 32)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Native 9pt Insets Comparison"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.center()

        for (id, label) in [("a", "A System"), ("b", "B Cell 9pt"), ("c", "C Native 9pt")] {
            let reference = FileManagerTitlePathField(path: texts[0])
            let field: NSTextField = id == "c" ? NativeInsetField(string: texts[0]) : FileManagerTitlePathField(path: texts[0])
            let originalFont = reference.font
            if id == "b" { field.cell = NinePointCell(textCell: texts[0]) }
            field.font = originalFont
            field.controlSize = reference.controlSize
            field.isEditable = reference.isEditable
            field.isSelectable = reference.isSelectable
            field.lineBreakMode = reference.lineBreakMode
            field.isAutomaticTextCompletionEnabled = reference.isAutomaticTextCompletionEnabled
            field.bezelStyle = reference.bezelStyle
            field.isBezeled = reference.isBezeled
            field.allowsEditingTextAttributes = reference.allowsEditingTextAttributes
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
            field.setAccessibilityIdentifier("comparison.\(id)")
            let constraint = field.widthAnchor.constraint(equalToConstant: 240)
            constraint.isActive = true
            let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(id))
            item.view = field
            item.label = label
            item.isBordered = false
            entries.append(Entry(id: id, label: label, field: field, width: constraint))
            items[item.itemIdentifier] = item
        }
        let body = window.contentView!
        let legend = NSTextField(wrappingLabelWithString: """
        All variants: native extraLarge size, original system font, original plain-text editing, init(string:).
        Each field is hosted directly by its NSToolbarItem. No extra container or fixed height.

        A System: current production candidate, unmodified native text insets.
        B Cell 9pt: custom NSTextFieldCell sets text drawing edges to 9pt.
        C Native 9pt: standard cell, paragraph indents while idle; textContainerInset while editing.

        Solo + combined comparisons; short + long Unicode paths; idle, selected, caret and edited states.
        C restores the shared field editor's previous inset when editing ends.
        """)
        legend.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(legend)
        body.addSubview(status)
        NSLayoutConstraint.activate([
            legend.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 24),
            legend.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -24),
            legend.topAnchor.constraint(equalTo: body.topAnchor, constant: 24),
            status.leadingAnchor.constraint(equalTo: legend.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: legend.trailingAnchor),
            status.topAnchor.constraint(equalTo: legend.bottomAnchor, constant: 24),
        ])
        for entry in entries {
            for mode in modes {
                for text in texts {
                    for state in ["idle", "selected", "caret", "edited"] {
                        phases.append(Phase(layout: entry.id, modeName: mode.0, mode: mode.1, text: text,
                                            focusID: state == "idle" ? nil : entry.id, state: state))
                    }
                }
            }
        }
        for mode in modes {
            phases.append(Phase(layout: "combined", modeName: mode.0, mode: mode.1, text: texts[0], focusID: nil, state: "idle"))
            for entry in entries {
                phases.append(Phase(layout: "combined", modeName: mode.0, mode: mode.1, text: texts[0], focusID: entry.id, state: "selected"))
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.advance() }
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] { activeIdentifiers }
    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] { Array(items.keys) }
    func toolbar(_: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? { items[identifier] }

    private func advance() {
        guard step < phases.count else { finish(); return }
        let phase = phases[step]
        let previousEditor = window.firstResponder as? NSTextView
        window.makeFirstResponder(nil)
        previousEditorInsetAfterRelease = previousEditor.map { NSStringFromSize($0.textContainerInset) } ?? "none"
        if let previousEditor, previousEditor.textContainerInset != .zero {
            validationFailures.append("Phase \(step): shared editor retained inset \(previousEditor.textContainerInset)")
        }
        if let toolbar {
            for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
        }
        let visible = phase.layout == "combined" ? entries : entries.filter { $0.id == phase.layout }
        activeIdentifiers = visible.map { NSToolbarItem.Identifier($0.id) }
        for entry in entries {
            entry.field.stringValue = phase.text
            entry.width.constant = phase.layout == "combined" ? floor((window.frame.width - 180) / 3) : window.frame.width - 140
            entry.field.needsLayout = true
        }
        let next = NSToolbar(identifier: "NinePointComparison.\(step)")
        next.delegate = self
        next.displayMode = phase.mode
        window.toolbar = next
        toolbar = next
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        if let entry = entries.first(where: { $0.id == phase.focusID }) {
            entry.field.selectText(nil)
            if let editor = entry.field.currentEditor() as? NSTextView {
                if phase.state == "caret" || phase.state == "edited" {
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                    if phase.state == "edited" { editor.insertText("-試験", replacementRange: editor.selectedRange()) }
                    editor.scrollRangeToVisible(editor.selectedRange())
                }
            }
        }
        status.stringValue = "\(phase.layout) / \(phase.modeName) / \(phase.text.count > 100 ? "long" : "short") / \(phase.state)"
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.capture(phase) }
    }

    private func fieldInfo(_ field: NSTextField) -> [String: Any] {
        var info: [String: Any] = ["class": NSStringFromClass(type(of: field)), "frame": NSStringFromRect(field.frame),
            "windowFrame": NSStringFromRect(field.convert(field.bounds, to: nil)), "bounds": NSStringFromRect(field.bounds),
            "controlSize": field.controlSize.rawValue, "fontSize": field.font?.pointSize ?? 0,
            "allowsEditingTextAttributes": field.allowsEditingTextAttributes, "string": field.stringValue,
            "bezeled": field.isBezeled, "bordered": field.isBordered]
        if let cell = field.cell {
            info["cellClass"] = NSStringFromClass(type(of: cell))
            info["cellDrawingRect"] = NSStringFromRect(cell.drawingRect(forBounds: field.bounds))
        }
        if let editor = field.currentEditor() as? NSTextView {
            info["editorFrameInField"] = NSStringFromRect(field.convert(editor.bounds, from: editor))
            info["textContainerInset"] = NSStringFromSize(editor.textContainerInset)
            info["textContainerOrigin"] = NSStringFromPoint(editor.textContainerOrigin)
            info["lineFragmentPadding"] = editor.textContainer?.lineFragmentPadding
            info["selection"] = NSStringFromRange(editor.selectedRange())
            info["editorString"] = editor.string
            info["richText"] = editor.isRichText
            info["caretAtStart"] = NSStringFromRect(editor.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil))
        }
        return info
    }

    private func capture(_ phase: Phase) {
        let visible = phase.layout == "combined" ? entries : entries.filter { $0.id == phase.layout }
        for entry in visible {
            if !entry.field.isEditable || !entry.field.isBezeled {
                validationFailures.append("Phase \(step): \(entry.id) lost editable/native-bezel configuration")
            }
            if abs(entry.field.frame.height - entries[0].field.fittingSize.height) > 1 {
                validationFailures.append("Phase \(step): \(entry.id) differs from native fitting height")
            }
        }
        if let id = phase.focusID, let field = entries.first(where: { $0.id == id })?.field {
            if field.currentEditor() == nil {
                validationFailures.append("Phase \(step): \(id) did not receive a field editor")
            } else {
                let expected = phase.text + (phase.state == "edited" ? "-試験" : "")
                if (field.currentEditor() as? NSTextView)?.string != expected {
                    validationFailures.append("Phase \(step): \(id) editing changed unexpected text")
                }
            }
        }
        let filename = String(format: "%02d", step) + "-\(phase.layout)-\(phase.modeName)-\(phase.text.count > 100 ? "long" : "short")-\(phase.state).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.appendingPathComponent(filename).path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { captureFailures += 1 }
        } catch { captureFailures += 1; print(error) }
        records.append(["screenshot": filename, "displayMode": phase.modeName, "layout": phase.layout,
                        "state": phase.state, "focused": phase.focusID ?? "none", "isKeyWindow": window.isKeyWindow,
                        "previousEditorInsetAfterRelease": previousEditorInsetAfterRelease,
                        "fields": entries.map { ["id": $0.id, "properties": fieldInfo($0.field)] }])
        print("Captured \(filename)")
        step += 1
        advance()
    }

    private func finish() {
        do {
            let payload: [String: Any] = ["osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                                         "captureFailures": captureFailures, "validationFailures": validationFailures, "records": records]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("geometry-and-clipping.json"), options: .atomic)
            print("Completed \(records.count) comparisons; failures=\(captureFailures)")
            for failure in validationFailures { print("Validation failure: \(failure)") }
            exit(captureFailures == 0 && validationFailures.isEmpty ? 0 : 1)
        } catch { print(error); exit(2) }
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
