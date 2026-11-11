import Cocoa

class EditingWindow: NSWindow, NSWindowDelegate, ToolbarDelegate {

    private var canvasView: DrawingCanvasView!
    private var toolbar: ToolbarView!

    var onClose: ((EditingWindow) -> Void)?

    private let toolbarHeight: CGFloat = 64
    private let gap: CGFloat = 8
    private let screenshot: NSImage

    // MARK: - Init

    init(screenRect: CGRect, screenshot: NSImage) {
        self.screenshot = screenshot

        let imageSize = screenshot.size
        // The toolbar needs a minimum width; narrow captures are centred.
        let contentSize = NSSize(
            width: max(imageSize.width, 880),
            height: imageSize.height + toolbarHeight + gap
        )
        let imageInset = (contentSize.width - imageSize.width) / 2

        // Keep the capture aligned with the area it came from and keep the
        // toolbar reachable when the selection touches the bottom of the screen.
        var origin = CGPoint(
            x: screenRect.origin.x - imageInset,
            y: screenRect.origin.y - toolbarHeight - gap
        )
        if let visible = NSScreen.screens.first(where: { $0.frame.contains(screenRect.center) ?? false })?.visibleFrame {
            origin.y = max(origin.y, visible.minY)
            origin.x = min(max(origin.x, visible.minX), visible.maxX - contentSize.width)
        }

        super.init(
            contentRect: NSRect(origin: origin, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.delegate = self

        buildContent(imageSize: imageSize, contentSize: contentSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func buildContent(imageSize: NSSize, contentSize: NSSize) {
        let imageInset = (contentSize.width - imageSize.width) / 2
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        self.contentView = container

        let imageInset = (contentSize.width - imageSize.width) / 2
        canvasView = DrawingCanvasView(frame: NSRect(
            x: imageInset,
            y: toolbarHeight + gap,
            width: imageSize.width,
            height: imageSize.height
        ))
        canvasView.backgroundImage = screenshot
        canvasView.onDrawingsChanged = { [weak self] in
            self?.toolbar.canUndo = self?.canvasView.canUndo() ?? false
        }
        canvasView.onColorPicked = { [weak self] color in
            self?.toolbar.currentColor = color
        }
        container.addSubview(canvasView)

        toolbar = ToolbarView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: toolbarHeight))
        toolbar.delegate = self
        container.addSubview(toolbar)

        window?.makeFirstResponder(canvasView)
    }

    // MARK: - Keyboard shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        if event.keyCode == 53 { // Escape
            closeWindow()
            return true
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s":
                saveImage()
                return true
            case "c":
                copyImage()
                return true
            case "z":
                undoRequested()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Actions

    private func closeWindow() {
        close()
    }

    private func saveImage() {
        let image = canvasView.renderCompositeImage()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Choxieshoot \(Self.timestamp()).png"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard
                let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                self?.presentErrorAlert("Could not encode the image as PNG.")
                return
            }
            do {
                try png.write(to: url)
            } catch {
                self?.presentErrorAlert("Could not save the image: \(error.localizedDescription)")
            }
        }
    }

    private func copyImage() {
        let image = canvasView.renderCompositeImage()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func shareImage() {
        let image = canvasView.renderCompositeImage()
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: toolbar.bounds, of: toolbar, preferredEdge: .minY)
    }

    private func presentErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Choxieshoot"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self, completionHandler: nil)
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }

    // MARK: - ToolbarDelegate

    func toolSelected(_ tool: DrawingToolType) {
        canvasView.setTool(tool)
    }

    func colorSelected(_ color: NSColor) {
        canvasView.currentColor = color
    }

    func lineWidthChanged(_ width: CGFloat) {
        canvasView.currentLineWidth = width
    }

    func undoRequested() {
        canvasView.undo()
        toolbar.canUndo = canvasView.canUndo()
    }

    func saveRequested() {
        saveImage()
    }

    func copyRequested() {
        copyImage()
    }

    func shareRequested() {
        shareImage()
    }

    func closeRequested() {
        closeWindow()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}