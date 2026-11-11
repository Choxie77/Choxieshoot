import Cocoa

protocol ToolbarDelegate: AnyObject {
    func toolSelected(_ tool: DrawingToolType)
    func colorSelected(_ color: NSColor)
    func lineWidthChanged(_ width: CGFloat)
    func undoRequested()
    func saveRequested()
    func copyRequested()
    func shareRequested()
    func closeRequested()
}

/// Lightshot-style editing bar: drawing tools, colour, stroke width and
/// save/copy/share/close actions in one compact row.
class ToolbarView: NSView {

    weak var delegate: ToolbarDelegate?

    private var toolButtons: [NSButton] = []
    private var colorWell: NSColorWell!
    private var lineWidthSlider: NSSlider!
    private var lineWidthLabel: NSTextField!
    private var undoButton: NSButton!

    private let toolTypes: [DrawingToolType] = [
        .pencil, .line, .arrow, .rectangle, .ellipse, .marker, .text, .colorPicker, .eraser
    ]

    private let predefinedColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black, .white
    ]

    var currentTool: DrawingToolType = .pencil {
        didSet { updateToolButtons() }
    }

    var currentColor: NSColor = .systemRed {
        didSet {
            colorWell?.color = currentColor
            updateColorSwatches()
        }
    }

    var currentLineWidth: CGFloat = 3.0 {
        didSet {
            lineWidthSlider?.doubleValue = Double(currentLineWidth)
            lineWidthLabel?.stringValue = "\(Int(currentLineWidth))px"
        }
    }

    var canUndo: Bool = false {
        didSet { undoButton?.isEnabled = canUndo }
    }

    // Kept so we can refresh swatch borders.
    private var swatchButtons: [NSButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let toolsStack = NSStackView()
        toolsStack.orientation = .horizontal
        toolsStack.spacing = 2
        toolsStack.alignment = .centerY
        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolsStack)

        for toolType in toolTypes {
            let button = makeToolButton(for: toolType)
            toolButtons.append(button)
            toolsStack.addArrangedSubview(button)
        }

        // Colour section
        let colorLabel = NSTextField(labelWithString: "Color")
        colorLabel.font = .systemFont(ofSize: 10)
        colorLabel.textColor = .secondaryLabelColor
        colorLabel.setContentHuggingPriority(.required, for: .horizontal)

        colorWell = NSColorWell()
        colorWell.color = currentColor
        colorWell.isBordered = true
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 26).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let swatchStack = NSStackView()
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 2
        swatchStack.alignment = .centerY
        for (index, color) in predefinedColors.enumerated() {
            let swatch = NSButton()
            swatch.bezelStyle = .inline
            swatch.isBordered = false
            swatch.wantsLayer = true
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 3
            swatch.tag = index
            swatch.target = self
            swatch.action = #selector(swatchClicked(_:))
            swatch.toolTip = "Colour \(index + 1)"
            swatch.widthAnchor.constraint(equalToConstant: 14).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 14).isActive = true
            swatchButtons.append(swatch)
            swatchStack.addArrangedSubview(swatch)
        }

        let colorStack = NSStackView(views: [colorLabel, colorWell, swatchStack])
        colorStack.orientation = .horizontal
        colorStack.spacing = 6
        colorStack.alignment = .centerY
        colorStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(colorStack)

        // Stroke width section
        lineWidthLabel = NSTextField(labelWithString: "\(Int(currentLineWidth))px")
        lineWidthLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        lineWidthLabel.textColor = .secondaryLabelColor
        lineWidthLabel.alignment = .right
        lineWidthLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true

        lineWidthSlider = NSSlider()
        lineWidthSlider.minValue = 1
        lineWidthSlider.maxValue = 20
        lineWidthSlider.doubleValue = Double(currentLineWidth)
        lineWidthSlider.target = self
        lineWidthSlider.action = #selector(lineWidthChanged(_:))
        lineWidthSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true

        let widthStack = NSStackView(views: [lineWidthLabel, lineWidthSlider])
        widthStack.orientation = .horizontal
        widthStack.spacing = 4
        widthStack.alignment = .centerY
        widthStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(widthStack)

        // Actions
        undoButton = makeActionButton(imageName: "arrow.uturn.backward", tooltip: "Undo (⌘Z)", action: #selector(undoClicked))
        undoButton.isEnabled = false
        let saveButton = makeActionButton(imageName: "square.and.arrow.down", tooltip: "Save (⌘S)", action: #selector(saveClicked))
        let copyButton = makeActionButton(imageName: "doc.on.doc", tooltip: "Copy (⌘C)", action: #selector(copyClicked))
        let shareButton = makeActionButton(imageName: "square.and.arrow.up", tooltip: "Share", action: #selector(shareClicked))
        let closeButton = makeActionButton(imageName: "xmark", tooltip: "Close (Esc)", action: #selector(closeClicked))
        closeButton.contentTintColor = .systemRed

        let actionsStack = NSStackView(views: [
            undoButton, makeDivider(), saveButton, copyButton, shareButton, makeDivider(), closeButton
        ])
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 6
        actionsStack.alignment = .centerY
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsStack)

        NSLayoutConstraint.activate([
            toolsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            toolsStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            colorStack.leadingAnchor.constraint(equalTo: toolsStack.trailingAnchor, constant: 12),
            colorStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            widthStack.leadingAnchor.constraint(equalTo: colorStack.trailingAnchor, constant: 12),
            widthStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsStack.leadingAnchor.constraint(greaterThanOrEqualTo: widthStack.trailingAnchor, constant: 12),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateToolButtons()
        updateColorSwatches()
    }

    private func makeToolButton(for toolType: DrawingToolType) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.toggle)
        button.image = NSImage(systemSymbolName: toolType.iconName, accessibilityDescription: toolType.displayName)
        button.image?.isTemplate = true
        button.contentTintColor = .labelColor
        button.toolTip = toolType.displayName
        button.tag = toolType.rawValue
        button.target = self
        button.action = #selector(toolButtonClicked(_:))
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func makeActionButton(imageName: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: tooltip)
        button.image?.isTemplate = true
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return divider
    }

    private func updateToolButtons() {
        for button in toolButtons {
            button.state = (button.tag == currentTool.rawValue) ? .on : .off
        }
    }

    private func updateColorSwatches() {
        for (index, swatch) in swatchButtons.enumerated() {
            guard index < predefinedColors.count else { continue }
            let isSelected = predefinedColors[index] == currentColor
            swatch.layer?.borderWidth = isSelected ? 2 : 1
            swatch.layer?.borderColor = (isSelected ? NSColor.labelColor : NSColor.separatorColor).cgColor
        }
    }

    // MARK: - Actions

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard let toolType = DrawingToolType(rawValue: sender.tag) else { return }
        currentTool = toolType
        delegate?.toolSelected(toolType)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        currentColor = sender.color
        delegate?.colorSelected(sender.color)
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        guard sender.tag < predefinedColors.count else { return }
        let color = predefinedColors[sender.tag]
        currentColor = color
        delegate?.colorSelected(color)
    }

    @objc private func lineWidthChanged(_ sender: NSSlider) {
        currentLineWidth = CGFloat(sender.doubleValue)
        delegate?.lineWidthChanged(currentLineWidth)
    }

    @objc private func undoClicked() {
        delegate?.undoRequested()
    }

    @objc private func saveClicked() {
        delegate?.saveRequested()
    }

    @objc private func copyClicked() {
        delegate?.copyRequested()
    }

    @objc private func shareClicked() {
        delegate?.shareRequested()
    }

    @objc private func closeClicked() {
        delegate?.closeRequested()
    }
}