import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: Session!
    private var overlay: OverlayController!
    private var menu: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("TrainerHUD starting (\(ProcessInfo.processInfo.operatingSystemVersionString))")
        session = Session()
        overlay = OverlayController(session: session)
        session.overlay = overlay
        menu = StatusMenuController(session: session, overlay: overlay)
        NSApp.servicesProvider = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.shutdown()
        Log.info("TrainerHUD quitting")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
