import AppKit
import SwiftUI

/// The menu bar item: the animated Keycap icon, and the panel that opens when you click it.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let onOpen: () -> Void
    private var shown: KeycapIcon.Frame?

    init(panel: some View, onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        super.init()
        let host = NSHostingController(rootView: panel)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle(_:))
            button.toolTip = "Agent Backlight"
        }
        show(.normal)
    }

    func show(_ frame: KeycapIcon.Frame) {
        guard frame != shown, let button = item.button else { return }
        shown = frame
        button.image = KeycapIcon.image(for: frame)
        button.appearsDisabled = frame == .off
        button.setAccessibilityLabel("Agent Backlight, \(frame.spokenState)")
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        onOpen()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }
}

private extension KeycapIcon.Frame {
    var spokenState: String {
        switch self {
        case .normal: "normal"
        case .off: "signals off"
        case .thinking: "thinking"
        case .question: "question"
        }
    }
}
