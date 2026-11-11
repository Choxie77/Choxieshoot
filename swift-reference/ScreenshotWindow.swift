import Cocoa

/// Full-screen, dimmed overlay used to drag-select the capture region.
class ScreenshotWindow: NSWindow {

    var onAreaSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    private var selectionView: SelectionView!

    init() {
        // Cover the union of every screen so multi-display capture works.
        let unionFrame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let frame = unionFrame.isEmpty
            ? (NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080))
            : unionFrame

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false

        selectionView = SelectionView(frame: NSRect(origin: .zero, size: frame.size))
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onComplete = { [weak self] viewRect in
            guard let self = self else { return }
            // Convert from view coordinates to screen coordinates.
            let inWindow = self.selectionView.convert(viewRect, to: nil)
            let screenRect = self.convertToScreen(inWindow)
            // Let the overlay disappear before the actual capture happens.
            self.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.onAreaSelected?(screenRect)
                self.close()
            }
        }
        selectionView.onCancel = { [weak self] in
            self?.onCancelled?()
            self?.close()
        }
        self.contentView?.addSubview(selectionView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            selectionView.onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        selectionView.onCancel?()
    }
}

/// Draws the dimmed background, the live selection rectangle, corner handles,
/// a dimension badge and a crosshair that follows the cursor.
class SelectionView: NSView {

    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var selectionRect: CGRect = .zero
    private var mousePoint: CGPoint?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        selectionRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionRect = RectangleTool.normalizedRect(from: start, to: point)
        mousePoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        let rect = selectionRect
        startPoint = nil
        needsDisplay = true

        if rect.width >= 8 && rect.height >= 8 {
            onComplete?(rect)
        } else {
            onCancel?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mousePoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim everything outside the selection.
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fill(bounds)

        if selectionRect.width > 0 && selectionRect.height > 0 {
            // Punch a hole so the desktop shows through clearly.
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.setBlendMode(.normal)

            // Dashed border
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(selectionRect.insetBy(dx: 0.75, dy: 0.75))
            context.setLineDash(phase: 0, lengths: [])

            // Corner handles
            drawCornerHandles(context: context, rect: selectionRect)

            // Dimension badge
            drawDimensionsLabel(context: context, rect: selectionRect)
        }

        // Crosshair at the cursor.
        if let mousePoint = mousePoint {
            drawCrosshair(context: context, at: mousePoint)
        }
    }

    private func drawCornerHandles(context: CGContext, rect: CGRect) {
        let handleSize: CGFloat = 8
        let corners = [
            CGPoint(x: rect.minX - handleSize / 2, y: rect.minY - handleSize / 2),
            CGPoint(x: rect.maxX - handleSize / 2, y: rect.minY - handleSize / 2),
            CGPoint(x: rect.minX - handleSize / 2, y: rect.maxY - handleSize / 2),
            CGPoint(x: rect.maxX - handleSize / 2, y: rect.maxY - handleSize / 2)
        ]
        context.setFillColor(NSColor.white.cgColor)
        for corner in corners {
            context.fill(CGRect(origin: corner, size: CGSize(width: handleSize, height: handleSize)))
        }
    }

    private func drawDimensionsLabel(context: CGContext, rect: CGRect) {
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -3.0
        ]
        let attributedString = NSAttributedString(string: label, attributes: attributes)
        let size = attributedString.size()
        let x = min(max(rect.midX - size.width / 2, 4), bounds.width - size.width - 4)
        let y = min(rect.maxY + 8, bounds.height - size.height - 4)
        attributedString.draw(at: CGPoint(x: x, y: y))
    }

    private func drawCrosshair(context: CGContext, at point: CGPoint) {
        let length: CGFloat = 18
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.move(to: CGPoint(x: point.x - length, y: point.y))
        context.addLine(to: CGPoint(x: point.x + length, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - length))
        context.addLine(to: CGPoint(x: point.x, y: point.y + length))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }
}