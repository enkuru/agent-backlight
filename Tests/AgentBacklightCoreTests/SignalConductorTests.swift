import Testing
@testable import AgentBacklightCore

struct SignalConductorTests {
    private let settings = SignalSettings.defaults

    private func level(_ output: SignalConductor.Output) -> Double? {
        if case .level(let value) = output { value } else { nil }
    }

    /// For moves that must leave the light where it is.
    private func noTakeover() -> Double {
        Issue.record("took the light over again")
        return 0.9
    }

    @Test func thinkingTakesOverOnceAndBlendsFromTheLevelTheTakeoverRead() {
        var conductor = SignalConductor(settings: settings)
        var takeovers = 0
        conductor.show(.thinking, at: 0) {
            takeovers += 1
            return 0.6
        }
        #expect(takeovers == 1)
        #expect(level(conductor.frame(at: 0)) == 0.6)

        let wave = settings.thinking.level(at: 1000)
        #expect(abs((level(conductor.frame(at: 1000)) ?? -1) - wave) < 1e-9)

        conductor.show(.question, at: 1000, takeOver: noTakeover)
        #expect(conductor.userLevel == 0.6)
    }

    @Test func questionFollowsTheBurstPattern() {
        var conductor = SignalConductor(settings: settings)
        conductor.show(.question, at: 0) { 0.5 }
        #expect(level(conductor.frame(at: 100)) == 1.0)
        #expect(level(conductor.frame(at: 200)) == 0.0)
        #expect(level(conductor.frame(at: 1000)) == 0.0)
        #expect(level(conductor.frame(at: 1350 + 100)) == 1.0)
    }

    @Test func stopFadesBackToTheLevelTheTakeoverReadThenReleasesOnce() {
        var conductor = SignalConductor(settings: settings)
        conductor.show(.question, at: 0) { 0.4 }
        _ = conductor.frame(at: 50)
        conductor.show(.normal, at: 100, takeOver: noTakeover)

        let halfway = level(conductor.frame(at: 300)) ?? -1
        #expect(abs(halfway - 0.7) < 1e-9)
        #expect(conductor.frame(at: 500) == .release(0.4))
        #expect(conductor.frame(at: 520) == .hold)
        #expect(conductor.mode == .idle)
    }

    @Test func aSignalDuringTheFadeKeepsTheOriginalUserLevel() {
        var conductor = SignalConductor(settings: settings)
        conductor.show(.thinking, at: 0) { 0.3 }
        conductor.show(.normal, at: 1000, takeOver: noTakeover)
        _ = conductor.frame(at: 1100)

        conductor.show(.thinking, at: 1200, takeOver: noTakeover)
        conductor.show(.normal, at: 2000, takeOver: noTakeover)
        #expect(conductor.frame(at: 2400) == .release(0.3))
    }

    @Test func normalWhileIdleChangesNothing() {
        var conductor = SignalConductor(settings: settings)
        conductor.show(.normal, at: 0, takeOver: noTakeover)
        #expect(conductor.frame(at: 10) == .hold)
    }
}
