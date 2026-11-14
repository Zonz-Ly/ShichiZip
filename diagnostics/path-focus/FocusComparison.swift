import AppKit
@MainActor enum SZL10n { static func string(_ key: String) -> String { "Path" } }
/// A native toolbar-sized path editor, with the pane address field's navigation behavior.
final class FileManagerTitlePathField: NSTextField, NSTextFieldDelegate {
    var onSubmit: ((String) -> Bool)?
    var onFinish: (() -> Void)?
    private var isFinished = false
    private var isSubmitting = false
    private var isRestoringSheetFocus = false
    private weak var insetEditor: NSTextView?
    private var originalEditorInset: NSSize?

    convenience init(path: String) {
        self.init(string: path)
        lineBreakMode = .byTruncatingHead
        isAutomaticTextCompletionEnabled = false
        if #available(macOS 26.0, *) {
            controlSize = .extraLarge
        } else {
            controlSize = .large
        }
        bezelStyle = .roundedBezel
        isBezeled = true
        delegate = self
        setAccessibilityIdentifier("fileManager.titlePathField")
    }

    // Target 9pt text margins without replacing the native cell or changing control height.
    private var extraTextInset: CGFloat {
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
        let delta = extraTextInset
        guard paragraph.headIndent != delta || paragraph.firstLineHeadIndent != delta ||
            paragraph.tailIndent != -delta else { return }
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
        editor.textStorage?.removeAttribute(.paragraphStyle,
                                           range: NSRange(location: 0, length: (editor.string as NSString).length))
        var attributes = editor.typingAttributes
        attributes.removeValue(forKey: .paragraphStyle)
        editor.typingAttributes = attributes
        editor.defaultParagraphStyle = nil
        var inset = editor.textContainerInset
        inset.width = extraTextInset
        editor.textContainerInset = inset
    }

    func controlTextDidChange(_: Notification) {
        updateEditorInsets()
    }

    private func restoreEditorInsets() {
        // AppKit shares this editor with the other text fields in the window.
        if let editor = insetEditor, let originalEditorInset {
            editor.textContainerInset = originalEditorInset
        }
        insetEditor = nil
        originalEditorInset = nil
    }

    override func textDidEndEditing(_ notification: Notification) {
        restoreEditorInsets()
        super.textDidEndEditing(notification)
        updateDisplayInsets()
    }

    func install() {
        NotificationCenter.default.addObserver(self, selector: #selector(sheetDidEnd(_:)),
                                               name: NSWindow.didEndSheetNotification, object: window)
    }

    func uninstall() {
        restoreEditorInsets()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didEndSheetNotification, object: window)
    }

    func beginPathEditing() {
        guard !isFinished else { return }
        selectText(nil)
        updateEditorInsets()
    }

    @objc private func sheetDidEnd(_: Notification) {
        // Let AppKit finish restoring the sheet's previous first responder first.
        isRestoringSheetFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            beginPathEditing()
            isRestoringSheetFocus = false
        }
    }

    func cancelPathEditing() {
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish?()
    }

    func controlTextDidEndEditing(_: Notification) {
        guard !isSubmitting, !isRestoringSheetFocus, window?.attachedSheet == nil else { return }
        finish()
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            finish()
        case #selector(NSResponder.insertNewline(_:)):
            isSubmitting = true
            let accepted = onSubmit?(stringValue) ?? false
            isSubmitting = false
            if accepted {
                finish()
            } else if window?.attachedSheet != nil {
                isRestoringSheetFocus = true
            } else {
                beginPathEditing()
            }
        default:
            return false
        }
        return true
    }
}

/// Uses a separate native toolbar for path editing, preserving the user's toolbar object and layout.
@MainActor
final class FileManagerPathToolbar: NSObject, NSToolbarDelegate {
    private static let pathItem = NSToolbarItem.Identifier("fm_path")
    private weak var window: NSWindow?
    private let originalToolbar: NSToolbar?
    private let originalTitleVisibility: NSWindow.TitleVisibility
    private let toolbar = NSToolbar(identifier: "FileManagerPathToolbar")
    private let item = NSToolbarItem(itemIdentifier: FileManagerPathToolbar.pathItem)
    private let widthLimit: NSLayoutConstraint

    init(window: NSWindow, field: NSTextField) {
        self.window = window
        originalToolbar = window.toolbar
        originalTitleVisibility = window.titleVisibility
        // AppKit allocates the available toolbar width and owns all item geometry.
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        widthLimit = field.widthAnchor.constraint(lessThanOrEqualToConstant: window.frame.width)
        widthLimit.isActive = true
        item.view = field
        item.label = SZL10n.string("column.path")
        // Modern toolbars supply the field's native background through the item border.
        if #available(macOS 26.0, *) {
            item.isBordered = true
        } else {
            item.isBordered = false
        }
        super.init()
        toolbar.delegate = self
        // Text-only mode must still show the editor. Modern toolbars keep their
        // label row in icon-and-label mode so entering a path does not resize the window content.
        toolbar.displayMode = .iconOnly
        if #available(macOS 26.0, *), originalToolbar?.displayMode == .iconAndLabel {
            toolbar.displayMode = .iconAndLabel
        }
    }

    func install() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.subtitle = ""
        window.toolbar = toolbar
        window.contentView?.superview?.layoutSubtreeIfNeeded()
    }

    func restore() {
        guard let window else { return }
        window.toolbar = originalToolbar
        window.titleVisibility = originalTitleVisibility
    }

    func updateWidth() {
        guard let window else { return }
        widthLimit.constant = window.frame.width
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.pathItem]
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.pathItem]
    }

    func toolbar(_: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem?
    {
        identifier == Self.pathItem ? item : nil
    }
}

import AppKit

private enum FocusScene: Int, CaseIterable {
    case content, existingToolbar, current, nextTurn, warmEditor, nativeInsets

    var label: String {
        switch self {
        case .content: "A　原生內容區文字框"
        case .existingToolbar: "B　原生工具列文字框（不切換工具列）"
        case .current: "C　我們目前的工具列切換方式"
        case .nextTurn: "D　切換後，下一輪事件迴圈再聚焦"
        case .warmEditor: "E　預先建立共享編輯器，再照現有方式聚焦"
        case .nativeInsets: "F　現有切換方式，不加 9 pt 內距"
        }
    }
}

@MainActor
private final class FocusLog {
    let url: URL

    init() throws {
        let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let folder = desktop.appendingPathComponent("ShichiZip-Focus-Comparison", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        url = folder.appendingPathComponent("focus-\(UUID().uuidString).jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func record(_ values: [String: Any]) {
        do {
            var values = values
            values["timestamp"] = Date().timeIntervalSince1970
            values["uptime"] = ProcessInfo.processInfo.systemUptime
            var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            data.append(0x0a)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Focus comparison log failed: %@", String(describing: error))
        }
    }
}

@MainActor
private final class FocusDemoWindow: NSWindow {
    var opened = false
    var onOpenPath: (() -> Void)?
    var onTrace: ((String) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown, !opened,
           event.locationInWindow.y >= contentLayoutRect.maxY {
            onTrace?("trigger.rightMouseDown")
            onOpenPath?()
            return
        }
        let mouse = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(event.type)
        if mouse, opened { onTrace?("mouse.before.\(event.type.rawValue)") }
        super.sendEvent(event)
        if mouse, opened {
            onTrace?("mouse.after.\(event.type.rawValue)")
            DispatchQueue.main.async { [weak self] in self?.onTrace?("mouse.next-turn") }
        }
    }
}

@MainActor
private final class InitialToolbarDelegate: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("up"), .flexibleSpace, .init("add"), .init("copy")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = identifier.rawValue
        let symbol = identifier.rawValue == "up" ? "chevron.up" : identifier.rawValue == "add" ? "plus.circle" : "doc.on.doc"
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
        return item
    }
}

@MainActor
private final class FocusComparisonController: NSObject, NSApplicationDelegate {
    private var log: FocusLog?
    private var controls: NSWindow?
    private var demo: FocusDemoWindow?
    private var field: NSTextField?
    private var pathToolbar: FileManagerPathToolbar?
    private var initialDelegate: InitialToolbarDelegate?
    private let popup = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "先測 C。若 C 沒有重現二次動畫，請直接回報，不必測其他場景。")
    private var scene: FocusScene = .current
    private var instance = UUID()

    func applicationDidFinishLaunching(_: Notification) {
        do { log = try FocusLog() } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "無法建立桌面對照日誌"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        log?.record(["event": "launch", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                     "build": Bundle.main.object(forInfoDictionaryKey: "ShichiZipGitShortHash") ?? "local",
                     "purpose": "Manual focus comparison only; no preferences, file operations or automated tests."])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 250),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "ShichiZip 聚焦對照（獨立程式）"
        let content = window.contentView!
        let instructions = NSTextField(wrappingLabelWithString:
            "每次開啟都建立全新視窗。先在對照視窗標題列按右鍵，等藍色焦點環出現，再左鍵點輸入框一次。\n觀察是否重播動畫，回到這裡記錄結果。B 的右鍵可直接點上方輸入框。")
        instructions.frame = NSRect(x: 20, y: 175, width: 720, height: 55)
        content.addSubview(instructions)
        popup.addItems(withTitles: FocusScene.allCases.map(\.label))
        popup.selectItem(at: FocusScene.current.rawValue)
        popup.frame = NSRect(x: 20, y: 130, width: 530, height: 28)
        content.addSubview(popup)
        button("開啟全新對照視窗", action: #selector(openDemo), x: 565, y: 130, width: 175, in: content)
        button("有重播", action: #selector(recordResult(_:)), x: 20, y: 85, width: 120, tag: 1, in: content)
        button("沒有重播", action: #selector(recordResult(_:)), x: 150, y: 85, width: 120, tag: 0, in: content)
        button("結束對照", action: #selector(quit), x: 620, y: 85, width: 120, in: content)
        status.frame = NSRect(x: 20, y: 15, width: 720, height: 55)
        content.addSubview(status)
        controls = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func button(_ title: String, action: Selector, x: CGFloat, y: CGFloat,
                        width: CGFloat, tag: Int = 0, in content: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = NSRect(x: x, y: y, width: width, height: 30)
        button.tag = tag
        content.addSubview(button)
    }

    private func nativeField() -> NSTextField {
        let field = NSTextField(string: "/Users/Test/Documents/Folder")
        field.lineBreakMode = .byTruncatingHead
        field.isAutomaticTextCompletionEnabled = false
        if #available(macOS 26.0, *) { field.controlSize = .extraLarge } else { field.controlSize = .large }
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        return field
    }

    @objc private func openDemo() {
        guard let selected = FocusScene(rawValue: popup.indexOfSelectedItem) else { return }
        demo?.onOpenPath = nil
        demo?.onTrace = nil
        demo?.close()
        field = nil
        pathToolbar = nil
        initialDelegate = nil
        scene = selected
        instance = UUID()
        let window = FocusDemoWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 320),
                                     styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = scene.label
        window.toolbarStyle = .unified
        let content = window.contentView!
        let note = NSTextField(wrappingLabelWithString:
            "\(scene.label)\n\n請在上方標題列按右鍵開始，等藍環出現，再左鍵點輸入框一次。\n測完回到控制視窗，按「有重播」或「沒有重播」。")
        note.frame = NSRect(x: 24, y: 95, width: 950, height: 90)
        note.autoresizingMask = [.width]
        content.addSubview(note)
        let sink = NSTableView(frame: NSRect(x: 24, y: 16, width: 950, height: 50))
        sink.addTableColumn(NSTableColumn(identifier: .init("focus-sink")))
        content.addSubview(sink)
        window.initialFirstResponder = sink
        demo = window
        window.onTrace = { [weak self] event in self?.trace(event) }
        window.onOpenPath = { [weak self] in self?.openPath() }
        if scene == .content {
            let field = nativeField()
            field.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                field.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            ])
            self.field = field
        } else if scene == .existingToolbar {
            let field = nativeField()
            self.field = field
            pathToolbar = FileManagerPathToolbar(window: window, field: field)
            pathToolbar?.install()
        } else {
            let delegate = InitialToolbarDelegate()
            initialDelegate = delegate
            let toolbar = NSToolbar(identifier: "FocusComparisonInitialToolbar")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        trace("window.created")
        if scene == .warmEditor {
            _ = window.fieldEditor(true, for: nil)
            trace("editor.prewarmed")
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(sink)
        trace("window.shown")
        status.stringValue = "目前：\(scene.label)\n請先右鍵，再左鍵點輸入框；每次要重測請重新開啟全新視窗。"
    }

    private func openPath() {
        guard let window = demo, !window.opened else { return }
        window.opened = true
        if field == nil {
            let field: NSTextField = scene == .nativeInsets
                ? nativeField() : FileManagerTitlePathField(path: "/Users/Test/Documents/Folder")
            if let field = field as? FileManagerTitlePathField {
                field.onFinish = { [weak self] in self?.trace("field.finished") }
            }
            self.field = field
            trace("field.created")
            pathToolbar = FileManagerPathToolbar(window: window, field: field)
            pathToolbar?.install()
            (field as? FileManagerTitlePathField)?.install()
            trace("toolbar.installed")
        }
        if scene == .nextTurn {
            trace("focus.queued")
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.demo === window else { return }
                focus()
            }
        } else {
            focus()
        }
    }

    private func focus() {
        guard let field else { return }
        trace("focus.before")
        if let field = field as? FileManagerTitlePathField { field.beginPathEditing() } else { field.selectText(nil) }
        trace("focus.after")
        DispatchQueue.main.async { [weak self] in self?.trace("focus.next-turn") }
    }

    private func trace(_ event: String) {
        func identity(_ object: AnyObject?) -> String {
            guard let object else { return "nil" }
            return "\(type(of: object)) \(ObjectIdentifier(object))"
        }
        let editor = field?.currentEditor() as? NSTextView
        var data: [String: Any] = ["event": event, "scene": scene.rawValue, "sceneLabel": scene.label,
            "instance": instance.uuidString, "windowNumber": demo?.windowNumber ?? -1,
            "keyWindow": demo?.isKeyWindow ?? false, "field": identity(field), "editor": identity(editor),
            "cachedEditor": identity(demo?.fieldEditor(false, for: nil)),
            "firstResponder": identity(demo?.firstResponder),
            "editorIsFirstResponder": editor != nil && demo?.firstResponder === editor,
            "bezeled": field?.isBezeled ?? false, "bordered": field?.isBordered ?? false,
            "showsFirstResponder": field?.cell?.showsFirstResponder ?? false,
            "highlighted": field?.cell?.isHighlighted ?? false,
            "frame": field.map { NSStringFromRect($0.frame) } ?? "nil"]
        if let editor {
            data["editorFrame"] = NSStringFromRect(editor.frame)
            data["editorInset"] = NSStringFromSize(editor.textContainerInset)
            data["selection"] = NSStringFromRange(editor.selectedRange())
        }
        log?.record(data)
    }

    @objc private func recordResult(_ sender: NSButton) {
        guard demo != nil else { return }
        trace("manual.result.\(sender.tag == 1 ? "replayed" : "not-replayed")")
        status.stringValue = "已記錄：\(scene.label) → \(sender.tag == 1 ? "有重播" : "沒有重播")\n日誌：桌面／ShichiZip-Focus-Comparison"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    func applicationWillTerminate(_: Notification) { trace("application.quit") }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
private struct FocusComparisonMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = FocusComparisonController()
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}
