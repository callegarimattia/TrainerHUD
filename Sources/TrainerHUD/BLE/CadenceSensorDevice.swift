import Foundation
import CoreBluetooth

final class CadenceSensorDevice: NSObject, DeviceHandler, CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let role = DeviceRole.cadenceSensor
    unowned let session: Session

    private var crankSupported: Bool?
    private var crank = CrankTracker()

    init(peripheral: CBPeripheral, session: Session) {
        self.peripheral = peripheral
        self.session = session
        super.init()
    }

    func didConnect() {
        peripheral.delegate = self
        peripheral.discoverServices([GATT.csc, GATT.battery])
    }

    func didDisconnect() {
        crankSupported = nil
        crank = CrankTracker()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            Log.error("Cadence sensor service discovery failed: \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            Log.warn("Cadence sensor characteristic discovery failed for \(service.uuid): \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            Log.ble("Cadence sensor char \(characteristic.uuid) in \(service.uuid) props=\(characteristic.properties.rawValue)")
            switch characteristic.uuid {
            case GATT.cscMeasurement:
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    Log.warn("Cadence sensor CSC Measurement does not support notifications")
                }
            case GATT.cscFeature:
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                } else {
                    Log.warn("Cadence sensor CSC Feature does not support reads")
                }
            case GATT.batteryLevel:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Log.warn("Cadence sensor notify \(characteristic.uuid) failed: \(error.localizedDescription)")
        } else {
            Log.ble("Cadence sensor notify enabled \(characteristic.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            if characteristic.uuid == GATT.cscFeature {
                crankSupported = false
                session.cadenceSensorValidation(crankSupported: false)
            }
            Log.warn("Cadence sensor value \(characteristic.uuid) failed: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case GATT.cscMeasurement:
            guard crankSupported == true else { return }
            guard let sample = CSCSample.parse(data),
                  let revolutions = sample.crankRevs,
                  let eventTime = sample.crankTime,
                  let cadence = crank.update(revs: revolutions, time1024: eventTime) else { return }
            session.cadenceSensorReport(cadence: Int(cadence.rounded()))
        case GATT.cscFeature:
            guard let features = data.u16(0) else {
                crankSupported = false
                session.cadenceSensorValidation(crankSupported: false)
                Log.warn("Cadence sensor CSC Feature has an invalid value")
                return
            }
            crankSupported = features & 0x0002 != 0
            session.cadenceSensorValidation(crankSupported: crankSupported == true)
            Log.info("Cadence sensor CSC Feature 0x\(String(format: "%04X", features)); crank data \(crankSupported == true ? "supported" : "not supported")")
        case GATT.batteryLevel:
            if let battery = data.first { Log.info("Cadence sensor battery \(battery)%") }
        default:
            break
        }
    }
}
