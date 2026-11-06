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

    @Test func inputWithoutSessionIsIgnored() {
        #expect(HookEvent(hookInput: Data("{\"hook_event_name\":\"Stop\"}".utf8)) == nil)
    }
}
