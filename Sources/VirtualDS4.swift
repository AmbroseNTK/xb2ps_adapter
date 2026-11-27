import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Tay cầm DualShock 4 ảo, tạo bằng IOHIDUserDevice.
/// Cần entitlement `com.apple.developer.hid.virtual.device`.
final class VirtualDS4 {
    /// Gọi khi host (PS Remote Play) gửi lệnh rung: (motor mạnh, motor nhẹ) trong 0...1.
    var onRumble: ((Float, Float) -> Void)?

    private let device: IOHIDUserDevice
    private let queue = DispatchQueue(label: "xb2ps.virtual-ds4", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var state = DS4State()
    private var counter: UInt8 = 0
    private var timestamp: UInt16 = 0

    /// Tần suất gửi report (DS4 thật qua USB là 250 Hz).
    private let intervalMs = 4

    init?() {
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(DS4.reportDescriptor),
            kIOHIDVendorIDKey: DS4.vendorID,
            kIOHIDProductIDKey: DS4.productID,
            kIOHIDVersionNumberKey: 0x0100,
            kIOHIDManufacturerKey: "Sony Interactive Entertainment",
            kIOHIDProductKey: "Wireless Controller",
            kIOHIDTransportKey: "USB",
            kIOHIDSerialNumberKey: DS4.deviceMAC.reversed().map { String(format: "%02X", $0) }.joined(),
            kIOHIDCountryCodeKey: 0,
            kIOHIDMaxInputReportSizeKey: DS4.inputReportSize,
            kIOHIDMaxOutputReportSizeKey: 32,
            kIOHIDMaxFeatureReportSizeKey: 64,
        ]
        guard let dev = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault, properties as CFDictionary, 0)
        else { return nil }
        device = dev

        IOHIDUserDeviceRegisterGetReportBlock(dev) { type, reportID, report, length in
            guard type == kIOHIDReportTypeFeature else { return kIOReturnUnsupported }
            let capacity = length.pointee
            var bytes = DS4.featureReport(id: reportID) ?? [UInt8(truncatingIfNeeded: reportID)]
            if bytes.count < capacity, DS4.featureReport(id: reportID) == nil {
                bytes += [UInt8](repeating: 0, count: capacity - bytes.count)
            }
            let n = min(bytes.count, capacity)
            for i in 0..<n { report[i] = bytes[i] }
            length.pointee = n
            return kIOReturnSuccess
        }

        IOHIDUserDeviceRegisterSetReportBlock(dev) { [weak self] type, reportID, report, length in
            // Output report 0x05: [1] cờ, [4] motor nhẹ (phải), [5] motor mạnh (trái), [6...8] RGB.
            if type == kIOHIDReportTypeOutput, reportID == 0x05, length >= 6 {
                let weak = Float(report[4]) / 255, strong = Float(report[5]) / 255
                self?.onRumble?(strong, weak)
            }
            return kIOReturnSuccess
        }

        // macOS ép Transport = "Virtual" lúc tạo; PS Remote Play chỉ nhận "USB"/"Bluetooth".
        IOHIDUserDeviceSetProperty(dev, kIOHIDTransportKey as CFString, "USB" as CFString)
        IOHIDUserDeviceSetProperty(dev, kIOHIDLocationIDKey as CFString, 0x1420_0000 as CFNumber)

        IOHIDUserDeviceSetDispatchQueue(dev, queue)
        IOHIDUserDeviceActivate(dev)

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(intervalMs), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.sendReport() }
        t.resume()
        timer = t
    }

    deinit {
        timer?.cancel()
        IOHIDUserDeviceCancel(device)
    }

    func update(_ newState: DS4State) {
        queue.async { self.state = newState }
    }

    private func sendReport() {
        counter &+= 1
        timestamp &+= UInt16(intervalMs * 188)  // đơn vị 5,33 µs, tức khoảng 188 đơn vị mỗi ms
        let report = DS4.inputReport(state, counter: counter, timestamp: timestamp)
        _ = IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(), report, report.count)
    }
}
