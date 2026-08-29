import Foundation
import SwiftUI

struct SaveCurrentLookSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    let onSave: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceL) {
            UtilitySheetHeader(
                title: "Save Current Look",
                subtitle: "Save the selected bulb's color or color temperature and brightness as a reusable static mode. Power and active flows are not included.",
                systemImage: "camera.aperture"
            )

            if let device = state.selectedDevice, let look = state.currentLightLook {
                HStack(spacing: 12) {
                    lookPreview(look)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.displayName)
                            .font(.body.weight(.medium))
                        Text(look.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(state.connectionReady ? "Current look" : "Last known look")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                .padding(12)
                .yeelightGlass(.tinted(lookAccentColor(look)))
            }

            if state.selectedDeviceIsFlowing {
                Label("A flow is running. This saves the last reported static look, not the flow.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Mode name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
                .onSubmit(save)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
                    HStack(spacing: YeelightDesignTokens.spaceS) {
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)

                        Button("Save Mode") {
                            save()
                        }
                        .yeelightPrimaryButtonStyle()
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedName.isEmpty || state.currentLightLook == nil)
                    }
                }
            }
        }
        .padding(YeelightDesignTokens.spaceXL)
        .frame(width: 440)
        .frame(minHeight: 270)
        .onAppear {
            nameIsFocused = true
        }
    }

    @ViewBuilder
    private func lookPreview(_ look: CurrentLightLook) -> some View {
        if let rgb = look.swatchRGB {
            Circle()
                .fill(Color(yeelightRGB: rgb))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        } else {
            Image(systemName: look.symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lookAccentColor(_ look: CurrentLightLook) -> Color {
        look.swatchRGB.map { Color(yeelightRGB: $0) } ?? YeelightDesignTokens.accent
    }

    private func save() {
        guard !trimmedName.isEmpty, onSave(trimmedName) else {
            return
        }
        dismiss()
    }
}

struct NewFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var repeatsIndefinitely = true
    @State private var cycles = 1
    @State private var stopAction: FlowStopAction = .recover
    @State private var steps: [FlowStep] = Self.defaultSteps
    @State private var selectedStepID: UUID?
    @FocusState private var nameIsFocused: Bool

    let onSave: (String, ColorFlow) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceL) {
            UtilitySheetHeader(
                title: "New Flow",
                subtitle: "Create an ordered sequence that runs directly on the bulb without keeping YeelightBar open.",
                systemImage: "waveform.badge.plus"
            )

            playbackFields

            HSplitView {
                stepList
                    .frame(minWidth: 220, idealWidth: 235, maxWidth: 270)

                Group {
                    if let selectedStepBinding {
                        FlowStepDetailEditor(step: selectedStepBinding)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "list.number")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Select a Step")
                                .font(.headline)
                            Text("Choose a flow step to edit its settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text("\(steps.count) \(steps.count == 1 ? "step" : "steps")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
                    HStack(spacing: YeelightDesignTokens.spaceS) {
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)

                        Button("Create Flow") {
                            save()
                        }
                        .yeelightPrimaryButtonStyle()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                    }
                }
            }
        }
        .padding(YeelightDesignTokens.spaceXL)
        .frame(width: 680, height: 560)
        .onAppear {
            selectedStepID = steps.first?.id
            nameIsFocused = true
        }
        .onChange(of: steps.count) {
            cycles = min(cycles, maximumCycles)
        }
    }

    private var playbackFields: some View {
        GlassSection("Playback") {
            Grid(alignment: .leading, horizontalSpacing: YeelightDesignTokens.spaceM, verticalSpacing: YeelightDesignTokens.spaceS) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Flow name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameIsFocused)
                }

                GridRow {
                    Text("Playback")
                        .foregroundStyle(.secondary)
                    HStack(spacing: YeelightDesignTokens.spaceM) {
                        Toggle("Repeat indefinitely", isOn: $repeatsIndefinitely)

                        if !repeatsIndefinitely {
                            Stepper(value: $cycles, in: 1...maximumCycles) {
                                Text("\(cycles) \(cycles == 1 ? "cycle" : "cycles")")
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                GridRow {
                    Text("When Finished")
                        .foregroundStyle(.secondary)
                    Picker("When Finished", selection: $stopAction) {
                        ForEach(FlowStopAction.allCases) { action in
                            Text(action.editorTitle).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    private var stepList: some View {
        VStack(spacing: 8) {
            List(selection: $selectedStepID) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    FlowStepListRow(index: index, step: step)
                        .tag(step.id)
                }
                .onMove(perform: moveSteps)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            HStack(spacing: 8) {
                Menu {
                    Button {
                        addStep(.color(0xFFFFFF, brightness: 80, duration: 500))
                    } label: {
                        Label("Color", systemImage: "paintpalette")
                    }

                    Button {
                        addStep(.colorTemperature(4000, brightness: 80, duration: 500))
                    } label: {
                        Label("Temperature", systemImage: "thermometer.sun")
                    }

                    Button {
                        addStep(.sleep(1000))
                    } label: {
                        Label("Hold", systemImage: "pause")
                    }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }

                Spacer()

                Button(role: .destructive) {
                    deleteSelectedStep()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(steps.count <= 1 || selectedStepID == nil)
                .help("Delete selected step")
            }
        }
    }

    private var selectedStepBinding: Binding<FlowStep>? {
        guard let selectedStepID, let index = steps.firstIndex(where: { $0.id == selectedStepID }) else {
            return nil
        }
        return $steps[index]
    }

    private var maximumCycles: Int {
        max(1, min(100, ColorFlow.maximumCount / max(steps.count, 1)))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var protocolCount: Int? {
        repeatsIndefinitely ? 0 : ColorFlow.count(forCycles: cycles, stepCount: steps.count)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !steps.isEmpty && protocolCount != nil
    }

    private func addStep(_ step: FlowStep) {
        steps.append(step)
        selectedStepID = step.id
    }

    private func deleteSelectedStep() {
        guard steps.count > 1,
              let selectedStepID,
              let index = steps.firstIndex(where: { $0.id == selectedStepID }) else {
            return
        }

        steps.remove(at: index)
        self.selectedStepID = steps[min(index, steps.count - 1)].id
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        guard let protocolCount else {
            return
        }

        let flow = ColorFlow(count: protocolCount, stopAction: stopAction, steps: steps)
        guard onSave(trimmedName, flow) else {
            return
        }
        dismiss()
    }

    private static let defaultSteps: [FlowStep] = [
        .color(0xFF0000, brightness: 80, duration: 800),
        .color(0x00FF00, brightness: 80, duration: 800),
        .color(0x0000FF, brightness: 80, duration: 800)
    ]
}

private struct FlowStepListRow: View {
    let index: Int
    let step: FlowStep

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            stepIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(step.mode.editorTitle)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.mode {
        case .color:
            Circle()
                .fill(Color(yeelightRGB: step.rgb))
                .frame(width: 18, height: 18)
                .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }
        case .colorTemperature:
            Image(systemName: "thermometer.sun")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        case .sleep:
            Image(systemName: "pause.fill")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private var detail: String {
        let duration = formattedMilliseconds(step.duration)
        switch step.mode {
        case .color:
            return "#\(String(format: "%06X", step.rgb)) · \(duration) · \(brightnessText)"
        case .colorTemperature:
            return "\(step.colorTemperature)K · \(duration) · \(brightnessText)"
        case .sleep:
            return duration
        }
    }

    private var brightnessText: String {
        step.brightness.map { "\($0)%" } ?? "current brightness"
    }
}

private struct FlowStepDetailEditor: View {
    @Binding var step: FlowStep

    var body: some View {
        Form {
            Picker("Step Type", selection: $step.mode) {
                ForEach(FlowStepMode.allCases) { mode in
                    Text(mode.editorTitle).tag(mode)
                }
            }

            Stepper(value: $step.duration, in: 50...600_000, step: 50) {
                LabeledContent("Duration", value: formattedMilliseconds(step.duration))
            }

            switch step.mode {
            case .color:
                ColorPicker("Color", selection: Binding(
                    get: { Color(yeelightRGB: step.rgb) },
                    set: { step.rgb = $0.yeelightRGBValue }
                ), supportsOpacity: false)
                brightnessEditor
            case .colorTemperature:
                Stepper(value: $step.colorTemperature, in: 1700...6500, step: 100) {
                    LabeledContent("Temperature", value: "\(step.colorTemperature)K")
                }
                brightnessEditor
            case .sleep:
                Text("Hold keeps the current visible state for the duration above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var brightnessEditor: some View {
        Toggle("Use current brightness", isOn: Binding(
            get: { step.brightness == nil },
            set: { useCurrent in
                step.brightness = useCurrent ? nil : 80
            }
        ))

        if step.brightness != nil {
            Stepper(value: Binding(
                get: { step.brightness ?? 80 },
                set: { step.brightness = $0.clamped(to: 1...100) }
            ), in: 1...100, step: 1) {
                LabeledContent("Brightness", value: "\(step.brightness ?? 80)%")
            }
        }
    }
}

enum ModeCreator: String, Identifiable {
    case currentLook
    case flow

    var id: String { rawValue }
}

enum ModeLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case staticModes
    case flows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .staticModes: return "Static"
        case .flows: return "Flows"
        }
    }

    var showsStaticModes: Bool { self != .flows }
    var showsFlows: Bool { self != .staticModes }

    var selectionNoun: String {
        switch self {
        case .all: return "mode or flow"
        case .staticModes: return "static mode"
        case .flows: return "flow"
        }
    }
}

extension FlowStopAction {
    var editorTitle: String {
        switch self {
        case .recover: return "Restore previous state"
        case .stay: return "Keep final state"
        case .turnOff: return "Turn off light"
        }
    }
}

extension FlowStepMode {
    var editorTitle: String {
        switch self {
        case .color: return "Color"
        case .colorTemperature: return "Temperature"
        case .sleep: return "Hold"
        }
    }
}

func formattedMilliseconds(_ value: Int) -> String {
    if value < 1000 {
        return "\(value) ms"
    }

    let seconds = Double(value) / 1000
    return String(format: seconds == floor(seconds) ? "%.0f s" : "%.1f s", seconds)
}
