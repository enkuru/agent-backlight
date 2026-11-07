import AgentBacklightCore
import AppKit
import Observation

/// The panel's view of one agent's hooks. Changes to the hook file are confirmed first.
@MainActor @Observable
final class HooksModel {
    private(set) var status = AgentHooks.Status.notInstalled
    private(set) var problem: String?
    let agent: String
    @ObservationIgnored private let hooks: AgentHooks

    init(_ hooks: AgentHooks) {
        self.hooks = hooks
        agent = hooks.agent
    }

    func refresh() {
        status = hooks.status()
    }

    func install() {
        let confirmed = confirm(
            "Add Agent Backlight to \(agent)?",
            "Adds the hook command to \(hooks.installer.events.count) events in \(hooks.displayPath). Your other settings and hooks stay; the file is rewritten with sorted keys and the current one is kept as \((hooks.backupPath as NSString).lastPathComponent).\n\n\(hooks.pickUp)",
            button: "Add Hooks"
        )
        guard confirmed else { return }
        run { () throws(AgentHooks.Failure) in try hooks.install() }
    }

    func remove() {
        let confirmed = confirm(
            "Remove Agent Backlight from \(agent)?",
            "Removes the hook command from \(hooks.displayPath) and keeps the current file as \((hooks.backupPath as NSString).lastPathComponent).",
            button: "Remove Hooks"
        )
        guard confirmed else { return }
        run { () throws(AgentHooks.Failure) in try hooks.remove() }
    }

    private func run(_ change: () throws(AgentHooks.Failure) -> Void) {
        do {
            try change()
            problem = nil
        } catch {
            problem = error.description
        }
        refresh()
    }

    private func confirm(_ title: String, _ text: String, button: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
