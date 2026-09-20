import Foundation
import CoreBluetooth

enum DeviceRole: String, Codable, CaseIterable {
    case trainer, heartRate, powerMeter, controller

    var label: String {
        switch self {
        case .trainer: return "Trainer"
        case .heartRate: return "Heart rate"
        case .powerMeter: return "Power meter"
        case .controller: return "Shifter / controller"
        }
    }
}

protocol DeviceHandler: AnyObject {
    var peripheral: CBPeripheral { get }
    var role: DeviceRole { get }
    func didConnect()
    func didDisconnect()
}

final class TrainerDevice: NSObject, DeviceHandler, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let role = DeviceRole.trainer
    unowned let session: Session

    private var indoorBikeData: CBCharacteristic?
    private var ftmsControl: CBCharacteristic?
    private var cpsMeasurement: CBCharacteristic?
    private var cscMeasurement: CBCharacteristic?
    private var zwiftAsync: CBCharacteristic?
    private var zwiftRX: CBCharacteristic?
    private var zwiftTX: CBCharacteristic?

    private(set) var zwiftReady = false
    private var zwiftSubscriptions = 0
    private var rideOnAttempts = 0
    private var rideOnTimer: Timer?
    private var keepAliveTimer: Timer?
    private var ftmsGranted = false
    private var ftmsBusy = false
    private var ftmsQueue: [Data] = []
    private var ftmsTimeout: Timer?
    private var crank = CrankTracker()
    private var cscCrank = CrankTracker()
    private var lastGearRatioX10000 = 0
    private var lastInclineX100: Int32 = 0
    private var sentFirstSim = false
    private var lastDataAt = Date.distantPast

    var hasZwiftProtocol: Bool { zwiftRX != nil }
    var hasFTMSControl: Bool { ftmsControl != nil }

    init(peripheral: CBPeripheral, session: Session) {
        self.peripheral = peripheral
        self.session = session
        super.init()
    }

    func didConnect() {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func didDisconnect() {
        zwiftReady = false
        zwiftSubscriptions = 0
        rideOnAttempts = 0
        ftmsGranted = false
        ftmsBusy = false
        ftmsQueue.removeAll()
        sentFirstSim = false
        rideOnTimer?.invalidate()
        keepAliveTimer?.invalidate()
        ftmsTimeout?.invalidate()
        indoorBikeData = nil; ftmsControl = nil; cpsMeasurement = nil; cscMeasurement = nil
        zwiftAsync = nil; zwiftRX = nil; zwiftTX = nil
    }

    // MARK: Discovery

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { Log.error("Trainer service discovery failed: \(error.localizedDescription)"); return }
        for s in peripheral.services ?? [] {
            Log.ble("Trainer service \(s.uuid)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            Log.ble("Trainer char \(c.uuid) in \(service.uuid) props=\(c.properties.rawValue)")
            switch c.uuid {
            case GATT.indoorBikeData:
                indoorBikeData = c; peripheral.setNotifyValue(true, for: c)
            case GATT.ftmsControlPoint:
                ftmsControl = c; peripheral.setNotifyValue(true, for: c)
            case GATT.ftmsStatus:
                peripheral.setNotifyValue(true, for: c)
            case GATT.cyclingPowerMeasurement:
                cpsMeasurement = c; peripheral.setNotifyValue(true, for: c)
            case GATT.cscMeasurement:
                cscMeasurement = c; peripheral.setNotifyValue(true, for: c)
            case GATT.firmwareRevision, GATT.serialNumber:
                peripheral.readValue(for: c)
            case ZwiftUUID.asyncChar:
                zwiftAsync = c; peripheral.setNotifyValue(true, for: c)
            case ZwiftUUID.syncTX:
                zwiftTX = c; peripheral.setNotifyValue(true, for: c)
            case ZwiftUUID.syncRX:
                zwiftRX = c
            default: break
            }
        }
        if service.uuid == ZwiftUUID.service || service.uuid == ZwiftUUID.serviceFC82 {
            session.trainerCapabilitiesChanged()
        }
        if service.uuid == GATT.ftms || service.uuid == GATT.cyclingPower {
            session.trainerCapabilitiesChanged()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Log.warn("Trainer notify state \(characteristic.uuid) failed: \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == ZwiftUUID.asyncChar || characteristic.uuid == ZwiftUUID.syncTX {
            zwiftSubscriptions += 1
            if zwiftSubscriptions == 2 { sendRideOn() }
        }
    }

    // MARK: Zwift protocol

    private func sendRideOn() {
        guard let rx = zwiftRX else { return }
        rideOnAttempts += 1
        Log.ble("Trainer → RideOn (attempt \(rideOnAttempts))")
        writeZwift(ZwiftMessages.rideOnTrainer, to: rx)
        rideOnTimer?.invalidate()
        rideOnTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, !self.zwiftReady else { return }
            if self.rideOnAttempts < 3 {
                self.sendRideOn()
            } else {
                Log.warn("Trainer never acknowledged RideOn; virtual shifting via Zwift protocol unavailable, falling back to FTMS")
                self.session.trainerZwiftReady(false)
            }
        }
    }

    private func writeZwift(_ data: Data, to c: CBCharacteristic) {
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        Log.ble("Trainer ZP ⇢ \(data.hexString)")
        peripheral.writeValue(data, for: c, type: type)
    }

    private func zwiftInitSequence() {
        guard let rx = zwiftRX else { return }
        let ratio = session.currentGearRatioX10000()
        let bike = Int((session.settings.bikeWeightKg * 100).rounded())
        let rider = Int((session.settings.riderWeightKg * 100).rounded())
        let incline = Int32((session.state.gradePercent * 100).rounded())
        lastGearRatioX10000 = ratio
        lastInclineX100 = incline
        let steps: [Data] = [
            ZwiftMessages.unknown41,
            ZwiftMessages.gear(ratioX10000: ratio, bikeKgX100: bike, riderKgX100: rider),
            ZwiftMessages.getDeviceInfo,
            ZwiftMessages.simulation(inclineX100: incline, full: true),
            ZwiftMessages.gear(ratioX10000: ratio),
            ZwiftMessages.getGearRatio,
        ]
        for (i, d) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i)) { [weak self] in
                guard let self, self.zwiftReady else { return }
                self.writeZwift(d, to: rx)
            }
        }
        sentFirstSim = true
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.keepAlive()
        }
    }

    private func keepAlive() {
        guard zwiftReady, let rx = zwiftRX, session.state.mode == .sim else { return }
        writeZwift(ZwiftMessages.simulation(inclineX100: lastInclineX100, full: false), to: rx)
    }

    func setGear(ratioX10000: Int) {
        lastGearRatioX10000 = ratioX10000
        if zwiftReady, let rx = zwiftRX {
            if !sentFirstSim {
                writeZwift(ZwiftMessages.simulation(inclineX100: lastInclineX100, full: true), to: rx)
                sentFirstSim = true
            }
            writeZwift(ZwiftMessages.gear(ratioX10000: ratioX10000), to: rx)
            writeZwift(ZwiftMessages.getGearRatio, to: rx)
        } else {
            sendFTMSSimulation()
        }
    }

    func setGrade(percent: Double) {
        lastInclineX100 = Int32((percent * 100).rounded())
        if zwiftReady, let rx = zwiftRX {
            writeZwift(ZwiftMessages.simulation(inclineX100: lastInclineX100, full: !sentFirstSim), to: rx)
            sentFirstSim = true
        } else {
            sendFTMSSimulation()
        }
    }

    func setErg(watts: Int?) {
        if let watts {
            enqueueFTMS(FTMSControl.targetPower(watts))
        } else if zwiftReady, let rx = zwiftRX {
            writeZwift(ZwiftMessages.simulation(inclineX100: lastInclineX100, full: true), to: rx)
            writeZwift(ZwiftMessages.gear(ratioX10000: lastGearRatioX10000), to: rx)
        } else {
            sendFTMSSimulation()
        }
    }

    func releaseVirtualShifting() {
        guard zwiftReady, let rx = zwiftRX else { return }
        writeZwift(ZwiftMessages.gear(ratioX10000: 0), to: rx)
    }

    // MARK: FTMS control (fallback when no Zwift protocol, and ERG)

    private func sendFTMSSimulation() {
        guard ftmsControl != nil else { return }
        let grade = session.effectiveFTMSGrade()
        enqueueFTMS(FTMSControl.simulation(gradePercent: grade))
    }

    private func enqueueFTMS(_ cmd: Data) {
        guard ftmsControl != nil else { return }
        if !ftmsGranted, ftmsQueue.first != FTMSControl.requestControl {
            ftmsQueue.insert(FTMSControl.requestControl, at: 0)
        }
        ftmsQueue.append(cmd)
        pumpFTMS()
    }

    private func pumpFTMS() {
        guard !ftmsBusy, let c = ftmsControl, !ftmsQueue.isEmpty else { return }
        let cmd = ftmsQueue.removeFirst()
        ftmsBusy = true
        Log.ble("Trainer FTMS ⇢ \(cmd.hexString)")
        peripheral.writeValue(cmd, for: c, type: .withResponse)
        ftmsTimeout?.invalidate()
        ftmsTimeout = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.ftmsBusy = false
            self?.pumpFTMS()
        }
    }

    // MARK: Values

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { Log.warn("Trainer write \(characteristic.uuid) failed: \(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let d = characteristic.value else { return }
        switch characteristic.uuid {
        case GATT.indoorBikeData:
            if let ibd = IndoorBikeData.parse(d) {
                lastDataAt = Date()
                session.trainerReport(power: ibd.power, cadence: ibd.cadence.map { Int($0.rounded()) },
                                      speedKmh: ibd.speedKmh, resistance: ibd.resistance, source: "ftms")
            }
        case GATT.cyclingPowerMeasurement:
            if let s = CyclingPowerSample.parse(d) {
                lastDataAt = Date()
                var cad: Int?
                if let r = s.crankRevs, let t = s.crankTime, let c = crank.update(revs: r, time1024: t) { cad = Int(c.rounded()) }
                session.trainerReport(power: s.watts, cadence: cad, speedKmh: nil, resistance: nil, source: "cps")
            }
        case GATT.cscMeasurement:
            if let s = CSCSample.parse(d), let r = s.crankRevs, let t = s.crankTime, let c = cscCrank.update(revs: r, time1024: t) {
                session.trainerReport(power: nil, cadence: Int(c.rounded()), speedKmh: nil, resistance: nil, source: "csc")
            }
        case GATT.ftmsControlPoint:
            Log.ble("Trainer FTMS ⇠ \(FTMSControl.describeResponse(d))")
            if d.count >= 3, d[d.startIndex] == 0x80 {
                if d[d.startIndex + 1] == 0x00 { ftmsGranted = d[d.startIndex + 2] == 0x01 }
                ftmsTimeout?.invalidate()
                ftmsBusy = false
                pumpFTMS()
            }
        case GATT.ftmsStatus:
            Log.ble("Trainer FTMS status \(d.hexString)")
            if d.first == 0xFF { ftmsGranted = false }
        case GATT.firmwareRevision:
            Log.info("Trainer firmware: \(String(decoding: d, as: UTF8.self))")
        case GATT.serialNumber:
            Log.info("Trainer serial: \(String(decoding: d, as: UTF8.self))")
        case ZwiftUUID.syncTX:
            handleZwiftSync(d)
        case ZwiftUUID.asyncChar:
            handleZwiftAsync(d)
        default:
            break
        }
    }

    private func handleZwiftSync(_ d: Data) {
        Log.ble("Trainer ZP ⇠(sync) \(d.hexString)")
        if ZwiftMessages.isRideOnResponse(d) {
            guard !zwiftReady else { return }
            zwiftReady = true
            rideOnTimer?.invalidate()
            Log.info("Trainer accepted RideOn: virtual shifting available")
            session.trainerZwiftReady(true)
            zwiftInitSequence()
            return
        }
        guard let op = d.first else { return }
        if op == ZwiftOpcode.getResponse.rawValue {
            let payload = d.dropFirst()
            if let info = ZwiftMessages.parseDeviceInfo(payload) {
                Log.info("Trainer ZP device info: name=\(info.name ?? "?") serial=\(info.serial ?? "?") hw=\(info.hardware ?? "?") fw=\(info.firmware ?? "?")")
            } else {
                let fields = Proto.decode(payload).map { "f\($0.number)=\($0.wireType == 2 ? $0.bytes.hexString : String($0.varint))" }
                Log.info("Trainer ZP get response: \(fields.joined(separator: " "))")
            }
        }
    }

    private func handleZwiftAsync(_ d: Data) {
        guard let op = d.first else { return }
        switch op {
        case ZwiftOpcode.trainerData.rawValue:
            let t = ZwiftMessages.parseTrainerData(d.dropFirst())
            session.trainerZwiftData(t)
        case ZwiftOpcode.logData.rawValue:
            Log.ble("Trainer ZP log \(d.hexString)")
        default:
            Log.ble("Trainer ZP ⇠(async) \(d.hexString)")
        }
    }
}

final class HeartRateDevice: NSObject, DeviceHandler, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let role = DeviceRole.heartRate
    unowned let session: Session

    init(peripheral: CBPeripheral, session: Session) {
        self.peripheral = peripheral
        self.session = session
        super.init()
    }

    func didConnect() {
        peripheral.delegate = self
        peripheral.discoverServices([GATT.heartRate, GATT.battery])
    }

    func didDisconnect() {}

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == GATT.heartRateMeasurement { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == GATT.batteryLevel { peripheral.readValue(for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let d = characteristic.value else { return }
        if characteristic.uuid == GATT.heartRateMeasurement, let s = HeartRateSample.parse(d) {
            session.heartRateReport(bpm: s.bpm)
        } else if characteristic.uuid == GATT.batteryLevel, let b = d.first {
            Log.info("HRM battery \(b)%")
        }
    }
}

final class PowerMeterDevice: NSObject, DeviceHandler, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let role = DeviceRole.powerMeter
    unowned let session: Session
    private var crank = CrankTracker()

    init(peripheral: CBPeripheral, session: Session) {
        self.peripheral = peripheral
        self.session = session
        super.init()
    }

    func didConnect() {
        peripheral.delegate = self
        peripheral.discoverServices([GATT.cyclingPower, GATT.battery])
    }

    func didDisconnect() {}

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == GATT.cyclingPowerMeasurement { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == GATT.batteryLevel { peripheral.readValue(for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let d = characteristic.value else { return }
        if characteristic.uuid == GATT.cyclingPowerMeasurement, let s = CyclingPowerSample.parse(d) {
            var cad: Int?
            if let r = s.crankRevs, let t = s.crankTime, let c = crank.update(revs: r, time1024: t) { cad = Int(c.rounded()) }
            session.powerMeterReport(power: s.watts, cadence: cad)
        } else if characteristic.uuid == GATT.batteryLevel, let b = d.first {
            Log.info("Power meter battery \(b)%")
        }
    }
}
