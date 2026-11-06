import Foundation

/// One Claude Code hook call, forwarded from the hook command to the app.
public struct HookEvent: Equatable, Sendable {
    public var sessionID: String
    public var name: String
    public var toolName: String?
    public var notificationType: String?

    public init(sessionID: String, name: String, toolName: String? = nil, notificationType: String? = nil) {
        self.sessionID = sessionID
        self.name = name
        self.toolName = toolName
        self.notificationType = notificationType
    }
}

/// How the hook command reaches the app: a distributed notification carrying the event as strings.
public enum HookChannel {
    public static let notification = Notification.Name("local.agentbacklight.hook-event")

    private enum Key {
        static let session = "session"
        static let event = "event"
        static let tool = "tool"
        static let notificationType = "notificationType"
    }

    public static func userInfo(for event: HookEvent) -> [String: String] {
        var info = [Key.session: event.sessionID, Key.event: event.name]
        info[Key.tool] = event.toolName
        info[Key.notificationType] = event.notificationType
        return info
    }

    public static func event(from userInfo: [AnyHashable: Any]) -> HookEvent? {
        guard let session = userInfo[Key.session] as? String, let name = userInfo[Key.event] as? String else { return nil }
        return HookEvent(
            sessionID: session,
            name: name,
            toolName: userInfo[Key.tool] as? String,
            notificationType: userInfo[Key.notificationType] as? String
        )
    }
}

extension HookEvent {
    /// Reads the JSON Claude Code writes to a hook command's stdin.
    public init?(hookInput data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let session = json["session_id"] as? String,
              let name = json["hook_event_name"] as? String else { return nil }
        self.init(
            sessionID: session,
            name: name,
            toolName: json["tool_name"] as? String,
            notificationType: json["notification_type"] as? String
        )
    }
}
