import Foundation

/// The rollout file Codex writes for a session. Hooks get its path as `transcript_path`.
enum CodexTranscript {
    /// How much of the file's end is read. Codex writes a `turn_context` record as each turn starts, and the
    /// largest turn seen ran about 300 KB past it.
    static let tailBytes: UInt64 = 4 << 20

    /// Who answers the session's permission requests, `user` or `auto_review`, from the latest `turn_context`
    /// record. Nil when the file can't be read, no record is in reach, or the record has no reviewer.
    static func approvalsReviewer(at path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(),
              (try? file.seek(toOffset: size - min(size, tailBytes))) != nil,
              let tail = try? file.readToEnd(),
              let marker = tail.range(of: Data(#""type":"turn_context""#.utf8), options: .backwards) else { return nil }
        let newline = UInt8(ascii: "\n")
        let start = tail[..<marker.lowerBound].lastIndex(of: newline).map { $0 + 1 } ?? tail.startIndex
        let end = tail[marker.upperBound...].firstIndex(of: newline) ?? tail.endIndex
        let record = (try? JSONSerialization.jsonObject(with: tail[start..<end])) as? [String: Any]
        return (record?["payload"] as? [String: Any])?["approvals_reviewer"] as? String
    }
}
