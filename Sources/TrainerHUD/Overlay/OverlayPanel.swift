import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    var interactive = false

    override var canBecomeKey: Bool { interactive }
    override var canBecomeMain: Bool { false }
}

final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((NSSize) -> Void)?

    override func layout() {
        super.layout()
        onSizeChange?(fittingSize)
    }
}

final class OverlayController {
    let panel: OverlayPanel
    private let session: Session
    private var observers: [NSObjectProtocol] = []
    private var fitTimer: Timer?

    init(session: Session) {
        self.session = session
        let settings = session.settings
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 96),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false

        let host = FittingHostingView(rootView: HUDView(state: session.state, settings: settings, controllerLabel: { [weak session] in
            session?.controllerLabel($0) ?? "Ctrl"
        }))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        host.onSizeChange = { [weak self] size in self?.fit(to: size) }
        fit(to: host.fittingSize)
        fitTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak host] _ in
            guard let self, let host else { return }
            self.fit(to: host.fittingSize)
        }

        applyLock(settings.overlayLocked)
        if let f = settings.overlayFrame, NSScreen.screens.contains(where: { $0.frame.intersects(f) }) {
            panel.setFrameOrigin(f.origin)
        } else {
            centerTop()
        }
        if settings.overlayVisible { panel.orderFrontRegardless() }

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.session.settings.overlayFrame = self.panel.frame
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reassert()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reassert()
        })
    }

    private func fit(to size: NSSize) {
        guard size.width > 10, size.height > 10 else { return }
        let f = panel.frame
        guard abs(f.width - size.width) > 0.5 || abs(f.height - size.height) > 0.5 else { return }
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func reassert() {
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if session.settings.overlayVisible { panel.orderFrontRegardless() }
    }

    func centerTop() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        session.settings.overlayFrame = panel.frame
    }

    func applyLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
        panel.interactive = !locked
        session.settings.overlayLocked = locked
        if !locked {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func toggleVisible() {
        setVisible(!session.settings.overlayVisible)
    }

    func setVisible(_ visible: Bool) {
        session.settings.overlayVisible = visible
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}
