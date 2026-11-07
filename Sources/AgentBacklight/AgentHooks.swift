import AgentBacklightCore
import Foundation

/// Reads and writes this app's hooks in one agent's hook file. Every write keeps a backup of the file
/// as it was, and writes through a symlink to the real file.
struct AgentHooks: Sendable {
    enum Status: Equatable {
        case installed
        case notInstalled
        /// Installed for a copy of the app in another folder, or by an older version that used fewer events.
        case outdated
        case unreadable(String)
        /// The agent's folder doesn't exist, so it isn't used on this Mac.
        case agentNotFound
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static let claudeCode = AgentHooks(
        agent: "Claude Code", folder: ".claude", fileName: "settings.json", installer: .claudeCode,
        pickUp: "Restart open Claude Code sessions to pick up the hooks."
    )
    static let codex = AgentHooks(
        agent: "Codex", folder: ".codex", fileName: "hooks.json", installer: .codex,
        pickUp: "Codex skips new hooks until you trust them: when it asks, choose Trust all and continue, or review them with /hooks."
    )

    let agent: String
    let installer: HookInstaller
    /// What to do after installing so the agent runs the hooks.
    let pickUp: String
    let displayPath: String
    private let folder: URL
    private let file: URL

    private init(agent: String, folder: String, fileName: String, installer: HookInstaller, pickUp: String) {
        self.agent = agent
        self.installer = installer
        self.pickUp = pickUp
        self.displayPath = "~/\(folder)/\(fileName)"
        self.folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: folder)
        self.file = self.folder.appending(path: fileName).resolvingSymlinksInPath()
    }

    /// The hook command inside this app bundle.
    let command = Bundle.main.bundleURL.appending(path: "Contents/MacOS/\(HookInstaller.commandName)").path(percentEncoded: false)

    var backupPath: String { file.path(percentEncoded: false) + ".agent-backlight.bak" }

    func status() -> Status {
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return .agentNotFound }
        do {
            let settings = try read()
            if installer.isInstalled(command: command, in: settings) { return .installed }
            return installer.hasAnyInstall(in: settings) ? .outdated : .notInstalled
        } catch {
            return .unreadable(error.description)
        }
    }

    func install() throws(Failure) {
        guard command.allSatisfy({ $0.isLetter || $0.isNumber || "/._-".contains($0) }) else {
            throw Failure(description: "\(agent) runs the hook through a shell, so the app's path can't contain spaces or symbols. Move AgentBacklight.app to ~/Applications and try again.")
        }
        guard FileManager.default.isExecutableFile(atPath: command) else {
            throw Failure(description: "The hook command is missing from the app: \(command)")
        }
        try write(installer.installing(command: command, into: read()))
    }

    func remove() throws(Failure) {
        try write(installer.removing(from: read()))
    }

    private func read() throws(Failure) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return [:] }
        do {
            let data = try Data(contentsOf: file)
            if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
            guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure(description: "\(displayPath) is not a JSON object")
            }
            return settings
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure(description: "Can't read \(displayPath): \(error.localizedDescription)")
        }
    }

    private func write(_ settings: [String: Any]) throws(Failure) {
        let manager = FileManager.default
        let path = file.path(percentEncoded: false)
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let permissions = (try? manager.attributesOfItem(atPath: path))?[.posixPermissions]
            if manager.fileExists(atPath: path) {
                try? manager.removeItem(atPath: backupPath)
                try manager.copyItem(atPath: path, toPath: backupPath)
            } else {
                try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try (data + Data("\n".utf8)).write(to: file, options: .atomic)
            if let permissions {
                try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            }
        } catch {
            throw Failure(description: "Can't write \(displayPath): \(error.localizedDescription)")
        }
    }
}
