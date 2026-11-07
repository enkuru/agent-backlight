/// Follows every Claude Code and Codex session from its hook events. Only sessions that are thinking or asking are kept.
public struct SessionTracker: Sendable {
    /// Tools that wait for your answer before they run. `request_user_input` is Codex's.
    static let askingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode", "request_user_input"]
    /// Notifications that mean Claude is waiting for your decision.
    static let askingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]

    public private(set) var sessions: [String: AgentState] = [:]

    public init() {}

    public var state: AgentState { sessions.values.max() ?? .normal }

    public mutating func apply(_ event: HookEvent) {
        let id = event.sessionID
        switch event.name {
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
            sessions[id] = .thinking
        case "PreToolUse":
            sessions[id] = Self.askingTools.contains(event.toolName ?? "") ? .question : .thinking
        case "PermissionRequest":
            sessions[id] = .question
        case "Notification":
            if let type = event.notificationType, Self.askingNotifications.contains(type) {
                sessions[id] = .question
            } else if event.notificationType == "idle_prompt", sessions[id] == .thinking {
                // Claude is waiting for a prompt. An interrupted turn (Esc) sends no Stop, so this ends its wave.
                // A pending question keeps blinking.
                sessions[id] = nil
            }
        case "Stop", "StopFailure", "SessionEnd":
            sessions[id] = nil
        default:
            break
        }
    }

    public mutating func clear() { sessions.removeAll() }
}
