import Foundation

struct ProtoWriter {
    private(set) var data = Data()

    mutating func writeVarint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    mutating func varint(_ field: Int, _ value: UInt64) {
        writeVarint(UInt64(field << 3))
        writeVarint(value)
    }

    mutating func varint(_ field: Int, _ value: Int) {
        varint(field, UInt64(max(0, value)))
    }

    mutating func sint(_ field: Int, _ value: Int32) {
        let zz = UInt32(bitPattern: (value << 1) ^ (value >> 31))
        varint(field, UInt64(zz))
    }

    mutating func bytes(_ field: Int, _ payload: Data) {
        writeVarint(UInt64(field << 3 | 2))
        writeVarint(UInt64(payload.count))
        data.append(payload)
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var w = ProtoWriter()
        build(&w)
        bytes(field, w.data)
    }
}

struct ProtoField {
    let number: Int
    let wireType: Int
    let varint: UInt64
    let bytes: Data

    var sint32: Int32 {
        let v = UInt32(truncatingIfNeeded: varint)
        return Int32(bitPattern: (v >> 1) ^ (0 &- (v & 1)))
    }
    var int: Int { Int(truncatingIfNeeded: varint) }
    var string: String { String(decoding: bytes, as: UTF8.self) }
}

enum Proto {
    static func readVarint(_ b: [UInt8], _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < b.count {
            let byte = b[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    static func decode(_ data: Data) -> [ProtoField] {
        let b = [UInt8](data)
        var i = 0
        var fields: [ProtoField] = []
        while i < b.count {
            guard let key = readVarint(b, &i) else { break }
            let number = Int(key >> 3)
            let wt = Int(key & 7)
            switch wt {
            case 0:
                guard let v = readVarint(b, &i) else { return fields }
                fields.append(ProtoField(number: number, wireType: 0, varint: v, bytes: Data()))
            case 1:
                guard i + 8 <= b.count else { return fields }
                var v: UInt64 = 0
                for k in 0..<8 { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
                i += 8
                fields.append(ProtoField(number: number, wireType: 1, varint: v, bytes: Data()))
            case 2:
                guard let len = readVarint(b, &i), i + Int(len) <= b.count else { return fields }
                let slice = Data(b[i..<(i + Int(len))])
                i += Int(len)
                fields.append(ProtoField(number: number, wireType: 2, varint: 0, bytes: slice))
            case 5:
                guard i + 4 <= b.count else { return fields }
                var v: UInt64 = 0
                for k in 0..<4 { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
                i += 4
                fields.append(ProtoField(number: number, wireType: 5, varint: v, bytes: Data()))
            default:
                return fields
            }
        }
        return fields
    }
}

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined(separator: " ") }

    init?(hex: String) {
        let clean = hex.replacingOccurrences(of: " ", with: "")
        guard clean.count % 2 == 0 else { return nil }
        var d = Data()
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            d.append(byte)
            idx = next
        }
        self = d
    }

    func u8(_ at: Int) -> UInt8? { at < count ? self[startIndex + at] : nil }
    func u16(_ at: Int) -> UInt16? {
        guard at + 1 < count else { return nil }
        return UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8
    }
    func s16(_ at: Int) -> Int16? { u16(at).map { Int16(bitPattern: $0) } }
    func u24(_ at: Int) -> UInt32? {
        guard at + 2 < count else { return nil }
        return UInt32(self[startIndex + at]) | UInt32(self[startIndex + at + 1]) << 8 | UInt32(self[startIndex + at + 2]) << 16
    }
    func u32(_ at: Int) -> UInt32? {
        guard at + 3 < count else { return nil }
        return UInt32(self[startIndex + at]) | UInt32(self[startIndex + at + 1]) << 8
            | UInt32(self[startIndex + at + 2]) << 16 | UInt32(self[startIndex + at + 3]) << 24
    }
}
