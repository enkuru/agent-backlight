import AgentBacklightCore
import SwiftUI

/// The menu bar panel, laid out like the mock-up on the design page.
struct PanelView: View {
    let light: LightController
    let hooks: HooksModel

    @State private var tab = AgentState.thinking
    @State private var showsImport = false
    @State private var specText = ""
    @State private var importMessage: String?

    private typealias Limits = SignalSettings.Limits

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = light.backlightError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Signal", selection: $tab) {
                ForEach([AgentState.thinking, .question, .normal], id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .thinking: thinkingFields
            case .question: questionFields
            case .normal: normalFields
            }

            Button { light.play(tab) } label: {
                Text("Play \(tab.title) on keyboard").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(light.backlightError != nil)

            Divider()
            hooksRow
            if showsImport { importBox }
            Divider()
            HStack {
                Button("Clear sessions") { light.clearSessions() }
                    .disabled(light.tracker.sessions.isEmpty)
                    .help("Ends every signal now, for example after you pressed Esc in Claude Code")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Agent Backlight").fontWeight(.semibold)
                HStack(spacing: 6) {
                    Circle().fill(light.enabled ? light.displayedState.color : Color.secondary).frame(width: 7, height: 7)
                    Text(light.statusText).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Signals on", isOn: Binding(get: { light.enabled }, set: { light.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Turn the signals off for meetings or screen sharing")
        }
    }

    private var thinkingFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            choice("Shape", setting(\.thinking.shape), WaveShape.allCases) { $0.rawValue.capitalized }
            slider("One breath", setting(\.thinking.periodMs), Limits.periodMs, step: 100, format: Self.seconds)
            slider("Lowest", low(\.thinking.lowPct, high: \.thinking.highPct), Limits.percent, step: 1, format: Self.percent)
            slider("Highest", high(\.thinking.highPct, low: \.thinking.lowPct), Limits.percent, step: 1, format: Self.percent)
        }
    }

    private var questionFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            choice("Flashes per burst", setting(\.question.flashes), Array(Limits.flashes)) { "\($0)" }
            slider("On", setting(\.question.onMs), Limits.flashMs, step: 10, format: Self.milliseconds)
            slider("Off between flashes", setting(\.question.offMs), Limits.flashMs, step: 10, format: Self.milliseconds)
            slider("Rest after burst", setting(\.question.pauseMs), Limits.pauseMs, step: 50, format: Self.milliseconds)
            slider("Off level", low(\.question.lowPct, high: \.question.highPct), Limits.percent, step: 1, format: Self.percent)
            slider("On level", high(\.question.highPct, low: \.question.lowPct), Limits.percent, step: 1, format: Self.percent)
            let flashes = light.settings.question.maxFlashesInOneSecond
            if flashes > SignalSettings.maxSafeFlashesInOneSecond {
                Label("Up to \(flashes) flashes in one second. Keep it at 3 or fewer: lengthen on/off time or use fewer flashes.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var normalFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your level").foregroundStyle(.secondary)
                Spacer()
                Text("From macOS")
            }
            .font(.callout)
            slider("Fade back after Stop", setting(\.normal.fadeBackMs), Limits.fadeBackMs, step: 50, format: Self.milliseconds)
        }
    }

    private var hooksRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(hooks.status == .installed ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(hooksText)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button(showsImport ? "Hide import" : "Import spec…") {
                    showsImport.toggle()
                    importMessage = nil
                }
                .buttonStyle(.link)
            }
            .font(.caption)
            HStack {
                switch hooks.status {
                case .installed:
                    Button("Remove hooks") { hooks.remove() }
                case .notInstalled, .otherCopy:
                    Button(hooks.status == .otherCopy ? "Install for this copy" : "Install hooks") { hooks.install() }
                case .unreadable:
                    EmptyView()
                }
            }
            .controlSize(.small)
            if let problem = hooks.problem {
                Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hooksText: String {
        switch hooks.status {
        case .installed: "Claude Code hooks installed"
        case .notInstalled: "Claude Code hooks not installed"
        case .otherCopy: "Hooks point to another copy of the app"
        case .unreadable(let reason): reason
        }
    }

    private var importBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste the spec from the design page").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $specText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 72)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
            HStack {
                if let importMessage {
                    Text(importMessage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import") { importSpec() }.controlSize(.small)
            }
        }
    }

    // MARK: - Controls

    private func slider(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int, format: (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(format(value.wrappedValue)).font(.system(.callout, design: .monospaced))
            }
            .font(.callout)
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .controlSize(.small)
            .accessibilityLabel(label)
            .accessibilityValue(format(value.wrappedValue))
        }
    }

    private func choice<Value: Hashable>(_ label: String, _ value: Binding<Value>, _ options: [Value], title: @escaping (Value) -> String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.callout)
            Spacer()
            Picker(label, selection: value) {
                ForEach(options, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func setting<Value>(_ path: WritableKeyPath<SignalSettings, Value>) -> Binding<Value> {
        Binding(get: { light.settings[keyPath: path] }, set: { value in light.update { $0[keyPath: path] = value } })
    }

    /// A lowest level that pushes the highest level up with it.
    private func low(_ path: WritableKeyPath<SignalSettings, Int>, high: WritableKeyPath<SignalSettings, Int>) -> Binding<Int> {
        Binding(get: { light.settings[keyPath: path] }, set: { value in
            light.update {
                $0[keyPath: path] = value
                $0[keyPath: high] = max($0[keyPath: high], value)
            }
        })
    }

    /// A highest level that pushes the lowest level down with it.
    private func high(_ path: WritableKeyPath<SignalSettings, Int>, low: WritableKeyPath<SignalSettings, Int>) -> Binding<Int> {
        Binding(get: { light.settings[keyPath: path] }, set: { value in
            light.update {
                $0[keyPath: path] = value
                $0[keyPath: low] = min($0[keyPath: low], value)
            }
        })
    }

    private func importSpec() {
        do throws(SpecImportError) {
            try light.importSpec(specText)
            importMessage = "Imported"
        } catch {
            switch error {
            case .notJSON: importMessage = "That isn't JSON. Copy the spec from the design page."
            case .noSignals: importMessage = "No thinking, question or normal values found."
            }
        }
    }

    private static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }
    private static func milliseconds(_ ms: Int) -> String { "\(ms) ms" }
    private static func percent(_ value: Int) -> String { "\(value)%" }
}

private extension AgentState {
    var color: Color {
        switch self {
        case .normal: .secondary
        case .thinking: .blue
        case .question: .orange
        }
    }
}
