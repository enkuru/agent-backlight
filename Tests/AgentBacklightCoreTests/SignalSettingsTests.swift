import Foundation
import Testing
@testable import AgentBacklightCore

struct SignalSettingsTests {
    @Test func breathRisesFromLowestToHighestAtFortyPercent() {
        let thinking = SignalSettings.defaults.thinking
        #expect(abs(thinking.level(at: 0) - 0.15) < 1e-9)
        #expect(abs(thinking.level(at: 1200) - 1.0) < 1e-9)
        #expect(abs(thinking.level(at: 3000) - 0.15) < 1e-9)
    }

    @Test func flashCountLooksAtAnyOneSecondWindow() {
        var question = SignalSettings.defaults.question
        #expect(question.maxFlashesInOneSecond == 1)

        question.flashes = 3
        question.onMs = 60
        question.offMs = 60
        #expect(question.maxFlashesInOneSecond == 3)

        question.pauseMs = 0
        #expect(question.maxFlashesInOneSecond == 9)

        question.lowPct = 95
        #expect(question.maxFlashesInOneSecond == 0)
    }

    @Test func importReadsTheDesignSpecAndClampsToThePanelRanges() throws {
        let spec = """
        {
          "thinking": { "shape": "sine", "periodMs": 9000, "lowPct": 40, "highPct": 30, "enterFadeMs": 250 },
          "question": { "flashes": 2, "onMs": 10, "offMs": true, "pauseMs": 1200.4 },
          "normal": { "restore": "saved level and auto-brightness", "fadeBackMs": 600 },
          "menuBarIcon": { "style": "keycap" }
        }
        """
        let result = try SignalSettings.defaults.importing(spec: Data(spec.utf8))

        #expect(result.thinking == .init(shape: .sine, periodMs: 6000, lowPct: 40, highPct: 40))
        #expect(result.question.flashes == 2)
        #expect(result.question.onMs == 60)
        #expect(result.question.offMs == SignalSettings.defaults.question.offMs)
        #expect(result.question.pauseMs == 1200)
        #expect(result.question.highPct == SignalSettings.defaults.question.highPct)
        #expect(result.normal.fadeBackMs == 600)
    }

    @Test func importRejectsTextWithoutSignals() {
        #expect(throws: SpecImportError.notJSON) { try SignalSettings.defaults.importing(spec: Data("hello".utf8)) }
        #expect(throws: SpecImportError.noSignals) { try SignalSettings.defaults.importing(spec: Data("{\"a\":1}".utf8)) }
    }
}
