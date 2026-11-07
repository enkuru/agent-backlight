import Foundation
import Testing
@testable import AgentBacklightCore

struct HookInstallerTests {
    private let command = "/Users/me/Applications/AgentBacklight.app/Contents/MacOS/agent-backlight-hook"
    private let userGuard: [String: Any] = ["type": "command", "command": "~/.claude/hooks/guard.sh"]

    private func userSettings() -> [String: Any] {
        [
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [userGuard]]],
                "SessionStart": [["hooks": [["type": "command", "command": "echo hi"]]]]
            ]
        ]
    }

    private func json(_ value: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    @Test func installAddsOurCommandToEveryEventAndKeepsTheUsersHooks() throws {
        let result = HookInstaller.claudeCode.installing(command: command, into: userSettings())

        #expect(HookInstaller.claudeCode.isInstalled(command: command, in: result))
        #expect(result["model"] as? String == "opus")
        let hooks = try #require(result["hooks"] as? [String: Any])
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 2)
        #expect(preToolUse.first?["matcher"] as? String == "Bash")
        #expect(hooks["SessionStart"] != nil)
    }

    /// Codex trusts each hook by its event and position, so the user's hooks must keep their places.
    @Test func codexInstallAddsOnlyCodexEventsAfterTheUsersHooks() throws {
        let result = HookInstaller.codex.installing(command: command, into: userSettings())

        #expect(HookInstaller.codex.isInstalled(command: command, in: result))
        let hooks = try #require(result["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.codex.events + ["SessionStart"]))
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let usersPreToolUse = try #require((userSettings()["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        #expect(json(["list": Array(preToolUse.dropLast())]) == json(["list": usersPreToolUse]))
    }

    @Test func reinstallFromANewLocationReplacesTheOldCommand() throws {
        let installer = HookInstaller.claudeCode
        let old = installer.installing(command: "/old/place/agent-backlight-hook", into: userSettings())
        #expect(!installer.isInstalled(command: command, in: old))
        #expect(installer.hasAnyInstall(in: old))
        #expect(!installer.hasAnyInstall(in: userSettings()))

        let result = installer.installing(command: command, into: old)

        let hooks = try #require(result["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 1)
        #expect(!json(result).contains("/old/place"))
    }

    @Test func anInstallFromBeforeANewEventNeedsAnUpdate() throws {
        let installer = HookInstaller.claudeCode
        var older = installer.installing(command: command, into: userSettings())
        var hooks = try #require(older["hooks"] as? [String: Any])
        hooks["PermissionRequest"] = nil
        older["hooks"] = hooks

        #expect(!installer.isInstalled(command: command, in: older))
        #expect(installer.hasAnyInstall(in: older))
    }

    @Test(arguments: [HookInstaller.claudeCode, .codex])
    func removeRestoresTheOriginalSettings(installer: HookInstaller) {
        let installed = installer.installing(command: command, into: userSettings())
        #expect(json(installer.removing(from: installed)) == json(userSettings()))
    }

    @Test func removeKeepsUserHooksThatShareAGroupWithOurs() throws {
        let shared: [String: Any] = ["hooks": ["Stop": [["hooks": [userGuard, ["type": "command", "command": command]]]]]]
        let result = HookInstaller.claudeCode.removing(from: shared)

        let hooks = try #require(result["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect((stop.first?["hooks"] as? [[String: Any]])?.count == 1)
    }

    @Test func removeLeavesSettingsWithoutOurHooksUntouched() {
        let settings: [String: Any] = ["hooks": [String: Any](), "model": "opus"]
        #expect(json(HookInstaller.claudeCode.removing(from: settings)) == json(settings))
    }
}
