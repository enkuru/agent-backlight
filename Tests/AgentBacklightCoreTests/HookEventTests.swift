import Foundation
import Testing
@testable import AgentBacklightCore

struct HookEventTests {
    @Test func hookInputReachesTheAppUnchanged() throws {
        let stdin = """
        {"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt",
         "message":"Claude needs your permission to use Bash","cwd":"/tmp","permission_mode":"default"}
        """
        let event = try #require(HookEvent(hookInput: Data(stdin.utf8)))

        #expect(event == HookEvent(sessionID: "s1", name: "Notification", notificationType: "permission_prompt"))
        #expect(HookChannel.event(from: HookChannel.userInfo(for: event)) == event)
    }

    /// The fields Codex 0.165 requires for `PermissionRequest`, read from its hook input schema.
    @Test func codexInputReadsTheSameFields() throws {
        let stdin = """
        {"session_id":"019a","turn_id":"t1","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"command":"rm -rf build"},"cwd":"/tmp","model":"gpt-5.5","permission_mode":"default",
         "transcript_path":"/Users/me/.codex/sessions/2026/11/07/rollout-2026-11-07T06-33-39-019a.jsonl"}
        """
        let event = try #require(HookEvent(hookInput: Data(stdin.utf8)))

        #expect(event == HookEvent(sessionID: "019a", name: "PermissionRequest", toolName: "Bash"))
    }

    /// Captured from Codex 0.165: memory consolidation and the suggested next message run as sessions without a
    /// transcript. Counting the memory session would keep the wave on for about a minute after the real turn.
    @Test(arguments: [
        """
        {"session_id":"019b","turn_id":"t2","hook_event_name":"UserPromptSubmit","transcript_path":null,
         "model":"gpt-6.1-terra","permission_mode":"bypassPermissions","prompt":"Consolidate the supplied rollout summaries"}
        """,
        """
        {"session_id":"019c","hook_event_name":"SessionEnd","transcript_path":null,"reason":"other","cwd":"/tmp"}
        """
    ])
    func codexBackgroundSessionsAreIgnored(stdin: String) {
        #expect(HookEvent(hookInput: Data(stdin.utf8)) == nil)
    }

    /// In auto mode the classifier answers most permission requests; the ones you see send a notification later.
    @Test func claudeAutoModePermissionRequestIsIgnored() {
        let stdin = """
        {"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","permission_mode":"auto",
         "transcript_path":"/Users/me/.claude/projects/p/s1.jsonl","tool_input":{"command":"swift build"}}
        """
        #expect(HookEvent(hookInput: Data(stdin.utf8)) == nil)
    }

    @Test func claudeAutoModeToolUseStillCounts() {
        let stdin = """
        {"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","permission_mode":"auto",
         "transcript_path":"/Users/me/.claude/projects/p/s1.jsonl"}
        """
        #expect(HookEvent(hookInput: Data(stdin.utf8)) == HookEvent(sessionID: "s1", name: "PreToolUse", toolName: "Bash"))
    }

    /// Codex reports `permission_mode` "default" whoever approves, so the hook reads the reviewer from the latest
    /// `turn_context` record in the session's rollout file. The records are trimmed copies of Codex 0.165's.
    @Test(arguments: [
        (["auto_review"], false),
        (["user"], true),
        ([nil], true),
        (["user", "auto_review"], false),
        (["auto_review", "user"], true)
    ] as [([String?], Bool)])
    func codexPermissionRequestAsksOnlyWhenYouReview(reviewers: [String?], asks: Bool) throws {
        let transcript = FileManager.default.temporaryDirectory.appendingPathComponent("rollout-\(UUID()).jsonl")
        try codexRollout(reviewers: reviewers).write(to: transcript, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: transcript) }
        let stdin = """
        {"session_id":"019a","turn_id":"t2","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "tool_input":{"command":"rm -rf build"},"cwd":"/tmp","model":"gpt-6-astra","permission_mode":"default",
         "transcript_path":"\(transcript.path)"}
        """

        #expect((HookEvent(hookInput: Data(stdin.utf8)) != nil) == asks)
    }

    private func codexRollout(reviewers: [String?]) -> String {
        reviewers.enumerated().map { turn, reviewer in
            let field = reviewer.map { #","approvals_reviewer":"\#($0)""# } ?? ""
            return """
            {"timestamp":"2026-11-07T05:33:41.571Z","type":"turn_context","payload":{"turn_id":"t\(turn)",\
            "cwd":"/tmp","approval_policy":"on-request"\(field),"model":"gpt-6-astra"}}
            {"timestamp":"2026-11-07T05:33:42.100Z","type":"response_item","payload":{"type":"function_call",\
            "name":"exec_command","arguments":"{\\"cmd\\":\\"grep approvals_reviewer ~/.codex/config.toml\\"}"}}
            """
        }.joined(separator: "\n") + "\n"
    }

    @Test func inputWithoutSessionIsIgnored() {
        #expect(HookEvent(hookInput: Data("{\"hook_event_name\":\"Stop\"}".utf8)) == nil)
    }
}
