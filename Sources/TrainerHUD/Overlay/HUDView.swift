import SwiftUI

struct HUDView: View {
    @ObservedObject var state: RideState
    @ObservedObject var settings: Settings
    var controllerLabel: (String) -> String
    var onQuit: () -> Void = {}
    @State private var hovering = false
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scale: CGFloat { CGFloat(settings.overlayScale) }

    var body: some View {
        Group {
            if settings.overlayMinimized { minimized } else { expanded }
        }
        .onHover { hovering = $0 }
        .onReceive(clockTimer) { now in clock = now }
    }

    private var chrome: some ShapeStyle { Color.black.opacity(settings.overlayOpacity) }

    private var expanded: some View {
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
        .padding(.top, hovering ? 10 * scale : 0)
        .background(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(chrome))
        .overlay(alignment: .topTrailing) { if hovering { toolbar } }
        .overlay(alignment: .top) {
            if hovering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 3 * scale)
            }
        }
        .fixedSize()
    }

    private var minimized: some View {
        HStack(spacing: 10 * scale) {
            if settings.showGear {
                HStack(spacing: 3 * scale) {
                    Image(systemName: "gearshape.fill").font(.system(size: 10 * scale)).foregroundStyle(.cyan.opacity(0.8))
                    Text("\(state.gearIndex + 1)").foregroundStyle(.cyan)
                }
            }
            if settings.showPower {
                Text("\(state.power3s)") + Text(" W").font(.system(size: 9 * scale, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
            if settings.showHeartRate {
                HStack(spacing: 2 * scale) {
                    Image(systemName: "heart.fill").font(.system(size: 9 * scale)).foregroundStyle(hrColor)
                    Text(state.heartRate > 0 ? "\(state.heartRate)" : "--").foregroundStyle(hrColor)
                }
            }
            if settings.showTime {
                Text(state.elapsedString).foregroundStyle(.white.opacity(0.85))
            }
            Button { settings.overlayMinimized = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.4))
                    .frame(width: 16 * scale, height: 16 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand")
        }
        .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
        .monospacedDigit()
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 6 * scale)
        .background(Capsule().fill(chrome))
        .fixedSize()
    }

    private var toolbar: some View {
        HStack(spacing: 2 * scale) {
            toolButton("minus", help: "Minimize") { settings.overlayMinimized = true }
            toolButton("xmark", help: "Quit TrainerHUD") { onQuit() }
        }
        .padding(4 * scale)
    }

    private func toolButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 16 * scale, height: 16 * scale)
                .background(Circle().fill(Color.white.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
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
