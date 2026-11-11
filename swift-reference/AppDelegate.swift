import Cocoa
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static private var retainedDelegate: AppDelegate?

    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var selectionWindow: ScreenshotWindow?
    private var editingWindows: [EditingWindow] = []
    private var isSelecting = false

    // MARK: - Entry point (programmatic AppKit app, no storyboard)

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerGlobalHotkey()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Choxieshoot") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "CS"
            }
        }

        let menu = NSMenu()
        let takeItem = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "")
        takeItem.target = self
        menu.addItem(takeItem)
        menu.addItem(NSMenuItem.separator())
        let prefItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Choxieshoot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Global hotkey (⌘⇧2)

    private func registerGlobalHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x43485853) // 'CHXS'
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.handleHotkey()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func handleHotkey() {
        startAreaSelection()
    }

    @objc private func takeScreenshot() {
        startAreaSelection()
    }

    // MARK: - Capture flow

    private func startAreaSelection() {
        guard !isSelecting else { return }
        isSelecting = true

        let window = ScreenshotWindow()
        window.onAreaSelected = { [weak self] rect in
            guard let self = self else { return }
            self.isSelecting = false
            self.selectionWindow = nil
            self.captureAndEdit(rect: rect)
        }
        window.onCancelled = { [weak self] in
            self?.isSelecting = false
            self?.selectionWindow = nil
        }

        selectionWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureAndEdit(rect: CGRect) {
        guard let image = ScreenshotCapture.capture(rect: rect) else {
            NSSound.beep()
            return
        }

        let editingWindow = EditingWindow(screenRect: rect, screenshot: image)
        editingWindow.onClose = { [weak self] window in
            self?.editingWindows.removeAll { $0 === window }
        }
        editingWindows.append(editingWindow)
        editingWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showPreferences() {
        let alert = NSAlert()
        alert.messageText = "Choxieshoot"
        alert.informativeText = "Take a screenshot with ⌘⇧2 (or from the menu bar), drag to select an area, then annotate it.\n\nKeyboard shortcuts:\n⌘S — save\n⌘C — copy\n⌘Z — undo\nEsc — close"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}