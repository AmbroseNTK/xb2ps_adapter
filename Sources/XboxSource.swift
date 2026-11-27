import CoreHaptics
import Foundation
import GameController

/// Theo dõi tay cầm Xbox qua GameController framework và dịch sang DS4State.
final class XboxSource {
    var onState: ((DS4State) -> Void)?
    var onControllerChange: ((String?) -> Void)?

    private(set) var controller: GCController?
    private var strongMotor: RumbleMotor?
    private var weakMotor: RumbleMotor?

    func start() {
        // Bắt buộc: PS Remote Play sẽ là app ở phía trước, ta chạy nền.
        GCController.shouldMonitorBackgroundEvents = true

        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        GCController.startWirelessControllerDiscovery {}
        refresh()
    }

    /// Chỉ nhận tay cầm Xbox — bỏ qua chính chiếc DualShock 4 ảo để không tạo vòng lặp.
    private static func isXbox(_ c: GCController) -> Bool {
        c.extendedGamepad is GCXboxGamepad || c.productCategory.localizedCaseInsensitiveContains("xbox")
    }

    private func refresh() {
        let found = GCController.controllers().first(where: Self.isXbox)
        guard found !== controller else { return }

        controller?.extendedGamepad?.valueChangedHandler = nil
        strongMotor = nil
        weakMotor = nil
        controller = found
        onState?(DS4State())  // thả hết nút khi đổi/mất tay cầm

        if let c = found, let pad = c.extendedGamepad {
            pad.valueChangedHandler = { [weak self] pad, _ in
                self?.onState?(Self.map(pad))
            }
            strongMotor = RumbleMotor(controller: c, locality: .leftHandle)
            weakMotor = RumbleMotor(controller: c, locality: .rightHandle)
        }
        onControllerChange?(found.map { $0.vendorName ?? $0.productCategory })
    }

    func rumble(strong: Float, weak: Float) {
        DispatchQueue.main.async {
            self.strongMotor?.set(strong)
            self.weakMotor?.set(weak)
        }
    }

    // MARK: - Bảng map Xbox -> PlayStation

    static func map(_ pad: GCExtendedGamepad) -> DS4State {
        var s = DS4State()
        var b: DS4State.Buttons = []

        if pad.buttonA.isPressed { b.insert(.cross) }
        if pad.buttonB.isPressed { b.insert(.circle) }
        if pad.buttonX.isPressed { b.insert(.square) }
        if pad.buttonY.isPressed { b.insert(.triangle) }
        if pad.leftShoulder.isPressed { b.insert(.l1) }
        if pad.rightShoulder.isPressed { b.insert(.r1) }
        if pad.leftThumbstickButton?.isPressed == true { b.insert(.l3) }
        if pad.rightThumbstickButton?.isPressed == true { b.insert(.r3) }
        if pad.dpad.up.isPressed { b.insert(.dpadUp) }
        if pad.dpad.down.isPressed { b.insert(.dpadDown) }
        if pad.dpad.left.isPressed { b.insert(.dpadLeft) }
        if pad.dpad.right.isPressed { b.insert(.dpadRight) }

        // Menu (≡) -> Options, View (⧉) -> bấm touchpad, Share -> Share/Create, Xbox -> PS.
        // Giữ View + Menu cùng lúc = nút PS (phòng khi macOS chiếm nút Xbox).
        let menu = pad.buttonMenu.isPressed
        let view = pad.buttonOptions?.isPressed == true
        if menu && view {
            b.insert(.ps)
        } else {
            if menu { b.insert(.options) }
            if view { b.insert(.touchpad) }
        }
        if pad.buttonHome?.isPressed == true { b.insert(.ps) }
        if (pad as? GCXboxGamepad)?.buttonShare?.isPressed == true { b.insert(.share) }

        s.l2 = UInt8(clamping: Int((pad.leftTrigger.value * 255).rounded()))
        s.r2 = UInt8(clamping: Int((pad.rightTrigger.value * 255).rounded()))
        if s.l2 > 0 { b.insert(.l2) }
        if s.r2 > 0 { b.insert(.r2) }

        s.leftX = axis(pad.leftThumbstick.xAxis.value)
        s.leftY = axis(-pad.leftThumbstick.yAxis.value)  // DS4: 0 là lên
        s.rightX = axis(pad.rightThumbstick.xAxis.value)
        s.rightY = axis(-pad.rightThumbstick.yAxis.value)
        s.buttons = b
        return s
    }

    private static func axis(_ v: Float) -> UInt8 {
        UInt8(clamping: Int((128 + v * 127.5).rounded()))
    }
}

/// Một motor rung của tay cầm Xbox, điều khiển cường độ liên tục qua CoreHaptics.
private final class RumbleMotor {
    private let engine: CHHapticEngine
    private var player: CHHapticAdvancedPatternPlayer?
    private var running = false

    init?(controller: GCController, locality: GCHapticsLocality) {
        guard let haptics = controller.haptics,
            haptics.supportedLocalities.contains(locality),
            let engine = haptics.createEngine(withLocality: locality)
        else { return nil }
        self.engine = engine
        engine.resetHandler = { [weak self] in
            self?.player = nil
            self?.running = false
            try? self?.engine.start()
        }
        try? engine.start()
    }

    func set(_ intensity: Float) {
        do {
            if intensity <= 0.001 {
                if running {
                    try player?.stop(atTime: CHHapticTimeImmediate)
                    running = false
                }
                return
            }
            if player == nil {
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                    ],
                    relativeTime: 0, duration: 30)
                let p = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                p.loopEnabled = true
                player = p
            }
            try player?.sendParameters(
                [CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)],
                atTime: CHHapticTimeImmediate)
            if !running {
                try player?.start(atTime: CHHapticTimeImmediate)
                running = true
            }
        } catch {
            player = nil
            running = false
        }
    }
}
