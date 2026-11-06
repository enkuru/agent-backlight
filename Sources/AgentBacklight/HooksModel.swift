import AgentBacklightCore
import AppKit
import Observation

/// The panel's view of the Claude Code hooks. Changes to the settings file are confirmed first.
@MainActor @Observable
final class HooksModel {
    private(set) var status = ClaudeHooks.Status.notInstalled
    private(set) var problem: String?
    @ObservationIgnored private let hooks = ClaudeHooks()

    func refresh() {
        status = hooks.status()
    }

    func install() {
        let confirmed = confirm(
            "Add Agent Backlight to Claude Code?",
            "Adds the hook command to \(HookInstaller.events.count) events in \(hooks.displayPath). Your other settings and hooks stay; the file is rewritten with sorted keys and the current one is kept as \((hooks.backupPath as NSString).lastPathComponent).\n\nRestart open Claude Code sessions to pick up the hooks.",
            button: "Add Hooks"
        )
        guard confirmed else { return }
        run { () throws(ClaudeHooks.Failure) in try hooks.install() }
    }

    func remove() {
        let confirmed = confirm(
            "Remove Agent Backlight from Claude Code?",
            "Removes the hook command from \(hooks.displayPath) and keeps the current file as \((hooks.backupPath as NSString).lastPathComponent).",
            button: "Remove Hooks"
        )
        guard confirmed else { return }
        run { () throws(ClaudeHooks.Failure) in try hooks.remove() }
    }

    private func run(_ change: () throws(ClaudeHooks.Failure) -> Void) {
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
