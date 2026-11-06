import Foundation

/// One line per hook event and light change in ~/Library/Logs/AgentBacklight.log, so the timing of real
/// Claude Code sessions can be checked afterwards. Keeps about the last 256 KB.
@MainActor
final class EventLog {
    private let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/AgentBacklight.log")
    private let limit: UInt64 = 256 * 1024
    private let clock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    func write(_ message: String) {
        let line = Data("\(clock.string(from: Date())) \(message)\n".utf8)
        guard let file = try? FileHandle(forWritingTo: url) else {
            try? line.write(to: url)
            return
        }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return }
        if size > limit {
            keepNewestHalf(of: file)
        }
        try? file.write(contentsOf: line)
    }

    private func keepNewestHalf(of file: FileHandle) {
        guard (try? file.seek(toOffset: limit / 2)) != nil,
              let tail = try? file.readToEnd(),
              let firstLineEnd = tail.firstIndex(of: UInt8(ascii: "\n")) else { return }
        try? file.truncate(atOffset: 0)
        try? file.write(contentsOf: tail[tail.index(after: firstLineEnd)...])
    }
}
