import Foundation
import CoreBluetooth

enum GATT {
    static let heartRate = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let cyclingPower = CBUUID(string: "1818")
    static let cyclingPowerMeasurement = CBUUID(string: "2A63")
    static let csc = CBUUID(string: "1816")
    static let cscMeasurement = CBUUID(string: "2A5B")
    static let cscFeature = CBUUID(string: "2A5C")
    static let ftms = CBUUID(string: "1826")
    static let ftmsFeature = CBUUID(string: "2ACC")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let ftmsControlPoint = CBUUID(string: "2AD9")
    static let ftmsStatus = CBUUID(string: "2ADA")
    static let battery = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfo = CBUUID(string: "180A")
    static let firmwareRevision = CBUUID(string: "2A26")
    static let serialNumber = CBUUID(string: "2A25")
}

struct HeartRateSample {
    var bpm: Int
    var contact: Bool?
    var rrIntervals: [Double]

    static func parse(_ d: Data) -> HeartRateSample? {
        guard let flags = d.u8(0) else { return nil }
        var i = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard let v = d.u16(i) else { return nil }
            bpm = Int(v); i += 2
        } else {
            guard let v = d.u8(i) else { return nil }
            bpm = Int(v); i += 1
        }
        var contact: Bool?
        if flags & 0x04 != 0 { contact = flags & 0x02 != 0 }
        if flags & 0x08 != 0 { i += 2 }
        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while let v = d.u16(i) { rr.append(Double(v) / 1024.0); i += 2 }
        }
        return HeartRateSample(bpm: bpm, contact: contact, rrIntervals: rr)
    }
}

struct CrankTracker {
    private var lastRevs: UInt16?
    private var lastTime: UInt16?
    private var lastUpdate = Date.distantPast
    private(set) var cadence: Double = 0

    mutating func update(revs: UInt16, time1024: UInt16, now: Date = Date()) -> Double? {
        defer { lastRevs = revs; lastTime = time1024 }
        guard let lr = lastRevs, let lt = lastTime else { return nil }
        let dRevs = Int(revs &- lr)
        let dTicks = Int(time1024 &- lt)
        if dRevs == 0 || dTicks == 0 {
            if now.timeIntervalSince(lastUpdate) > 3 { cadence = 0; return 0 }
            return nil
        }
        lastUpdate = now
        cadence = Double(dRevs) / (Double(dTicks) / 1024.0) * 60.0
        if cadence > 250 { cadence = 0 }
        return cadence
    }

    mutating func idleCheck(now: Date = Date()) -> Bool {
        if cadence > 0, now.timeIntervalSince(lastUpdate) > 3 { cadence = 0; return true }
        return false
    }
}

struct WheelTracker {
    private var lastRevs: UInt32?
    private var lastTime: UInt16?
    private(set) var speedKmh: Double = 0
    var circumferenceM: Double = 2.105

    mutating func update(revs: UInt32, time: UInt16, ticksPerSecond: Double) -> Double? {
        defer { lastRevs = revs; lastTime = time }
        guard let lr = lastRevs, let lt = lastTime else { return nil }
        let dRevs = Int(revs &- lr)
        let dTicks = Int(time &- lt)
        if dRevs == 0 || dTicks == 0 { return nil }
        speedKmh = Double(dRevs) * circumferenceM / (Double(dTicks) / ticksPerSecond) * 3.6
        return speedKmh
    }
}

struct CyclingPowerSample {
    var watts: Int
    var crankRevs: UInt16?
    var crankTime: UInt16?
    var wheelRevs: UInt32?
    var wheelTime: UInt16?
    var balanceLeft: Double?

    static func parse(_ d: Data) -> CyclingPowerSample? {
        guard let flags = d.u16(0), let p = d.s16(2) else { return nil }
        var s = CyclingPowerSample(watts: Int(p))
        var i = 4
        if flags & 0x0001 != 0 {
            if let b = d.u8(i) { s.balanceLeft = Double(b) / 2.0 }
            i += 1
        }
        if flags & 0x0004 != 0 { i += 2 }
        if flags & 0x0010 != 0 {
            s.wheelRevs = d.u32(i); s.wheelTime = d.u16(i + 4); i += 6
        }
        if flags & 0x0020 != 0 {
            s.crankRevs = d.u16(i); s.crankTime = d.u16(i + 2); i += 4
        }
        return s
    }
}

struct CSCSample {
    var wheelRevs: UInt32?
    var wheelTime: UInt16?
    var crankRevs: UInt16?
    var crankTime: UInt16?

    static func parse(_ d: Data) -> CSCSample? {
        guard let flags = d.u8(0) else { return nil }
        var s = CSCSample()
        var i = 1
        if flags & 0x01 != 0 { s.wheelRevs = d.u32(i); s.wheelTime = d.u16(i + 4); i += 6 }
        if flags & 0x02 != 0 { s.crankRevs = d.u16(i); s.crankTime = d.u16(i + 2); i += 4 }
        return s
    }
}

struct IndoorBikeData {
    var speedKmh: Double?
    var cadence: Double?
    var distanceM: Int?
    var resistance: Int?
    var power: Int?
    var heartRate: Int?
    var elapsed: Int?

    static func parse(_ d: Data) -> IndoorBikeData? {
        guard let flags = d.u16(0) else { return nil }
        var r = IndoorBikeData()
        var i = 2
        if flags & 0x0001 == 0 { if let v = d.u16(i) { r.speedKmh = Double(v) / 100 }; i += 2 }
        if flags & 0x0002 != 0 { i += 2 }
        if flags & 0x0004 != 0 { if let v = d.u16(i) { r.cadence = Double(v) / 2 }; i += 2 }
        if flags & 0x0008 != 0 { i += 2 }
        if flags & 0x0010 != 0 { if let v = d.u24(i) { r.distanceM = Int(v) }; i += 3 }
        if flags & 0x0020 != 0 { if let v = d.s16(i) { r.resistance = Int(v) }; i += 2 }
        if flags & 0x0040 != 0 { if let v = d.s16(i) { r.power = Int(v) }; i += 2 }
        if flags & 0x0080 != 0 { i += 2 }
        if flags & 0x0100 != 0 { i += 5 }
        if flags & 0x0200 != 0 { if let v = d.u8(i) { r.heartRate = Int(v) }; i += 1 }
        if flags & 0x0400 != 0 { i += 1 }
        if flags & 0x0800 != 0 { if let v = d.u16(i) { r.elapsed = Int(v) }; i += 2 }
        return r
    }
}

enum FTMSControl {
    static let requestControl = Data([0x00])
    static let reset = Data([0x01])
    static func targetPower(_ w: Int) -> Data {
        let v = Int16(clamping: w)
        return Data([0x05, UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)])
    }
    static func simulation(gradePercent: Double, windMps: Double = 0, crr: Double = 0.004, cw: Double = 0.51) -> Data {
        let wind = Int16(clamping: Int((windMps * 1000).rounded()))
        let grade = Int16(clamping: Int((gradePercent * 100).rounded()))
        let crrB = UInt8(clamping: Int((crr * 10000).rounded()))
        let cwB = UInt8(clamping: Int((cw * 100).rounded()))
        return Data([0x11,
                     UInt8(truncatingIfNeeded: wind), UInt8(truncatingIfNeeded: wind >> 8),
                     UInt8(truncatingIfNeeded: grade), UInt8(truncatingIfNeeded: grade >> 8),
                     crrB, cwB])
    }
    static let start = Data([0x07])

    static func describeResponse(_ d: Data) -> String {
        guard d.count >= 3, d[d.startIndex] == 0x80 else { return "status \(d.hexString)" }
        let result: String
        switch d[d.startIndex + 2] {
        case 1: result = "success"
        case 2: result = "op not supported"
        case 3: result = "invalid parameter"
        case 4: result = "operation failed"
        case 5: result = "control not permitted"
        default: result = "result \(d[d.startIndex + 2])"
        }
        return "op 0x\(String(format: "%02X", d[d.startIndex + 1])) → \(result)"
    }
}
