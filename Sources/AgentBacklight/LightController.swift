import AgentBacklightCore
import AppKit
import Observation

/// Owns the keyboard light: follows the Claude Code sessions, runs the signal frames, and saves the settings.
/// While a signal runs it holds the light; when the signal ends it fades back and returns the light to macOS.
@MainActor @Observable
final class LightController {
    /// A signal played from the panel, shown instead of the sessions until `until`.
    struct Playback {
        /// The tab that was played.
        let label: AgentState
        let state: AgentState
        let until: Double
    }

    /// The keyboard state saved while the app holds the light, so a crash can't leave the keyboard blinking.
    private struct Takeover: Codable {
        let level: Double
    }

    private enum Key {
        static let settings = "signalSettings"
        static let enabled = "signalsEnabled"
        static let takeover = "takeover"
    }

    static let playMs = 5000.0
    /// Play on the Normal tab shows the wave this long, then the fade back.
    static let playNormalMs = 1500.0
    /// Smaller changes are not sent to the keyboard.
    private static let minimumStep = 0.002

    private(set) var settings: SignalSettings
    private(set) var enabled: Bool
    private(set) var tracker = SessionTracker()
    private(set) var playback: Playback?
    private(set) var playSecondsLeft = 0
    let backlightError: String?

    @ObservationIgnored var onIcon: ((KeycapIcon.Frame) -> Void)?
    @ObservationIgnored private let backlight: KeyboardBacklight?
    @ObservationIgnored private let log: EventLog
    @ObservationIgnored private var conductor: SignalConductor
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastWritten: Double?
    @ObservationIgnored private var loggedState = AgentState.normal

    init(log: EventLog) {
        self.log = log
        do {
            backlight = try KeyboardBacklight()
            backlightError = nil
        } catch {
            backlight = nil
            backlightError = error.description
            log.write("keyboard backlight unavailable: \(error.description)")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: Key.settings).flatMap { try? JSONDecoder().decode(SignalSettings.self, from: $0) }
        settings = saved ?? .defaults
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        conductor = SignalConductor(settings: saved ?? .defaults)
        restoreAfterUncleanExit()
    }

    var statusText: String {
        if backlightError != nil { return "Keyboard backlight unavailable" }
        if !enabled { return "Signals off · keyboard is yours" }
        if let playback { return "Playing \(playback.label.title) · \(playSecondsLeft) s left" }
        let count = tracker.sessions.count
        let sessions = count == 0 ? "no active sessions" : count == 1 ? "1 session" : "\(count) sessions"
        return "\(tracker.state.title) · \(sessions)"
    }

    /// What the status dot and icon describe: the played signal, else the sessions.
    var displayedState: AgentState {
        guard enabled else { return .normal }
        return playback?.label ?? tracker.state
    }

    func start() { tick() }

    func receive(_ event: HookEvent) {
        tracker.apply(event)
        let detail = [event.toolName, event.notificationType].compactMap(\.self).joined(separator: " ")
        log.write("hook \(event.name)\(detail.isEmpty ? "" : " " + detail) session \(event.sessionID.prefix(8)) -> \(tracker.state.title)")
        tick()
    }

    func clearSessions() {
        tracker.clear()
        log.write("sessions cleared")
        tick()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Key.enabled)
        if !on { playback = nil }
        log.write("signals \(on ? "on" : "off")")
        tick()
    }

    /// Plays one tab's signal on the keyboard. Normal shows the wave briefly, then the fade back.
    func play(_ tab: AgentState) {
        if !enabled { setEnabled(true) }
        let now = Self.now()
        playback = tab == .normal
            ? Playback(label: .normal, state: .thinking, until: now + Self.playNormalMs)
            : Playback(label: tab, state: tab, until: now + Self.playMs)
        tick()
    }

    func update(_ change: (inout SignalSettings) -> Void) {
        var next = settings
        change(&next)
        apply(next)
    }

    func importSpec(_ text: String) throws(SpecImportError) {
        apply(try settings.importing(spec: Data(text.utf8)))
        log.write("spec imported")
    }

    /// Gives the light back to macOS at once. Called when the app quits.
    func shutdown() {
        guard conductor.mode != .idle else { return }
        timer?.invalidate()
        timer = nil
        handBack(at: conductor.userLevel)
    }

    // MARK: - Frames

    private func apply(_ next: SignalSettings) {
        guard next != settings else { return }
        settings = next
        conductor.settings = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Key.settings)
        }
        tick()
    }

    private func tick() {
        let now = Self.now()
        if let playback, now >= playback.until { self.playback = nil }
        let target = playback?.state ?? (enabled ? tracker.state : .normal)
        conductor.show(target, at: now, takeOver: takeOver)
        switch conductor.frame(at: now) {
        case .hold: break
        case .level(let level): write(level)
        case .release(let level): handBack(at: level)
        }
        publish(at: now)
        if conductor.mode == .idle { stopTimer() } else { startTimer() }
    }

    private func publish(at now: Double) {
        let secondsLeft = playback.map { max(1, Int(($0.until - now) / 1000 + 0.999)) } ?? 0
        if secondsLeft != playSecondsLeft { playSecondsLeft = secondsLeft }
        if conductor.shownState != loggedState {
            loggedState = conductor.shownState
            log.write("light \(loggedState.title)")
        }
        onIcon?(iconFrame(at: now))
    }

    private func iconFrame(at now: Double) -> KeycapIcon.Frame {
        guard enabled else { return .off }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let elapsed = conductor.elapsed(at: now)
        switch conductor.shownState {
        case .normal: return .normal
        case .thinking: return .thinking(phase: still ? 0.25 : settings.thinking.phase(at: elapsed))
        case .question: return .question(lit: still || settings.question.isLit(at: elapsed))
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Keyboard

    private func write(_ level: Double) {
        guard let backlight else { return }
        if let lastWritten, abs(lastWritten - level) < Self.minimumStep { return }
        backlight.set(level)
        lastWritten = level
    }

    /// Called by the conductor while it changes, so it must not read `conductor`. Returns the user's level.
    private func takeOver() -> Double {
        guard let backlight else { return 0 }
        let record = Takeover(level: backlight.takeOver())
        lastWritten = nil
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Key.takeover)
        }
        log.write("took the keyboard at \(Self.percent(record.level))")
        return record.level
    }

    private func handBack(at level: Double) {
        guard let backlight else { return }
        backlight.handBack(level: level)
        UserDefaults.standard.removeObject(forKey: Key.takeover)
        lastWritten = nil
        log.write("handed the keyboard back at \(Self.percent(level))")
    }

    private func restoreAfterUncleanExit() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Key.takeover) else { return }
        defaults.removeObject(forKey: Key.takeover)
        guard let backlight, let record = try? JSONDecoder().decode(Takeover.self, from: data) else { return }
        backlight.handBack(level: record.level)
        log.write("restored the keyboard after an unclean exit: \(Self.percent(record.level))")
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    private static func percent(_ level: Double) -> String { "\(Int((level * 100).rounded()))%" }
}

extension AgentState {
    var title: String {
        switch self {
        case .normal: "Normal"
        case .thinking: "Thinking"
        case .question: "Question"
        }
    }
}
