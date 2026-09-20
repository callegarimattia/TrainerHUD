import SwiftUI

struct HUDView: View {
    @ObservedObject var state: RideState
    @ObservedObject var settings: Settings
    var controllerLabel: (String) -> String
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scale: CGFloat { CGFloat(settings.overlayScale) }

    var body: some View {
        VStack(spacing: 4 * scale) {
            HStack(spacing: 14 * scale) {
                if settings.showPower {
                    Metric(title: "POWER", value: "\(state.power3s)", unit: "W", scale: scale, color: .white)
                }
                if settings.showCadence {
                    Metric(title: "CADENCE", value: "\(state.cadence)", unit: "rpm", scale: scale, color: .white)
                }
                if settings.showHeartRate {
                    Metric(title: "HEART", value: state.heartRate > 0 ? "\(state.heartRate)" : "--", unit: "bpm", scale: scale, color: hrColor)
                }
                if settings.showSpeed {
                    Metric(title: "SPEED", value: String(format: "%.1f", state.speedKmh), unit: "km/h", scale: scale, color: .white)
                }
                if settings.showTime {
                    Metric(title: state.timerRunning ? "TIME" : "TIME ⏸", value: state.elapsedString, unit: "", scale: scale, color: .white)
                }
                if settings.showDistance {
                    Metric(title: "DIST", value: String(format: "%.1f", state.distanceKm), unit: "km", scale: scale, color: .white)
                }
                if settings.showGear {
                    GearCell(index: state.gearIndex, count: state.gearCount, ratio: state.gearRatio, scale: scale, flash: state.lastShift)
                }
                if settings.showGrade {
                    Metric(title: state.mode == .erg ? "ERG" : "GRADE",
                           value: state.mode == .erg ? "\(state.ergTarget)" : String(format: "%+.1f", state.gradePercent),
                           unit: state.mode == .erg ? "W" : "%", scale: scale, color: state.mode == .erg ? .orange : .white)
                }
                if settings.showResistance, let r = state.resistance {
                    Metric(title: "RES", value: "\(r)", unit: "", scale: scale, color: .white)
                }
                if settings.showClock {
                    Metric(title: "CLOCK", value: clockString, unit: "", scale: scale, color: .white.opacity(0.8))
                }
                statusColumn
            }
            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 8 * scale)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Color.black.opacity(settings.overlayOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .strokeBorder(settings.overlayLocked ? Color.white.opacity(0.08) : Color.yellow.opacity(0.9), lineWidth: settings.overlayLocked ? 1 : 2)
        )
        .fixedSize()
        .onReceive(clockTimer) { now in
            clock = now
        }
    }

    @State private var clock = Date()
    private var clockString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: clock)
    }

    private var hrColor: Color {
        let hr = state.heartRate
        if hr == 0 { return .gray }
        if hr < 120 { return .white }
        if hr < 145 { return .green }
        if hr < 160 { return .yellow }
        if hr < 172 { return .orange }
        return .red
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 1 * scale) {
            statusLine(symbol: state.trainerStatus.symbol, label: state.trainerHasZwiftProtocol ? "Trainer·VS" : "Trainer", status: state.trainerStatus)
            statusLine(symbol: state.heartRateStatus.symbol, label: "HR", status: state.heartRateStatus)
            if state.powerMeterStatus != .disconnected {
                statusLine(symbol: state.powerMeterStatus.symbol, label: "Pedals", status: state.powerMeterStatus)
            }
            ForEach(state.controllerStatuses.keys.sorted(), id: \.self) { id in
                let st = state.controllerStatuses[id] ?? .disconnected
                let bat = state.controllerBattery[id].map { " \($0)%" } ?? ""
                statusLine(symbol: st.symbol, label: controllerLabel(id) + bat, status: st)
            }
            if !state.bluetoothOn {
                statusLine(symbol: "✕", label: "Bluetooth off", status: .stalled)
            }
        }
        .font(.system(size: 9 * scale, weight: .medium, design: .rounded))
    }

    private func statusLine(symbol: String, label: String, status: ConnectionStatus) -> some View {
        HStack(spacing: 3 * scale) {
            Text(symbol).foregroundStyle(statusColor(status))
            Text(label).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func statusColor(_ s: ConnectionStatus) -> Color {
        switch s {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .yellow
        case .ready: return .green
        case .stalled: return .red
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let unit: String
    let scale: CGFloat
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2 * scale) {
                Text(value)
                    .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

private struct GearCell: View {
    let index: Int
    let count: Int
    let ratio: Double
    let scale: CGFloat
    let flash: (up: Bool, at: Date)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GEAR")
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4 * scale) {
                Text("\(index + 1)")
                    .font(.system(size: 28 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(recent ? (flash?.up == true ? Color.green : Color.orange) : Color.cyan)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(String(format: "%.2f", ratio))
                        .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 1.5 * scale) {
                        ForEach(0..<max(count, 1), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(i <= index ? Color.cyan : Color.white.opacity(0.18))
                                .frame(width: 3 * scale, height: (4 + CGFloat(i) * 0.35) * scale)
                        }
                    }
                }
            }
        }
    }

    private var recent: Bool {
        guard let f = flash else { return false }
        return Date().timeIntervalSince(f.at) < 0.8
    }
}
