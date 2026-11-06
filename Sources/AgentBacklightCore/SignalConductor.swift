/// Turns the agent state into a backlight level over time: it starts a signal from the current level,
/// switches between signals, and fades back to the user's own level when Claude is done.
/// Times are milliseconds on any steady clock.
public struct SignalConductor: Sendable {
    public enum Mode: Equatable, Sendable {
        case idle
        /// Holds `.thinking` or `.question`; `show(.normal)` fades back instead of entering a normal signal.
        case signal(AgentState, since: Double, from: Double)
        case fadingBack(since: Double, from: Double)
    }

    public enum Output: Equatable, Sendable {
        /// Nothing to set: the backlight belongs to macOS.
        case hold
        case level(Double)
        /// The fade is over: set this level, then hand the backlight back to macOS.
        case release(Double)
    }

    static let entryBlendMs = 250.0

    public var settings: SignalSettings
    public private(set) var mode: Mode = .idle
    /// The user's level when the first signal started; the fade back ends here.
    public private(set) var userLevel = 0.0
    private var lastLevel = 0.0

    public init(settings: SignalSettings) {
        self.settings = settings
    }

    public var shownState: AgentState {
        if case .signal(let state, _, _) = mode { state } else { .normal }
    }

    /// Moves to `state`. When the light leaves the user's control, calls `takeOver` once: it takes the light
    /// from macOS and returns the user's level, which the signal starts from and the fade back ends at.
    public mutating func show(_ state: AgentState, at now: Double, takeOver: () -> Double) {
        switch (mode, state) {
        case (.idle, .normal), (.fadingBack, .normal):
            break
        case (.signal(let shown, _, _), _) where shown == state:
            break
        case (.signal, .normal):
            mode = .fadingBack(since: now, from: lastLevel)
        case (.idle, _):
            let level = takeOver()
            userLevel = level
            lastLevel = level
            mode = .signal(state, since: now, from: level)
        case (.signal, _), (.fadingBack, _):
            mode = .signal(state, since: now, from: lastLevel)
        }
    }

    public mutating func frame(at now: Double) -> Output {
        switch mode {
        case .idle:
            return .hold
        case .signal(let state, let since, let from):
            let t = now - since
            if state == .thinking {
                let wave = settings.thinking.level(at: t)
                lastLevel = from + (wave - from) * min(1, t / Self.entryBlendMs)
            } else {
                lastLevel = settings.question.level(at: t)
            }
        case .fadingBack(let since, let from):
            let duration = Double(settings.normal.fadeBackMs)
            let progress = duration > 0 ? (now - since) / duration : 1
            guard progress < 1 else {
                mode = .idle
                lastLevel = userLevel
                return .release(userLevel)
            }
            lastLevel = from + (userLevel - from) * progress
        }
        return .level(lastLevel)
    }

    /// Time since the current signal started, so the menu bar icon can move in step with the keyboard.
    public func elapsed(at now: Double) -> Double {
        if case .signal(_, let since, _) = mode { now - since } else { 0 }
    }
}
