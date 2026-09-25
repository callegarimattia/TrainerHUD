# CYCPLUS C3 cadence sensor research

Research date: 2026-09-25  
Scope: CYCPLUS Smart Speed / Cadence Sensor C3 with a macOS Swift CoreBluetooth central.

## Result summary

| Question | Result |
| --- | --- |
| Standard BLE Cycling Speed and Cadence Service (`0x1816`) | **Not confirmed by CYCPLUS documentation.** The manual confirms BLE and ANT+ support, but it does not name `0x1816`, `0x2A5B`, or show a GATT table. `0x1816` is the Bluetooth SIG assigned UUID for the standard service. |
| Cadence data | **Confirmed for the standard service:** subscribe to CSC Measurement (`0x2A5B`) and parse crank revolution data. |
| Speed and cadence at the same time | **No.** The C3 has one physical sensor and two exclusive modes. |
| Pairing and reset | **No CYCPLUS pairing or reset procedure is documented.** BLE allows one connected device or app at a time. The standard does not provide a crank-revolution reset. |

## CYCPLUS product facts — confirmed

The C3 manual says:

- The sensor supports BLE and ANT+.
- The default mode is cadence.
- One sensor cannot measure speed and cadence at the same time. Use two sensors for both values.
- Turn the battery cover to change between speed mode and cadence mode. The manual says to hold the cover during this change so it does not pop open.
- Wheel rotation or crank rotation activates the sensor and starts a connection with the device or app.
- The BLE connection supports one device or app at a time. Disconnect the previous device before changing the connection.
- A phone app shall search for the sensor inside the app. Searching from the phone's Bluetooth settings is not valid for this product.
- The speed mode requires a hub width greater than 38 mm.

The manual also lists 600 hours of cadence use, 400 hours of speed use, IP67 protection, and compatibility with BLE or ANT+ apps and devices. The CYCPLUS FAQ does not recommend a spin bike when a magnet or antenna can interrupt the transmission. It recommends the front hub for speed mode because rear-wheel data can be erratic. These limits do not change the cadence packet format, but they affect test setup.

Sources: [CYCPLUS C3 manual PDF](https://cdn.shopify.com/s/files/1/0413/9597/8398/files/BZ-4141010271-01-_C3.pdf?v=1755507903), [CYCPLUS sensor manual page](https://www.cycplus.com/pages/manual-sensors), [CYCPLUS FAQ](https://www.cycplus.com/apps/frequently-asked-questions?faq-article-id=189812&faq-section-id=42342), and [CYCPLUS C3 product page](https://www.cycplus.com/products/cycplus-smart-speed-cadence-sensor).

## Standard CSCS data needed for cadence — confirmed by Bluetooth SIG

The Bluetooth SIG assigns these identifiers:

- Service: Cycling Speed and Cadence, `0x1816`.
- CSC Measurement, `0x2A5B`: mandatory `Notify`. Its Client Characteristic Configuration descriptor (`0x2902`) is mandatory.
- CSC Feature, `0x2A5C`: mandatory `Read`.
- Sensor Location, `0x2A5D`: conditional. It is not needed for cadence calculation.
- SC Control Point, `0x2A55`: conditional. It is not needed to receive cadence notifications. CYCPLUS does not document support for it.

The CSC Measurement value is little-endian:

| Offset | Field | Cadence use |
| ---: | --- | --- |
| 0 | Flags, `UInt8` | Bit 0: wheel data present. Bit 1: crank data present. Bits 2-7 are reserved and shall be zero. |
| 1-2 | Cumulative Crank Revolutions, `UInt16` | Use the delta between two notifications. The value is allowed to roll over. |
| 3-4 | Last Crank Event Time, `UInt16` | Free-running time in 1/1024-second units. The value rolls over every 64 seconds. |

If C3 cadence mode uses standard CSCS and sends crank data only, the expected flags value is `0x02` and the notification length is 5 bytes. This is an **inference from the standard**, not a CYCPLUS-confirmed packet example. Calculate cadence as:

`rpm = deltaCrankRevolutions / (deltaEventTime / 1024) * 60`

Use unsigned 16-bit wraparound for both deltas. Discard the first sample because it has no previous sample. The standard treats this measurement as time-sensitive and says to discard it after a lost connection or an unsuccessful notification.

The standard lists no security requirement for the CSCS characteristics. It also says that the Set Cumulative Value procedure applies to wheel revolutions and shall not be used to set cumulative crank revolutions. Therefore, do not add a cadence-counter reset command unless a live C3 inspection proves a vendor-specific command.

Sources: [Bluetooth SIG Cycling Speed and Cadence Service](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-service/), [Bluetooth SIG CSCS specification HTML](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html), and [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html).

## macOS CoreBluetooth implications

For a standard implementation, CoreBluetooth shall:

1. Wait for `CBCentralManager` state `poweredOn`.
2. Use a broad scan because CYCPLUS does not document its advertisement data. The implementation uses the local CYCPLUS name only as a discovery hint. The connected handler validates the GATT service and CSC Feature before it accepts cadence data.
3. Connect, discover service `0x1816`, and discover `0x2A5B` and `0x2A5C`.
4. Read `0x2A5C` and verify that the crank-data feature bit (bit 1) is set.
5. Call `setNotifyValue(true, for:)` for `0x2A5B`, then parse notifications in the peripheral delegate.

The CYCPLUS one-device BLE limit means that the CYCPLUS phone app, another bike app, and TrainerHUD shall not hold the same BLE connection at the same time. The CSCS table lists no security requirement for its characteristics, so a separate macOS pairing flow is not expected **if the C3 exposes standard CSCS**. This is an inference. CoreBluetooth manages service discovery and notification subscription; the C3 manual gives no pairing UI or password procedure.

Sources: [Apple CBCentralManager](https://developer.apple.com/documentation/CoreBluetooth/CBCentralManager), [Apple scanForPeripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals%28withservices%3Aoptions%3A%29), [Apple CBPeripheral](https://developer.apple.com/documentation/corebluetooth/cbperipheral), and [Apple setNotifyValue](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue%28_%3Afor%3A%29).

## Required live check before calling C3 support verified

Set the C3 to cadence mode, remove any connection from the phone app, rotate the crank, and inspect the actual GATT database. Confirm service `0x1816`, characteristic `0x2A5B` with `Notify`, characteristic `0x2A5C` with `Read`, and a 5-byte cadence notification with flags `0x02`. If the service is absent, the C3 is not using standard CSCS in that mode and a vendor-specific protocol investigation is required.
