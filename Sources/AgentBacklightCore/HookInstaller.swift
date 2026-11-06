/// Adds or removes this app's hook command in Claude Code's settings, leaving every other setting and hook as it was.
public enum HookInstaller {
    public static let events = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "Stop", "StopFailure", "SessionEnd"
    ]
    public static let commandName = "agent-backlight-hook"
    static let timeoutSeconds = 5

    public static func isInstalled(command: String, in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return events.allSatisfy { event in
            groups(hooks[event]).contains { group in
                entries(group).contains { $0["command"] as? String == command }
            }
        }
    }

    /// Whether any event runs this app's command, from this copy of the app or another.
    public static func hasAnyInstall(in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { groups($0).contains { entries($0).contains(where: isOurs) } }
    }

    /// Registers `command` for every event, replacing earlier installs from any location.
    public static func installing(command: String, into settings: [String: Any]) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        let group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeoutSeconds]]]
        for event in events {
            hooks[event] = groups(hooks[event]) + [group]
        }
        result["hooks"] = hooks
        return result
    }

    /// Removes every hook that runs this app's command. Lists and groups emptied by the removal go too.
    public static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var removedAny = false
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            var removed = false
            let kept: [[String: Any]] = list.compactMap { group in
                let all = entries(group)
                let others = all.filter { !isOurs($0) }
                guard others.count < all.count else { return group }
                removed = true
                guard !others.isEmpty else { return nil }
                var trimmed = group
                trimmed["hooks"] = others
                return trimmed
            }
            guard removed else { continue }
            removedAny = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard removedAny else { return settings }
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.hasSuffix("/" + commandName) == true
    }

    private static func groups(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

    private static func entries(_ group: [String: Any]) -> [[String: Any]] { group["hooks"] as? [[String: Any]] ?? [] }
}
