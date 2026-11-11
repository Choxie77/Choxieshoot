import Cocoa

class DrawingCanvasView: NSView {

    var currentTool: DrawingToolType = .pencil
    var currentColor: NSColor = .red
    var currentLineWidth: CGFloat = 2.0

    var backgroundImage: NSImage?

    /// Called whenever the drawing stack changes so the owner can refresh the undo state.
    var onDrawingsChanged: (() -> Void)?
    /// Called when the eyedropper picks a colour.
    var onColorPicked: ((NSColor) -> Void)?

    private var drawings: [Drawing] = []
    private var undoStack: [[Drawing]] = []
    private var currentToolInstance: DrawingTool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTool()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTool()
    }

    private func setupTool() {
        currentToolInstance = createTool(for: currentTool)
    }

    func setTool(_ tool: DrawingToolType) {
        currentTool = tool
        currentToolInstance = createTool(for: tool)
        window?.makeFirstResponder(self)
    }

    private func createTool(for type: DrawingToolType) -> DrawingTool {
        switch type {
        case .pencil: return PencilTool()
        case .line: return LineTool()
        case .arrow: return ArrowTool()
        case .rectangle: return RectangleTool()
        case .ellipse: return EllipseTool()
        case .marker: return MarkerTool()
        case .text: return TextTool()
        case .colorPicker: return ColorPickerTool()
        case .eraser: return EraserTool()
        }
    }

    func addDrawing(_ drawing: Drawing) {
        saveStateForUndo()
        drawings.append(drawing)
        onDrawingsChanged?()
    }

    func undo() {
        guard !drawings.isEmpty else { return }
        saveStateForUndo()
        drawings.removeLast()
        onDrawingsChanged?()
        needsDisplay = true
    }

    func canUndo() -> Bool {
        return !drawings.isEmpty
    }

    private func saveStateForUndo() {
        undoStack.append(drawings)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Captured screenshot as the canvas background.
        if let image = backgroundImage {
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for drawing in drawings {
            drawDrawing(drawing, in: context)
        }

        // Live preview of the tool currently being dragged.
        currentToolInstance?.draw(in: context, canvasView: self)
    }

    private func drawDrawing(_ drawing: Drawing, in context: CGContext) {
        context.setStrokeColor(drawing.color.cgColor)
        context.setFillColor(drawing.color.cgColor)
        context.setLineWidth(drawing.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch drawing.toolType {
        case .pencil, .marker, .line:
            context.addPath(drawing.path.cgPathRepresentation)
            context.strokePath()

        case .arrow:
            context.addPath(drawing.path.cgPathRepresentation)
            context.drawPath(using: .fillStroke)

        case .rectangle, .ellipse:
            if drawing.isFilled {
                context.addPath(drawing.path.cgPathRepresentation)
                context.fillPath()
            } else {
                context.addPath(drawing.path.cgPathRepresentation)
                context.strokePath()
            }

        case .text:
            if let text = drawing.text, let position = drawing.textPosition {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: drawing.color
                ]
                let attributedString = NSAttributedString(string: text, attributes: attributes)
                attributedString.draw(at: position)
            }

        default:
            context.addPath(drawing.path.cgPathRepresentation)
            context.strokePath()
        }
    }

    /// Render the screenshot plus every annotation into a new image (used for save/copy/share).
    func renderCompositeImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let bg = backgroundImage {
            bg.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
        }
        if let context = NSGraphicsContext.current?.cgContext {
            for drawing in drawings {
                drawDrawing(drawing, in: context)
            }
        }
        image.unlockFocus()
        return image
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        if currentTool == .colorPicker {
            pickColor(at: location)
        } else if currentTool == .eraser {
            eraseAt(location)
        } else {
            currentToolInstance?.mouseDown(at: location, in: self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if currentTool == .eraser {
            eraseAt(location)
        } else {
            currentToolInstance?.mouseDragged(to: location, in: self)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        currentToolInstance?.mouseUp(at: location, in: self)
    }

    // MARK: - Eyedropper

    private func pickColor(at point: CGPoint) {
        guard let color = sampleColor(at: point) else { return }
        currentColor = color
        onColorPicked?(color)
    }

    private func sampleColor(at point: CGPoint) -> NSColor? {
        guard let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let scaleX = CGFloat(cgImage.width) / max(bounds.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(bounds.height, 1)
        let px = Int(point.x * scaleX)
        // NSView is unflipped: the image's top-left corresponds to bounds.maxY.
        let py = Int((bounds.height - point.y) * scaleY)
        guard px >= 0, py >= 0, px < cgImage.width, py < cgImage.height else { return nil }

        guard let cropped = cgImage.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)) else {
            return nil
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return NSColor(
            red: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0,
            alpha: 1.0
        )
    }

    // MARK: - Eraser

    func eraseAt(_ point: CGPoint) {
        let eraseRadius: CGFloat = currentLineWidth * 2
        let eraseRect = CGRect(
            x: point.x - eraseRadius,
            y: point.y - eraseRadius,
            width: eraseRadius * 2,
            height: eraseRadius * 2
        )

        let before = drawings.count
        saveStateForUndo()
        drawings.removeAll { drawing in
            drawing.path.bounds.intersects(eraseRect)
        }
        if drawings.count != before {
            onDrawingsChanged?()
        }
        needsDisplay = true
    }
}