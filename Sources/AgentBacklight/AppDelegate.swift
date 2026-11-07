import AgentBacklightCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = EventLog()
    private var light: LightController?
    private var statusItem: StatusItemController?
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let light = LightController(log: log)
        let hooks = [HooksModel(.claudeCode), HooksModel(.codex)]
        let loginItem = LoginItem()
        let statusItem = StatusItemController(panel: PanelView(light: light, hooks: hooks, loginItem: loginItem)) {
            hooks.forEach { $0.refresh() }
            loginItem.refresh()
        }
        light.onIcon = { [weak statusItem] frame in statusItem?.show(frame) }
        self.light = light
        self.statusItem = statusItem

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(hookEvent(_:)),
            name: HookChannel.notification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        quitCleanly(on: [SIGTERM, SIGINT, SIGHUP])
        log.write("started")
        light.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        light?.shutdown()
        log.write("quit")
    }

    @objc private func hookEvent(_ notification: Notification) {
        guard let info = notification.userInfo, let event = HookChannel.event(from: info) else { return }
        light?.receive(event)
    }

    /// A kill or logout signal goes through the normal quit, so the keyboard gets its light back.
    private func quitCleanly(on signals: [Int32]) {
        for number in signals {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
