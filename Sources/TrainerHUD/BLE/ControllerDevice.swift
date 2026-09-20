import Foundation
import CoreBluetooth

final class ZwiftControllerDevice: NSObject, DeviceHandler, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let role = DeviceRole.controller
    unowned let session: Session
    private(set) var type: ZwiftDeviceType?
    let displayName: String

    private var asyncChar: CBCharacteristic?
    private var rxChar: CBCharacteristic?
    private var txChar: CBCharacteristic?
    private var subscriptions = 0
    private(set) var handshakeDone = false
    private var rideOnAttempts = 0
    private var rideOnTimer: Timer?
    private var keepAliveTimer: Timer?
    private var restartTimer: Timer?
    private(set) var lastFrameAt = Date.distantPast
    private(set) var handshakeAt: Date?
    private var pressed: Set<ControllerButton> = []
    private var lastVendor: Data?

    var id: UUID { peripheral.identifier }

    init(peripheral: CBPeripheral, type: ZwiftDeviceType?, name: String, session: Session) {
        self.peripheral = peripheral
        self.type = type
        self.displayName = name
        self.session = session
        super.init()
    }

    var shortLabel: String {
        switch type {
        case .clickV2Left: return "Click L"
        case .clickV2Right: return "Click R"
        case .click: return "Click"
        case .playLeft: return "Play L"
        case .playRight: return "Play R"
        case .playFw2: return "Play"
        case .rideLeft, .rideRight: return "Ride"
        case .hub, .none: return "Ctrl"
        }
    }

    func didConnect() {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func didDisconnect() {
        handshakeDone = false
        handshakeAt = nil
        subscriptions = 0
        rideOnAttempts = 0
        pressed.removeAll()
        rideOnTimer?.invalidate()
        keepAliveTimer?.invalidate()
        restartTimer?.invalidate()
        asyncChar = nil; rxChar = nil; txChar = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { Log.error("\(displayName) service discovery failed: \(error.localizedDescription)"); return }
        for s in peripheral.services ?? [] {
            Log.ble("\(displayName) service \(s.uuid)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            Log.ble("\(displayName) char \(c.uuid) in \(service.uuid) props=\(c.properties.rawValue)")
            switch c.uuid {
            case ZwiftUUID.asyncChar: asyncChar = c; peripheral.setNotifyValue(true, for: c)
            case ZwiftUUID.syncTX: txChar = c; peripheral.setNotifyValue(true, for: c)
            case ZwiftUUID.syncRX: rxChar = c
            case GATT.batteryLevel:
                peripheral.readValue(for: c)
                if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
            case GATT.firmwareRevision, GATT.serialNumber:
                peripheral.readValue(for: c)
            default: break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Log.warn("\(displayName) notify \(characteristic.uuid) failed: \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == ZwiftUUID.asyncChar || characteristic.uuid == ZwiftUUID.syncTX {
            subscriptions += 1
            if subscriptions == 2 {
                if let tx = txChar, tx.properties.contains(.read) { peripheral.readValue(for: tx) }
                sendRideOn()
            }
        }
    }

    private func write(_ data: Data) {
        guard let rx = rxChar else { return }
        let type: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        Log.ble("\(displayName) ⇢ \(data.hexString)")
        peripheral.writeValue(data, for: rx, type: type)
    }

    private func sendRideOn() {
        rideOnAttempts += 1
        write(ZwiftMessages.rideOn)
        rideOnTimer?.invalidate()
        rideOnTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, !self.handshakeDone else { return }
            if self.rideOnAttempts < 3 {
                self.sendRideOn()
            } else {
                Log.warn("\(self.displayName): no RideOn acknowledgement. Old firmware needing the encrypted handshake, or the device is asleep.")
                self.session.controllerStatusChanged(self, .stalled)
            }
        }
    }

    private func onHandshake() {
        handshakeDone = true
        handshakeAt = Date()
        lastFrameAt = Date()
        rideOnTimer?.invalidate()
        session.controllerStatusChanged(self, .ready)
        Log.info("\(displayName) handshake OK")

        if type == .clickV2Left {
            switch session.settings.clickV2LeftMode {
            case .unlockWithZwift:
                write(ZwiftMessages.clickV2Unlock)
                if let last = session.settings.lastZwiftUnlock, Date().timeIntervalSince(last) < 86400 {
                    Log.info("Click v2 left: unlock sent (Zwift blessing \(Int(Date().timeIntervalSince(last) / 3600)) h old)")
                } else {
                    Log.warn("Click v2 left: no Zwift unlock recorded in the last 24 h; the puck may stop reporting after ~1 min")
                }
            case .restartLoop:
                scheduleRestart()
            case .ignore:
                break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.write(ZwiftMessages.getDeviceInfo) }
        if session.settings.controllerKeepAlive {
            keepAliveTimer?.invalidate()
            keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                guard let self, self.handshakeDone else { return }
                self.write(ZwiftMessages.getDeviceInfo)
            }
        }
    }

    private func scheduleRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            guard let self, self.handshakeDone else { return }
            Log.info("\(self.displayName): restart loop → sending reset")
            self.write(ZwiftMessages.reset)
        }
    }

    func requestReset() { write(ZwiftMessages.reset) }

    func vibrate() {
        guard handshakeDone, type != .click, type != .clickV2Left, type != .clickV2Right else { return }
        write(ZwiftMessages.haptic())
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let d = characteristic.value, !d.isEmpty else { return }
        switch characteristic.uuid {
        case GATT.batteryLevel:
            session.controllerBattery(self, Int(d[d.startIndex]))
        case GATT.firmwareRevision:
            Log.info("\(displayName) firmware \(String(decoding: d, as: UTF8.self))")
        case GATT.serialNumber:
            let s = String(decoding: d, as: UTF8.self)
            Log.info("\(displayName) serial \(s)")
            if type == nil, let prefix = s.split(separator: "-").first, let v = UInt8(prefix, radix: 16), let t = ZwiftDeviceType(rawValue: v) {
                type = t
                Log.info("\(displayName) identified from serial as \(t.label)")
            }
        case ZwiftUUID.syncTX:
            handleSync(d)
        case ZwiftUUID.asyncChar:
            handleAsync(d)
        default: break
        }
    }

    private func handleSync(_ d: Data) {
        Log.ble("\(displayName) ⇠(sync) \(d.hexString)")
        if ZwiftMessages.isRideOnResponse(d) {
            if d.count > 8 {
                Log.warn("\(displayName) answered with a public key: firmware requires the encrypted handshake (not implemented)")
            }
            if !handshakeDone { onHandshake() }
            return
        }
        guard let op = d.first else { return }
        if op == ZwiftOpcode.getResponse.rawValue, let info = ZwiftMessages.parseDeviceInfo(d.dropFirst()) {
            Log.info("\(displayName) info: name=\(info.name ?? "?") serial=\(info.serial ?? "?") hw=\(info.hardware ?? "?") fw=\(info.firmware ?? "?") product=\(info.productId ?? -1)")
            if type == nil, let p = info.productId, let t = ZwiftDeviceType(rawValue: UInt8(clamping: p)) { type = t }
        }
    }

    private func handleAsync(_ d: Data) {
        lastFrameAt = Date()
        guard let op = d.first else { return }
        switch op {
        case ZwiftOpcode.idle.rawValue:
            break
        case ZwiftOpcode.battery.rawValue:
            if let pct = ZwiftMessages.parseBattery(d.dropFirst()) { session.controllerBattery(self, pct) }
        case ZwiftOpcode.controllerNotification.rawValue:
            let st = ZwiftMessages.parseControllerNotification(d.dropFirst())
            Log.ble("\(displayName) buttons \(d.hexString) → bitmap \(String(format: "%08X", st.rawBitmap)) \(st.buttons.map(\.rawValue).sorted())")
            applyPressed(st.buttons)
        case ZwiftOpcode.clickKeypad.rawValue:
            let b = ZwiftMessages.parseClickKeypad(d.dropFirst())
            Log.ble("\(displayName) click \(d.hexString) → \(b.map(\.rawValue).sorted())")
            applyPressed(b)
        case ZwiftOpcode.playKeypad.rawValue:
            let r = ZwiftMessages.parsePlayKeypad(d.dropFirst())
            Log.ble("\(displayName) play \(d.hexString) → \(r.buttons.map(\.rawValue).sorted())")
            applyPressed(r.buttons)
        case ZwiftOpcode.vendor.rawValue:
            Log.ble("\(displayName) vendor ⇠ \(d.hexString)")
            if d.count >= 2, d[d.startIndex + 1] == 0x03 { lastVendor = d }
            if d.count >= 5, d[d.startIndex + 1] == 0x05 {
                Log.warn("\(displayName): device reports it stopped (server lock). Re-bless it in Zwift or use the restart loop.")
                session.controllerStatusChanged(self, .stalled)
            }
        case ZwiftOpcode.lostControl.rawValue:
            Log.warn("\(displayName): another app took control")
            session.controllerStatusChanged(self, .stalled)
        case ZwiftOpcode.logData.rawValue:
            Log.ble("\(displayName) log \(d.hexString)")
        default:
            Log.ble("\(displayName) ⇠(async) \(d.hexString)")
        }
        if handshakeDone { session.controllerStatusChanged(self, .ready) }
    }

    private func applyPressed(_ now: Set<ControllerButton>) {
        let newlyPressed = now.subtracting(pressed)
        pressed = now
        for b in newlyPressed { session.controllerPressed(b, from: self) }
    }

    func checkStall(now: Date) -> Bool {
        guard handshakeDone else { return false }
        return now.timeIntervalSince(lastFrameAt) > 20
    }
}
