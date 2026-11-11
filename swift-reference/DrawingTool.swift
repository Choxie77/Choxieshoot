import Cocoa

// MARK: - NSBezierPath → CGPath helper
// Avoids depending on the macOS 14 `NSBezierPath.cgPath` property so the
// app keeps building on older SDKs.
extension NSBezierPath {
    var cgPathRepresentation: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}

enum DrawingToolType: Int, CaseIterable {
    case pencil = 0
    case line = 1
    case arrow = 2
    case rectangle = 3
    case ellipse = 4
    case marker = 5
    case text = 6
    case colorPicker = 7
    case eraser = 8

    var iconName: String {
        switch self {
        case .pencil: return "pencil"
        case .line: return "line.diagonal"
        case .arrow: return "arrowshape.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .colorPicker: return "eyedropper"
        case .eraser: return "eraser"
        }
    }

    var displayName: String {
        switch self {
        case .pencil: return "Pencil"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .marker: return "Marker"
        case .text: return "Text"
        case .colorPicker: return "Color Picker"
        case .eraser: return "Eraser"
        }
    }
}

struct Drawing {
    let path: NSBezierPath
    let color: NSColor
    let lineWidth: CGFloat
    let toolType: DrawingToolType
    var isFilled: Bool = false
    var text: String?
    var textPosition: CGPoint?
    let id = UUID()
}

protocol DrawingTool {
    var type: DrawingToolType { get }
    func mouseDown(at point: CGPoint, in view: DrawingCanvasView)
    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView)
    func mouseUp(at point: CGPoint, in view: DrawingCanvasView)
    func draw(in context: CGContext, canvasView: DrawingCanvasView)
}

// Freehand pencil
class PencilTool: DrawingTool {
    let type: DrawingToolType = .pencil
    var currentPath: NSBezierPath?

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        currentPath = NSBezierPath()
        currentPath?.move(to: point)
        currentPath?.lineWidth = view.currentLineWidth
        currentPath?.lineCapStyle = .round
        currentPath?.lineJoinStyle = .round
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPath?.line(to: point)
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        if let path = currentPath, path.elementCount > 1 {
            let drawing = Drawing(path: path, color: view.currentColor, lineWidth: view.currentLineWidth, toolType: .pencil)
            view.addDrawing(drawing)
        }
        currentPath = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let path = currentPath else { return }
        context.setStrokeColor(canvasView.currentColor.cgColor)
        context.setLineWidth(canvasView.currentLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPathRepresentation)
        context.strokePath()
    }
}

// Straight line
class LineTool: DrawingTool {
    let type: DrawingToolType = .line
    var startPoint: CGPoint?
    var currentPoint: CGPoint?

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        startPoint = point
        currentPoint = point
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPoint = point
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        guard let start = startPoint else { return }
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: point)
        path.lineWidth = view.currentLineWidth
        path.lineCapStyle = .round

        let drawing = Drawing(path: path, color: view.currentColor, lineWidth: view.currentLineWidth, toolType: .line)
        view.addDrawing(drawing)

        startPoint = nil
        currentPoint = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let start = startPoint, let current = currentPoint else { return }
        context.setStrokeColor(canvasView.currentColor.cgColor)
        context.setLineWidth(canvasView.currentLineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: current)
        context.strokePath()
    }
}

// Arrow
class ArrowTool: DrawingTool {
    let type: DrawingToolType = .arrow
    var startPoint: CGPoint?
    var currentPoint: CGPoint?

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        startPoint = point
        currentPoint = point
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPoint = point
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        guard let start = startPoint else { return }
        let path = ArrowTool.arrowPath(from: start, to: point, lineWidth: view.currentLineWidth)
        let drawing = Drawing(path: path, color: view.currentColor, lineWidth: view.currentLineWidth, toolType: .arrow)
        view.addDrawing(drawing)

        startPoint = nil
        currentPoint = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let start = startPoint, let current = currentPoint else { return }
        let path = ArrowTool.arrowPath(from: start, to: current, lineWidth: canvasView.currentLineWidth)
        context.setStrokeColor(canvasView.currentColor.cgColor)
        context.setFillColor(canvasView.currentColor.cgColor)
        context.setLineWidth(canvasView.currentLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPathRepresentation)
        context.drawPath(using: .fillStroke)
    }

    static func arrowPath(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / length
        let uy = dy / length

        let headLength = max(14, lineWidth * 5)
        let headWidth = max(10, lineWidth * 4)
        let shaftEnd = CGPoint(x: end.x - ux * headLength * 0.7, y: end.y - uy * headLength * 0.7)

        path.move(to: start)
        path.line(to: shaftEnd)

        // Arrow head triangle
        let baseX = end.x - ux * headLength
        let baseY = end.y - uy * headLength
        let perpX = -uy
        let perpY = ux
        let left = CGPoint(x: baseX + perpX * headWidth / 2, y: baseY + perpY * headWidth / 2)
        let right = CGPoint(x: baseX - perpX * headWidth / 2, y: baseY - perpY * headWidth / 2)

        path.move(to: end)
        path.line(to: left)
        path.line(to: right)
        path.close()

        return path
    }
}

// Rectangle
class RectangleTool: DrawingTool {
    let type: DrawingToolType = .rectangle
    var startPoint: CGPoint?
    var currentPoint: CGPoint?
    var isFilled = false

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        startPoint = point
        currentPoint = point
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPoint = point
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        guard let start = startPoint else { return }
        let rect = RectangleTool.normalizedRect(from: start, to: point)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = view.currentLineWidth
        let drawing = Drawing(path: path, color: view.currentColor, lineWidth: view.currentLineWidth, toolType: .rectangle, isFilled: isFilled)
        view.addDrawing(drawing)

        startPoint = nil
        currentPoint = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let start = startPoint, let current = currentPoint else { return }
        let rect = RectangleTool.normalizedRect(from: start, to: current)
        context.setStrokeColor(canvasView.currentColor.cgColor)
        context.setLineWidth(canvasView.currentLineWidth)
        if isFilled {
            context.setFillColor(canvasView.currentColor.cgColor)
            context.fill(rect)
        } else {
            context.stroke(rect)
        }
    }

    static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

// Ellipse
class EllipseTool: DrawingTool {
    let type: DrawingToolType = .ellipse
    var startPoint: CGPoint?
    var currentPoint: CGPoint?
    var isFilled = false

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        startPoint = point
        currentPoint = point
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPoint = point
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        guard let start = startPoint else { return }
        let rect = RectangleTool.normalizedRect(from: start, to: point)
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = view.currentLineWidth
        let drawing = Drawing(path: path, color: view.currentColor, lineWidth: view.currentLineWidth, toolType: .ellipse, isFilled: isFilled)
        view.addDrawing(drawing)

        startPoint = nil
        currentPoint = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let start = startPoint, let current = currentPoint else { return }
        let rect = RectangleTool.normalizedRect(from: start, to: current)
        context.setStrokeColor(canvasView.currentColor.cgColor)
        context.setLineWidth(canvasView.currentLineWidth)
        if isFilled {
            context.setFillColor(canvasView.currentColor.cgColor)
            context.fillEllipse(in: rect)
        } else {
            context.strokeEllipse(in: rect)
        }
    }
}

// Highlighter marker
class MarkerTool: DrawingTool {
    let type: DrawingToolType = .marker
    var currentPath: NSBezierPath?

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        currentPath = NSBezierPath()
        currentPath?.move(to: point)
        currentPath?.lineWidth = view.currentLineWidth * 3
        currentPath?.lineCapStyle = .round
        currentPath?.lineJoinStyle = .round
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        currentPath?.line(to: point)
        view.needsDisplay = true
    }

    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {
        if let path = currentPath, path.elementCount > 1 {
            let markerColor = view.currentColor.withAlphaComponent(0.35)
            let drawing = Drawing(path: path, color: markerColor, lineWidth: view.currentLineWidth * 3, toolType: .marker)
            view.addDrawing(drawing)
        }
        currentPath = nil
        view.needsDisplay = true
    }

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let path = currentPath else { return }
        context.setStrokeColor(canvasView.currentColor.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(canvasView.currentLineWidth * 3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPathRepresentation)
        context.strokePath()
    }
}

// Text
class TextTool: DrawingTool {
    let type: DrawingToolType = .text
    var textPosition: CGPoint?
    var textField: NSTextField?
    private var textDelegate: TextFieldDelegate?

    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {
        textPosition = point
        createTextField(at: point, in: view)
    }

    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {}
    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {}

    func draw(in context: CGContext, canvasView: DrawingCanvasView) {}

    private func createTextField(at point: CGPoint, in view: DrawingCanvasView) {
        // Remove any existing editor first
        textField?.removeFromSuperview()

        let textField = NSTextField(frame: CGRect(x: point.x, y: point.y - 12, width: 240, height: 28))
        textField.backgroundColor = NSColor.white.withAlphaComponent(0.15)
        textField.isBordered = false
        textField.drawsBackground = true
        textField.font = .systemFont(ofSize: 16, weight: .semibold)
        textField.textColor = view.currentColor
        textField.stringValue = ""
        textField.focusRingType = .none

        let delegate = TextFieldDelegate { [weak view] text in
            guard let view = view, !text.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: view.currentColor
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let path = NSBezierPath(rect: CGRect(origin: point, size: attributedString.size()))
            let drawing = Drawing(
                path: path,
                color: view.currentColor,
                lineWidth: 0,
                toolType: .text,
                text: text,
                textPosition: point
            )
            view.addDrawing(drawing)
            view.needsDisplay = true
        }

        textField.delegate = delegate
        self.textDelegate = delegate
        self.textField = textField

        view.addSubview(textField)
        view.window?.makeFirstResponder(textField)
    }
}

class TextFieldDelegate: NSObject, NSTextFieldDelegate {
    let onCommit: (String) -> Void

    init(onCommit: @escaping (String) -> Void) {
        self.onCommit = onCommit
        super.init()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onCommit(control.stringValue)
            control.window?.makeFirstResponder(nil)
            control.removeFromSuperview()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            control.window?.makeFirstResponder(nil)
            control.removeFromSuperview()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            onCommit(textField.stringValue)
            textField.removeFromSuperview()
        }
    }
}

// Color picker (handled by the canvas view itself)
class ColorPickerTool: DrawingTool {
    let type: DrawingToolType = .colorPicker
    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {}
    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {}
    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {}
    func draw(in context: CGContext, canvasView: DrawingCanvasView) {}
}

// Eraser (handled by the canvas view itself)
class EraserTool: DrawingTool {
    let type: DrawingToolType = .eraser
    func mouseDown(at point: CGPoint, in view: DrawingCanvasView) {}
    func mouseDragged(to point: CGPoint, in view: DrawingCanvasView) {
        view.eraseAt(point)
    }
    func mouseUp(at point: CGPoint, in view: DrawingCanvasView) {}
    func draw(in context: CGContext, canvasView: DrawingCanvasView) {
        guard let window = canvasView.window else { return }
        let localPoint = canvasView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let radius = canvasView.currentLineWidth * 2
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokeEllipse(in: CGRect(x: localPoint.x - radius, y: localPoint.y - radius, width: radius * 2, height: radius * 2))
        context.setLineDash(phase: 0, lengths: [])
    }
}