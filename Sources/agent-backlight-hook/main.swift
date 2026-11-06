import AgentBacklightCore
import Foundation

// Claude Code runs this for each hook event with the event as JSON on stdin. It forwards the event to the
// menu bar app and prints nothing, so Claude Code carries on unchanged. It always exits 0: a missing app
// or bad input must never block a session.
let input = FileHandle.standardInput.readDataToEndOfFile()
if let event = HookEvent(hookInput: input) {
    DistributedNotificationCenter.default().postNotificationName(
        HookChannel.notification,
        object: nil,
        userInfo: HookChannel.userInfo(for: event),
        deliverImmediately: true
    )
}
exit(0)
