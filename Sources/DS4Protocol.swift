import Foundation

/// Trạng thái tay cầm theo cách DualShock 4 hiểu.
struct DS4State: Equatable {
    struct Buttons: OptionSet {
        let rawValue: UInt32
        static let square = Buttons(rawValue: 1 << 0)
        static let cross = Buttons(rawValue: 1 << 1)
        static let circle = Buttons(rawValue: 1 << 2)
        static let triangle = Buttons(rawValue: 1 << 3)
        static let l1 = Buttons(rawValue: 1 << 4)
        static let r1 = Buttons(rawValue: 1 << 5)
        static let l2 = Buttons(rawValue: 1 << 6)
        static let r2 = Buttons(rawValue: 1 << 7)
        static let share = Buttons(rawValue: 1 << 8)
        static let options = Buttons(rawValue: 1 << 9)
        static let l3 = Buttons(rawValue: 1 << 10)
        static let r3 = Buttons(rawValue: 1 << 11)
        static let ps = Buttons(rawValue: 1 << 12)
        static let touchpad = Buttons(rawValue: 1 << 13)
        static let dpadUp = Buttons(rawValue: 1 << 16)
        static let dpadDown = Buttons(rawValue: 1 << 17)
        static let dpadLeft = Buttons(rawValue: 1 << 18)
        static let dpadRight = Buttons(rawValue: 1 << 19)
    }

    var buttons: Buttons = []
    /// Cần analog: 0 = trái/trên, 128 = giữa, 255 = phải/dưới.
    var leftX: UInt8 = 128
    var leftY: UInt8 = 128
    var rightX: UInt8 = 128
    var rightY: UInt8 = 128
    var l2: UInt8 = 0
    var r2: UInt8 = 0

    /// Hat switch của DS4: 0 = lên, đi theo chiều kim đồng hồ, 8 = thả.
    var hat: UInt8 {
        let u = buttons.contains(.dpadUp), d = buttons.contains(.dpadDown)
        let l = buttons.contains(.dpadLeft), r = buttons.contains(.dpadRight)
        switch (u, r, d, l) {
        case (true, false, false, false): return 0
        case (true, true, false, false): return 1
        case (false, true, false, false): return 2
        case (false, true, true, false): return 3
        case (false, false, true, false): return 4
        case (false, false, true, true): return 5
        case (false, false, false, true): return 6
        case (true, false, false, true): return 7
        default: return 8
        }
    }
}

enum DS4 {
    static let vendorID = 0x054C
    static let productID = 0x09CC  // DualShock 4 đời 2 (CUH-ZCT2)
    static let inputReportSize = 64

    /// Địa chỉ MAC giả của tay cầm (lưu theo thứ tự byte đảo như DS4 thật).
    static let deviceMAC: [UInt8] = [0x21, 0x43, 0x65, 0x87, 0xA9, 0xDC]

    /// Input report 0x01 qua USB, 64 byte tính cả report ID.
    static func inputReport(_ s: DS4State, counter: UInt8, timestamp: UInt16) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: inputReportSize)
        r[0] = 0x01
        r[1] = s.leftX
        r[2] = s.leftY
        r[3] = s.rightX
        r[4] = s.rightY

        let b = s.buttons
        var b5 = s.hat & 0x0F
        if b.contains(.square) { b5 |= 0x10 }
        if b.contains(.cross) { b5 |= 0x20 }
        if b.contains(.circle) { b5 |= 0x40 }
        if b.contains(.triangle) { b5 |= 0x80 }
        r[5] = b5

        var b6: UInt8 = 0
        if b.contains(.l1) { b6 |= 0x01 }
        if b.contains(.r1) { b6 |= 0x02 }
        if b.contains(.l2) { b6 |= 0x04 }
        if b.contains(.r2) { b6 |= 0x08 }
        if b.contains(.share) { b6 |= 0x10 }
        if b.contains(.options) { b6 |= 0x20 }
        if b.contains(.l3) { b6 |= 0x40 }
        if b.contains(.r3) { b6 |= 0x80 }
        r[6] = b6

        var b7: UInt8 = (counter & 0x3F) << 2
        if b.contains(.ps) { b7 |= 0x01 }
        if b.contains(.touchpad) { b7 |= 0x02 }
        r[7] = b7

        r[8] = s.l2
        r[9] = s.r2
        r[10] = UInt8(timestamp & 0xFF)
        r[11] = UInt8(timestamp >> 8)

        // Gyro (13...18) = 0. Gia tốc kế (19...24): tay cầm nằm yên, trọng lực trên trục Y.
        r[21] = 0x00
        r[22] = 0x20  // accelY = 8192 (1g)

        r[30] = 0x1B  // cắm cáp USB + pin đầy
        r[33] = 0  // không có gói touch mới
        r[35] = 0x80  // ngón 1 không chạm
        r[39] = 0x80  // ngón 2 không chạm
        return r
    }

    /// Trả lời các feature report mà host hay hỏi. Trả về nil nếu không biết.
    static func featureReport(id: UInt32) -> [UInt8]? {
        func le(_ v: Int16) -> [UInt8] { [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)] }
        switch id {
        case 0x02:  // Hiệu chuẩn IMU (bố cục USB)
            var r: [UInt8] = [0x02]
            r += le(0) + le(0) + le(0)  // bias gyro
            for _ in 0..<3 { r += le(8839) + le(-8839) }  // pitch/yaw/roll ±
            r += le(540) + le(540)  // tốc độ gyro ±
            for _ in 0..<3 { r += le(8192) + le(-8192) }  // gia tốc x/y/z ±
            r += [0, 0]
            return r
        case 0x12:  // MAC tay cầm + MAC host đã ghép
            return [0x12] + deviceMAC + [0x08, 0x25, 0x00] + [UInt8](repeating: 0, count: 6)
        case 0x81:
            return [0x81] + deviceMAC
        case 0xA3:  // Ngày build firmware + phiên bản
            var r = [UInt8](repeating: 0, count: 49)
            r[0] = 0xA3
            let date = Array("Sep 21 2018".utf8), time = Array("04:50:51".utf8)
            r.replaceSubrange(1..<(1 + date.count), with: date)
            r.replaceSubrange(17..<(17 + time.count), with: time)
            r.replaceSubrange(33..<49, with: [
                0x00, 0x01, 0x00, 0xB4, 0x01, 0x00, 0x00, 0x00,
                0x01, 0xA0, 0x0B, 0x20, 0x01, 0x80, 0x03, 0x00,
            ])
            return r
        default:
            return nil
        }
    }

    /// HID report descriptor của DualShock 4 (kết nối USB).
    static let reportDescriptor: [UInt8] = {
        var d: [UInt8] = [
            0x05, 0x01,  // Usage Page (Generic Desktop)
            0x09, 0x05,  // Usage (Game Pad)
            0xA1, 0x01,  // Collection (Application)
            0x85, 0x01,  //   Report ID (1)
            0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35,  //   X, Y, Z, Rz
            0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02,
            0x09, 0x39,  //   Hat switch
            0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14,
            0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
            0x65, 0x00,
            0x05, 0x09, 0x19, 0x01, 0x29, 0x0E,  //   14 nút
            0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0E, 0x81, 0x02,
            0x06, 0x00, 0xFF, 0x09, 0x20,  //   Bộ đếm 6 bit
            0x75, 0x06, 0x95, 0x01, 0x15, 0x00, 0x25, 0x7F, 0x81, 0x02,
            0x05, 0x01, 0x09, 0x33, 0x09, 0x34,  //   Rx, Ry (L2/R2 analog)
            0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
            0x06, 0x00, 0xFF, 0x09, 0x21, 0x95, 0x36, 0x81, 0x02,  //   54 byte vendor
            0x85, 0x05, 0x09, 0x22, 0x95, 0x1F, 0x91, 0x02,  //   Output report 5 (rung, đèn)
        ]
        func feature(_ id: UInt8, usage: UInt8, count: UInt8) {
            d += [0x85, id, 0x09, usage, 0x95, count, 0xB1, 0x02]
        }
        feature(0x04, usage: 0x23, count: 0x24)
        feature(0x02, usage: 0x24, count: 0x24)
        feature(0x08, usage: 0x25, count: 0x03)
        feature(0x10, usage: 0x26, count: 0x04)
        feature(0x11, usage: 0x27, count: 0x02)
        d += [0x06, 0x02, 0xFF]
        feature(0x12, usage: 0x21, count: 0x0F)
        feature(0x13, usage: 0x22, count: 0x16)
        d += [0x06, 0x05, 0xFF]
        feature(0x14, usage: 0x20, count: 0x10)
        feature(0x15, usage: 0x21, count: 0x2C)
        d += [0x06, 0x80, 0xFF]
        feature(0x80, usage: 0x20, count: 0x06)
        feature(0x81, usage: 0x21, count: 0x06)
        feature(0x82, usage: 0x22, count: 0x05)
        feature(0x83, usage: 0x23, count: 0x01)
        feature(0x84, usage: 0x24, count: 0x04)
        feature(0x85, usage: 0x25, count: 0x06)
        feature(0x86, usage: 0x26, count: 0x06)
        feature(0x87, usage: 0x27, count: 0x23)
        feature(0x88, usage: 0x28, count: 0x22)
        feature(0x89, usage: 0x29, count: 0x02)
        feature(0x90, usage: 0x30, count: 0x05)
        feature(0x91, usage: 0x31, count: 0x03)
        feature(0x92, usage: 0x32, count: 0x03)
        feature(0x93, usage: 0x33, count: 0x0C)
        feature(0xA0, usage: 0x40, count: 0x06)
        feature(0xA1, usage: 0x41, count: 0x01)
        feature(0xA2, usage: 0x42, count: 0x01)
        feature(0xA3, usage: 0x43, count: 0x30)
        feature(0xA4, usage: 0x44, count: 0x0D)
        feature(0xA5, usage: 0x45, count: 0x15)
        feature(0xA6, usage: 0x46, count: 0x15)
        feature(0xF0, usage: 0x47, count: 0x3F)
        feature(0xF1, usage: 0x48, count: 0x3F)
        feature(0xF2, usage: 0x49, count: 0x0F)
        feature(0xA7, usage: 0x4A, count: 0x01)
        feature(0xA8, usage: 0x4B, count: 0x01)
        feature(0xA9, usage: 0x4C, count: 0x08)
        feature(0xAA, usage: 0x4E, count: 0x01)
        feature(0xAB, usage: 0x4F, count: 0x39)
        feature(0xAC, usage: 0x50, count: 0x39)
        feature(0xAD, usage: 0x51, count: 0x0B)
        feature(0xAE, usage: 0x52, count: 0x01)
        feature(0xAF, usage: 0x53, count: 0x02)
        feature(0xB0, usage: 0x54, count: 0x3F)
        d += [0xC0]
        return d
    }()
}
