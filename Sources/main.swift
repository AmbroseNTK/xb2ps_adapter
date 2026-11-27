import AppKit

/// App menu bar: Xbox controller -> DualShock 4 ảo.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let xboxLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let virtualLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let source = XboxSource()
    private var virtual: VirtualDS4?
    private var activity: NSObjectProtocol?
    private var xboxName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(xboxLine)
        menu.addItem(virtualLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Xb2PS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Không để App Nap bóp tần suất gửi report khi app chạy nền.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical], reason: "Forwarding controller input")

        source.onState = { [weak self] state in self?.virtual?.update(state) }
        source.onControllerChange = { [weak self] name in
            self?.xboxName = name
            self?.syncVirtualDevice()
        }
        source.start()
        syncVirtualDevice()
    }

    /// DualShock 4 ảo chỉ tồn tại khi có tay cầm Xbox đang kết nối.
    private func syncVirtualDevice() {
        if xboxName != nil, virtual == nil {
            virtual = VirtualDS4()
            virtual?.onRumble = { [weak self] strong, weak in self?.source.rumble(strong: strong, weak: weak) }
            if virtual == nil {
                NSLog("Xb2PS: failed to create the virtual HID device (missing com.apple.developer.hid.virtual.device entitlement?)")
            }
        } else if xboxName == nil {
            virtual = nil
        }

        xboxLine.title = xboxName.map { "Xbox: \($0)" } ?? "Xbox: no controller connected"
        if xboxName == nil {
            virtualLine.title = "Virtual DualShock 4: waiting"
        } else if virtual != nil {
            virtualLine.title = "Virtual DualShock 4: active"
        } else {
            virtualLine.title = "Virtual DualShock 4: ERROR — app is not signed with the HID Virtual Device entitlement"
        }
        let symbol = virtual != nil ? "gamecontroller.fill" : "gamecontroller"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Xb2PS")
        NSLog("Xb2PS: %@ | %@", xboxLine.title, virtualLine.title)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
