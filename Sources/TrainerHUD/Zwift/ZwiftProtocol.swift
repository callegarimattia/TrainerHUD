import Foundation
import CoreBluetooth

enum ZwiftUUID {
    static let service = CBUUID(string: "00000001-19CA-4651-86E5-FA29DCDD09D1")
    static let serviceFC82 = CBUUID(string: "FC82")
    static let asyncChar = CBUUID(string: "00000002-19CA-4651-86E5-FA29DCDD09D1")
    static let syncRX = CBUUID(string: "00000003-19CA-4651-86E5-FA29DCDD09D1")
    static let syncTX = CBUUID(string: "00000004-19CA-4651-86E5-FA29DCDD09D1")
    static let companyID: UInt16 = 0x094A
}

enum ZwiftOpcode: UInt8 {
    case get = 0x00
    case trainerData = 0x03
    case trainerCommand = 0x04
    case playKeypad = 0x07
    case haptic = 0x12
    case idle = 0x15
    case reset = 0x18
    case battery = 0x19
    case batteryStatus = 0x1A
    case controllerNotification = 0x23
    case logData = 0x2A
    case clickKeypad = 0x37
    case getResponse = 0x3C
    case statusResponse = 0x3E
    case unknown41 = 0x41
    case rideOn = 0x52
    case lostControl = 0xFE
    case vendor = 0xFF
}

enum ZwiftDeviceType: UInt8 {
    case hub = 0x01
    case playRight = 0x02
    case playLeft = 0x03
    case rideRight = 0x07
    case rideLeft = 0x08
    case click = 0x09
    case clickV2Right = 0x0A
    case clickV2Left = 0x0B
    case playFw2 = 0x0E

    var label: String {
        switch self {
        case .hub: return "Zwift Hub"
        case .playRight: return "Zwift Play (right)"
        case .playLeft: return "Zwift Play (left)"
        case .rideRight: return "Zwift Ride (right)"
        case .rideLeft: return "Zwift Ride (left)"
        case .click: return "Zwift Click v1"
        case .clickV2Right: return "Zwift Click v2 (right)"
        case .clickV2Left: return "Zwift Click v2 (left)"
        case .playFw2: return "Zwift Play (fw 2)"
        }
    }

    var isController: Bool { self != .hub }

    static func from(manufacturerData: Data?) -> ZwiftDeviceType? {
        guard let d = manufacturerData, d.count >= 3, d.u16(0) == ZwiftUUID.companyID else { return nil }
        return ZwiftDeviceType(rawValue: d[d.startIndex + 2])
    }
}

struct RideButtons: OptionSet {
    let rawValue: UInt32
    static let left = RideButtons(rawValue: 0x0001)
    static let up = RideButtons(rawValue: 0x0002)
    static let right = RideButtons(rawValue: 0x0004)
    static let down = RideButtons(rawValue: 0x0008)
    static let a = RideButtons(rawValue: 0x0010)
    static let b = RideButtons(rawValue: 0x0020)
    static let y = RideButtons(rawValue: 0x0040)
    static let z = RideButtons(rawValue: 0x0080)
    static let shiftUpLeft = RideButtons(rawValue: 0x0100)
    static let shiftDownLeft = RideButtons(rawValue: 0x0200)
    static let powerUpLeft = RideButtons(rawValue: 0x0400)
    static let onOffLeft = RideButtons(rawValue: 0x0800)
    static let shiftUpRight = RideButtons(rawValue: 0x1000)
    static let shiftDownRight = RideButtons(rawValue: 0x2000)
    static let powerUpRight = RideButtons(rawValue: 0x4000)
    static let onOffRight = RideButtons(rawValue: 0x8000)
}

enum ControllerButton: String, CaseIterable, Codable {
    case left, up, right, down, a, b, y, z
    case shiftUpLeft, shiftDownLeft, powerUpLeft, onOffLeft
    case shiftUpRight, shiftDownRight, powerUpRight, onOffRight
    case paddleLeft, paddleRight
    case clickPlus, clickMinus

    var label: String {
        switch self {
        case .left: return "D-pad Left"
        case .up: return "D-pad Up"
        case .right: return "D-pad Right"
        case .down: return "D-pad Down"
        case .a: return "A"
        case .b: return "B"
        case .y: return "Y"
        case .z: return "Z"
        case .shiftUpLeft: return "Left − (minus)"
        case .shiftDownLeft: return "Left shift down"
        case .powerUpLeft: return "Left power-up"
        case .onOffLeft: return "Left on/off"
        case .shiftUpRight: return "Right + (plus)"
        case .shiftDownRight: return "Right shift down"
        case .powerUpRight: return "Right power-up"
        case .onOffRight: return "Right on/off"
        case .paddleLeft: return "Left paddle"
        case .paddleRight: return "Right paddle"
        case .clickPlus: return "Click +"
        case .clickMinus: return "Click −"
        }
    }

    static let rideMasks: [(RideButtons, ControllerButton)] = [
        (.left, .left), (.up, .up), (.right, .right), (.down, .down),
        (.a, .a), (.b, .b), (.y, .y), (.z, .z),
        (.shiftUpLeft, .shiftUpLeft), (.shiftDownLeft, .shiftDownLeft),
        (.powerUpLeft, .powerUpLeft), (.onOffLeft, .onOffLeft),
        (.shiftUpRight, .shiftUpRight), (.shiftDownRight, .shiftDownRight),
        (.powerUpRight, .powerUpRight), (.onOffRight, .onOffRight),
    ]
}

struct TrainerData {
    var power: Int?
    var cadence: Int?
    var speedX100: Int?
    var heartRate: Int?
}

enum ZwiftMessages {
    static let rideOn = Data([0x52, 0x69, 0x64, 0x65, 0x4F, 0x6E])
    static let rideOnTrainer = rideOn + Data([0x02, 0x01])
    static let unknown41 = Data([0x41, 0x08, 0x05])
    static let clickV2Unlock = Data([0xFF, 0x04, 0x00])
    static let reset = Data([ZwiftOpcode.reset.rawValue])
    static let getDeviceInfo = Data([0x00, 0x08, 0x00])
    static let getGearRatio = Data([0x00, 0x08, 0x88, 0x04])

    static func isRideOnResponse(_ d: Data) -> Bool { d.count >= 6 && d.prefix(6) == rideOn }

    static func gear(ratioX10000: Int, bikeKgX100: Int? = nil, riderKgX100: Int? = nil) -> Data {
        var w = ProtoWriter()
        w.message(5) { p in
            p.varint(2, ratioX10000)
            if let b = bikeKgX100 { p.varint(4, b) }
            if let r = riderKgX100 { p.varint(5, r) }
        }
        return Data([ZwiftOpcode.trainerCommand.rawValue]) + w.data
    }

    static func simulation(inclineX100: Int32, full: Bool) -> Data {
        var w = ProtoWriter()
        w.message(4) { s in
            if full { s.sint(1, 0) }
            s.sint(2, inclineX100)
            if full {
                s.varint(3, 5100)
                s.varint(4, 400)
            }
        }
        return Data([ZwiftOpcode.trainerCommand.rawValue]) + w.data
    }

    static func targetPower(_ watts: Int) -> Data {
        var w = ProtoWriter()
        w.varint(3, watts)
        return Data([ZwiftOpcode.trainerCommand.rawValue]) + w.data
    }

    static func haptic(pattern: UInt8 = 0x20) -> Data {
        Data([0x12, 0x12, 0x08, 0x0A, 0x06, 0x08, 0x02, 0x10, 0x00, 0x18, pattern])
    }

    static func parseTrainerData(_ payload: Data) -> TrainerData {
        var t = TrainerData()
        for f in Proto.decode(payload) where f.wireType == 0 {
            switch f.number {
            case 1: t.power = f.int
            case 2: t.cadence = f.int
            case 3: t.speedX100 = f.int
            case 4: t.heartRate = f.int
            default: break
            }
        }
        return t
    }

    struct ControllerState {
        var buttons: Set<ControllerButton> = []
        var analog: [Int: Int] = [:]
        var rawBitmap: UInt32 = 0xFFFFFFFF
    }

    static func parseControllerNotification(_ payload: Data) -> ControllerState {
        var st = ControllerState()
        for f in Proto.decode(payload) {
            switch (f.number, f.wireType) {
            case (1, 0):
                st.rawBitmap = UInt32(truncatingIfNeeded: f.varint)
            case (2, 2):
                for g in Proto.decode(f.bytes) where g.wireType == 2 {
                    parseAnalog(g.bytes, into: &st)
                }
            case (3, 2):
                parseAnalog(f.bytes, into: &st)
            default: break
            }
        }
        let pressed = RideButtons(rawValue: ~st.rawBitmap)
        for (mask, btn) in ControllerButton.rideMasks where pressed.contains(mask) {
            st.buttons.insert(btn)
        }
        for (id, v) in st.analog where abs(v) >= 25 {
            if id == 0 { st.buttons.insert(.paddleLeft) }
            if id == 1 { st.buttons.insert(.paddleRight) }
        }
        return st
    }

    private static func parseAnalog(_ d: Data, into st: inout ControllerState) {
        var id: Int?
        var value: Int?
        for f in Proto.decode(d) where f.wireType == 0 {
            if f.number == 1 { id = f.int }
            if f.number == 2 { value = Int(f.sint32) }
        }
        if let id, let value { st.analog[id] = value }
    }

    static func parseClickKeypad(_ payload: Data) -> Set<ControllerButton> {
        var s = Set<ControllerButton>()
        for f in Proto.decode(payload) where f.wireType == 0 {
            if f.number == 1, f.varint == 0 { s.insert(.clickPlus) }
            if f.number == 2, f.varint == 0 { s.insert(.clickMinus) }
        }
        return s
    }

    static func parsePlayKeypad(_ payload: Data) -> (buttons: Set<ControllerButton>, isLeft: Bool) {
        var isLeft = false
        var raw: [Int: UInt64] = [:]
        var analogLR = 0
        var analogUD = 0
        for f in Proto.decode(payload) where f.wireType == 0 {
            switch f.number {
            case 1: isLeft = f.varint == 1
            case 8: analogLR = Int(f.sint32)
            case 9: analogUD = Int(f.sint32)
            default: raw[f.number] = f.varint
            }
        }
        var s = Set<ControllerButton>()
        func pressed(_ n: Int) -> Bool { raw[n] == 0 }
        if isLeft {
            if pressed(2) { s.insert(.up) }
            if pressed(3) { s.insert(.left) }
            if pressed(4) { s.insert(.right) }
            if pressed(5) { s.insert(.down) }
            if pressed(6) { s.insert(.shiftUpLeft) }
            if pressed(7) { s.insert(.onOffLeft) }
            if abs(analogLR) >= 25 || abs(analogUD) >= 25 { s.insert(.paddleLeft) }
        } else {
            if pressed(2) { s.insert(.y) }
            if pressed(3) { s.insert(.z) }
            if pressed(4) { s.insert(.a) }
            if pressed(5) { s.insert(.b) }
            if pressed(6) { s.insert(.shiftUpRight) }
            if pressed(7) { s.insert(.onOffRight) }
            if abs(analogLR) >= 25 || abs(analogUD) >= 25 { s.insert(.paddleRight) }
        }
        return (s, isLeft)
    }

    static func parseBattery(_ payload: Data) -> Int? {
        for f in Proto.decode(payload) where f.wireType == 0 && f.number == 2 { return f.int }
        return nil
    }

    struct DeviceInfo {
        var name: String?
        var serial: String?
        var hardware: String?
        var firmware: String?
        var manufacturerId: Int?
        var productId: Int?
    }

    static func parseDeviceInfo(_ payload: Data) -> DeviceInfo? {
        var info = DeviceInfo()
        var found = false
        func scan(_ d: Data, depth: Int) {
            guard depth < 4 else { return }
            for f in Proto.decode(d) {
                if f.wireType == 2 {
                    if f.number == 3, let s = String(data: f.bytes, encoding: .utf8), s.allSatisfy({ $0.isASCII && !$0.isNewline }), !s.isEmpty {
                        info.name = s; found = true
                    } else if f.number == 6, let s = String(data: f.bytes, encoding: .utf8), s.allSatisfy({ $0.isASCII }) {
                        info.serial = s; found = true
                    } else if f.number == 7, let s = String(data: f.bytes, encoding: .utf8), s.allSatisfy({ $0.isASCII }) {
                        info.hardware = s; found = true
                    } else if f.number == 2, f.bytes.count == 4 {
                        info.firmware = f.bytes.map { String($0) }.joined(separator: ".")
                    } else {
                        scan(f.bytes, depth: depth + 1)
                    }
                } else if f.wireType == 0 {
                    if f.number == 9 { info.manufacturerId = f.int }
                    if f.number == 10 { info.productId = f.int }
                }
            }
        }
        scan(payload, depth: 0)
        return found ? info : nil
    }
}
