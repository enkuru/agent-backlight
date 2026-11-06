import Foundation

public enum WaveShape: String, Codable, CaseIterable, Sendable {
    case sine
    case breath
    case triangle
}

/// The tunable signals, with the same names, defaults and ranges as the design page.
public struct SignalSettings: Codable, Equatable, Sendable {
    public struct Thinking: Codable, Equatable, Sendable {
        public var shape: WaveShape
        public var periodMs: Int
        public var lowPct: Int
        public var highPct: Int
    }

    public struct Question: Codable, Equatable, Sendable {
        public var flashes: Int
        public var onMs: Int
        public var offMs: Int
        public var pauseMs: Int
        public var lowPct: Int
        public var highPct: Int
    }

    public struct Normal: Codable, Equatable, Sendable {
        public var fadeBackMs: Int
    }

    public var thinking: Thinking
    public var question: Question
    public var normal: Normal

    public static let defaults = SignalSettings(
        thinking: Thinking(shape: .breath, periodMs: 3000, lowPct: 15, highPct: 100),
        question: Question(flashes: 1, onMs: 150, offMs: 200, pauseMs: 1000, lowPct: 0, highPct: 100),
        normal: Normal(fadeBackMs: 400)
    )

    /// Slider ranges, shared by the panel and the spec import.
    public enum Limits {
        public static let periodMs = 1000...6000
        public static let percent = 0...100
        public static let flashes = 1...3
        public static let flashMs = 60...600
        public static let pauseMs = 0...3000
        public static let fadeBackMs = 0...1500
    }

    /// More flashes than this in one second can trigger seizures in photosensitive people (WCAG 2.3.1).
    public static let maxSafeFlashesInOneSecond = 3
}

extension SignalSettings.Thinking {
    /// Brightness from 0 to 1, `ms` after the wave started.
    public func level(at ms: Double) -> Double {
        let phase = phase(at: ms)
        let rise: Double
        switch shape {
        case .sine:
            rise = 0.5 - 0.5 * cos(2 * .pi * phase)
        case .breath:
            rise = phase < 0.4
                ? 0.5 - 0.5 * cos(.pi * phase / 0.4)
                : 0.5 + 0.5 * cos(.pi * (phase - 0.4) / 0.6)
        case .triangle:
            rise = phase < 0.5 ? phase * 2 : 2 - phase * 2
        }
        return (Double(lowPct) + Double(highPct - lowPct) * rise) / 100
    }

    /// Position within one breath, from 0 up to 1.
    public func phase(at ms: Double) -> Double { fraction(ms, of: Double(periodMs)) }
}

extension SignalSettings.Question {
    public var cycleMs: Int { flashes * (onMs + offMs) + pauseMs }

    public func isLit(at ms: Double) -> Bool {
        let t = fraction(ms, of: Double(cycleMs)) * Double(cycleMs)
        guard t < Double(flashes * (onMs + offMs)) else { return false }
        return t.truncatingRemainder(dividingBy: Double(onMs + offMs)) < Double(onMs)
    }

    /// Brightness from 0 to 1, `ms` after the blinking started.
    public func level(at ms: Double) -> Double { Double(isLit(at: ms) ? highPct : lowPct) / 100 }

    /// The most flashes that start within any one second. A swing under 10 points does not count as flashing.
    public var maxFlashesInOneSecond: Int {
        guard highPct - lowPct >= 10 else { return 0 }
        let cycles = 2000 / cycleMs + 2
        let onsets = (0..<cycles).flatMap { cycle in
            (0..<flashes).map { cycle * cycleMs + $0 * (onMs + offMs) }
        }
        return onsets.map { start in onsets.count { $0 >= start && $0 < start + 1000 } }.max() ?? 0
    }
}

public enum SpecImportError: Error, Equatable {
    case notJSON
    case noSignals
}

extension SignalSettings {
    /// Reads the spec copied from the design page. Missing or invalid fields keep their current value;
    /// numbers are clamped to the panel's ranges, and a low level above its high level raises the high level.
    public func importing(spec data: Data) throws(SpecImportError) -> SignalSettings {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw .notJSON }
        let thinkingSpec = root["thinking"] as? [String: Any]
        let questionSpec = root["question"] as? [String: Any]
        let normalSpec = root["normal"] as? [String: Any]
        guard thinkingSpec != nil || questionSpec != nil || normalSpec != nil else { throw .noSignals }

        var result = self
        if let shape = (thinkingSpec?["shape"] as? String).flatMap(WaveShape.init(rawValue:)) {
            result.thinking.shape = shape
        }
        result.thinking.periodMs = clamped(thinkingSpec?["periodMs"], Limits.periodMs) ?? result.thinking.periodMs
        result.thinking.lowPct = clamped(thinkingSpec?["lowPct"], Limits.percent) ?? result.thinking.lowPct
        result.thinking.highPct = clamped(thinkingSpec?["highPct"], Limits.percent) ?? result.thinking.highPct
        result.question.flashes = clamped(questionSpec?["flashes"], Limits.flashes) ?? result.question.flashes
        result.question.onMs = clamped(questionSpec?["onMs"], Limits.flashMs) ?? result.question.onMs
        result.question.offMs = clamped(questionSpec?["offMs"], Limits.flashMs) ?? result.question.offMs
        result.question.pauseMs = clamped(questionSpec?["pauseMs"], Limits.pauseMs) ?? result.question.pauseMs
        result.question.lowPct = clamped(questionSpec?["lowPct"], Limits.percent) ?? result.question.lowPct
        result.question.highPct = clamped(questionSpec?["highPct"], Limits.percent) ?? result.question.highPct
        result.normal.fadeBackMs = clamped(normalSpec?["fadeBackMs"], Limits.fadeBackMs) ?? result.normal.fadeBackMs

        result.thinking.highPct = max(result.thinking.highPct, result.thinking.lowPct)
        result.question.highPct = max(result.question.highPct, result.question.lowPct)
        return result
    }
}

private func fraction(_ ms: Double, of period: Double) -> Double {
    let value = ms.truncatingRemainder(dividingBy: period) / period
    return value < 0 ? value + 1 : value
}

private func clamped(_ value: Any?, _ range: ClosedRange<Int>) -> Int? {
    // JSON booleans also arrive as NSNumber.
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
        return nil
    }
    return min(range.upperBound, max(range.lowerBound, Int(number.doubleValue.rounded())))
}
