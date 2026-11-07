import Testing
@testable import AgentBacklightCore

private func event(_ name: String, _ session: String = "a", tool: String? = nil, notification: String? = nil) -> HookEvent {
    HookEvent(sessionID: session, name: name, toolName: tool, notificationType: notification)
}

struct SessionTrackerTests {
    @Test func questionInAnySessionWinsOverThinking() {
        var tracker = SessionTracker()
        tracker.apply(event("UserPromptSubmit", "a"))
        tracker.apply(event("PreToolUse", "b", tool: "AskUserQuestion"))
        #expect(tracker.state == .question)

        tracker.apply(event("Stop", "b"))
        #expect(tracker.state == .thinking)

        tracker.apply(event("Stop", "a"))
        #expect(tracker.state == .normal)
        #expect(tracker.sessions.isEmpty)
    }

    /// `PermissionRequest` comes as the dialog opens; the `permission_prompt` notification comes about 6 s later.
    @Test(arguments: [event("PermissionRequest", tool: "Bash"), event("Notification", notification: "permission_prompt")])
    func permissionPromptAsksUntilTheToolRuns(prompt: HookEvent) {
        var tracker = SessionTracker()
        tracker.apply(event("PreToolUse", tool: "Bash"))
        #expect(tracker.state == .thinking)

        tracker.apply(prompt)
        #expect(tracker.state == .question)

        tracker.apply(event("PostToolUse", tool: "Bash"))
        #expect(tracker.state == .thinking)
    }

    /// Plan approval in Claude Code, and Codex's question tool.
    @Test(arguments: ["ExitPlanMode", "request_user_input"])
    func toolsThatWaitForYourAnswerAsk(tool: String) {
        var tracker = SessionTracker()
        tracker.apply(event("PreToolUse", tool: tool))
        #expect(tracker.state == .question)
    }

    @Test func idlePromptEndsAnInterruptedWaveButNotAPendingQuestion() {
        var tracker = SessionTracker()
        tracker.apply(event("UserPromptSubmit", "interrupted"))
        tracker.apply(event("PreToolUse", "asking", tool: "AskUserQuestion"))

        tracker.apply(event("Notification", "interrupted", notification: "idle_prompt"))
        tracker.apply(event("Notification", "asking", notification: "idle_prompt"))

        #expect(tracker.sessions == ["asking": .question])
    }

    @Test func otherNotificationsChangeNothing() {
        var tracker = SessionTracker()
        tracker.apply(event("UserPromptSubmit"))
        tracker.apply(event("Notification", notification: "auth_success"))
        #expect(tracker.state == .thinking)
    }

    @Test func sessionEndForgetsTheSession() {
        var tracker = SessionTracker()
        tracker.apply(event("PreToolUse", tool: "AskUserQuestion"))
        tracker.apply(event("SessionEnd"))
        #expect(tracker.state == .normal)
    }
}
