import AppKit
import Foundation
import SwiftUI

struct ModesSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: ModeLibraryFilter = .all
    @State private var presentedCreator: ModeCreator?
    @State private var confirmReset = false

    var body: some View {
        GeometryReader { proxy in
            adaptiveContent(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $presentedCreator) { creator in
            switch creator {
            case .currentLook:
                SaveCurrentLookSheet { name in
                    guard state.saveCurrentMode(named: name) != nil else {
                        return false
                    }

                    filter = .staticModes
                    return true
                }
                .environmentObject(state)
            case .flow:
                NewFlowSheet { name, flow in
                    guard state.saveCustomFlow(named: name, flow: flow) != nil else {
                        return false
                    }

                    filter = .flows
                    return true
                }
                .environmentObject(state)
            }
        }
        .alert("Reset custom modes and favorites?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                state.resetCustomPresets()
                filter = .all
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All custom modes will be deleted and favorites will be restored to their defaults.")
        }
    }

    @ViewBuilder
    private func adaptiveContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryHeader

            if width >= 600 {
                HSplitView {
                    modeList
                        .frame(minWidth: 340, idealWidth: 430, maxWidth: 560, maxHeight: .infinity)

                    selectedPresetDetail
                        .frame(minWidth: 250, idealWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                modeList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode Library")
                        .font(.headline)

                    Text("Apply, favorite, and manage reusable static looks and color flows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Reset Custom Modes & Favorites…", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!canReset)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More mode library actions")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    filterPicker

                    Spacer(minLength: 4)

                    creationButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    filterPicker
                    creationButtons
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterPicker: some View {
        Picker("Mode type", selection: $filter) {
            ForEach(ModeLibraryFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 190)
    }

    private var creationButtons: some View {
        HStack(spacing: 8) {
            Button {
                presentedCreator = .currentLook
            } label: {
                Label("Save Current Look…", systemImage: "camera.aperture")
            }
            .disabled(state.currentLightLook == nil)
            .help(state.currentLightLook == nil ? "Select a bulb before saving its look" : "Save the selected bulb's static look")

            Button {
                presentedCreator = .flow
            } label: {
                Label("New Flow…", systemImage: "waveform.badge.plus")
            }
            .help("Create a color flow without changing the bulb")
        }
    }

    private var modeList: some View {
        List(selection: selectedPresetBinding) {
            if filter.showsStaticModes {
                Section("Static Modes") {
                    ForEach(staticPresets) { preset in
                        modeRow(preset)
                    }
                }
            }

            if filter.showsFlows {
                Section("Flows") {
                    ForEach(flowPresets) { preset in
                        modeRow(preset)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var selectedPresetDetail: some View {
        if let preset = selectedVisiblePreset {
            ModePresetDetailPane(
                preset: preset,
                isFavorite: state.favoritePresetIDs.contains(preset.id),
                canApply: state.canControlSelectedDevice,
                onToggleFavorite: { state.toggleFavoritePreset(id: preset.id) },
                onApply: { state.applyPreset(id: preset.id) },
                onDelete: { state.removeCustomPreset(id: preset.id) }
            )
        } else {
            ModeLibraryEmptyDetail(filter: filter)
        }
    }

    private var selectedVisiblePreset: LightPreset? {
        visiblePresets.first { $0.id == state.selectedPresetID }
    }

    private var visiblePresets: [LightPreset] {
        switch filter {
        case .all:
            return state.availablePresets
        case .staticModes:
            return staticPresets
        case .flows:
            return flowPresets
        }
    }

    private var selectedPresetBinding: Binding<String?> {
        Binding(
            get: { state.selectedPresetID },
            set: { id in
                guard let id else {
                    return
                }
                state.setSelectedPresetID(id)
            }
        )
    }

    private var staticPresets: [LightPreset] {
        state.availablePresets.filter { $0.kind != .flow }
    }

    private var flowPresets: [LightPreset] {
        state.availablePresets.filter { $0.kind == .flow }
    }

    private var canReset: Bool {
        !state.customPresets.isEmpty || state.favoritePresetIDs != LightPreset.defaultFavoriteIDs
    }

    private func modeRow(_ preset: LightPreset) -> some View {
        ModeLibraryRow(
            preset: preset,
            isFavorite: state.favoritePresetIDs.contains(preset.id),
            canApply: state.canControlSelectedDevice,
            onToggleFavorite: { state.toggleFavoritePreset(id: preset.id) },
            onApply: { state.applyPreset(id: preset.id) },
            onDelete: { state.removeCustomPreset(id: preset.id) }
        )
        .tag(preset.id)
    }
}

private struct ModeLibraryRow: View {
    let preset: LightPreset
    let isFavorite: Bool
    let canApply: Bool
    let onToggleFavorite: () -> Void
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            presetIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.title)
                        .lineLimit(1)

                    if !preset.isBuiltIn {
                        Text("Custom")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }

                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isFavorite ? Color.accentColor : Color.secondary)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(isFavorite ? "Remove \(preset.title) from favorites" : "Add \(preset.title) to favorites")

            Button(action: onApply) {
                ViewThatFits(in: .horizontal) {
                    Label("Apply", systemImage: "play.fill")
                    Image(systemName: "play.fill")
                }
            }
            .controlSize(.small)
            .disabled(!canApply)
            .help("Apply \(preset.title)")
            .accessibilityLabel("Apply \(preset.title)")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(action: onToggleFavorite) {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
            }

            Button(action: onApply) {
                Label("Apply", systemImage: "play.fill")
            }
            .disabled(!canApply)

            if !preset.isBuiltIn {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete \(preset.title)", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var presetIcon: some View {
        if let rgb = preset.swatchRGB {
            Circle()
                .fill(Color(yeelightRGB: rgb))
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        } else {
            Image(systemName: preset.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }
}

private struct ModePresetDetailPane: View {
    let preset: LightPreset
    let isFavorite: Bool
    let canApply: Bool
    let onToggleFavorite: () -> Void
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader
                primaryActions
                metadataCard

                if preset.kind == .flow {
                    flowSequenceCard
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                largeIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        DetailBadge(text: preset.kind.title)
                        DetailBadge(text: preset.isBuiltIn ? "Built-in" : "Custom")
                    }
                }

                Spacer(minLength: 0)

                if !preset.isBuiltIn {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete \(preset.title)", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("More actions for \(preset.title)")
                }
            }

            Text(preset.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Button(action: onApply) {
                    Label("Apply", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApply)
                .help(canApply ? "Apply \(preset.title)" : "Select an online bulb before applying")

                Button(action: onToggleFavorite) {
                    Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }

            VStack(alignment: .leading, spacing: 8) {
                Button(action: onApply) {
                    Label("Apply", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApply)
                .help(canApply ? "Apply \(preset.title)" : "Select an online bulb before applying")

                Button(action: onToggleFavorite) {
                    Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
    }

    private var metadataCard: some View {
        DetailCard(title: preset.kind == .flow ? "Flow Details" : "Look Details") {
            switch preset.kind {
            case .color:
                DetailInfoRow(label: "Color", value: "#\(String(format: "%06X", preset.rgb))")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .colorTemperature:
                DetailInfoRow(label: "Temperature", value: "\(preset.colorTemperature)K")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .hsv:
                DetailInfoRow(label: "Hue", value: "\(preset.hue)°")
                DetailInfoRow(label: "Saturation", value: "\(preset.saturation)%")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .flow:
                if let flow = preset.flow {
                    DetailInfoRow(label: "Steps", value: "\(flow.steps.count)")
                    DetailInfoRow(label: "Playback", value: playbackText(for: flow))
                    DetailInfoRow(label: "When Finished", value: flow.stopAction.editorTitle)
                } else {
                    Text("This flow is missing its step data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var flowSequenceCard: some View {
        if let flow = preset.flow {
            DetailCard(title: "Step Sequence") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in
                        FlowStepSummaryRow(index: index, step: step)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var largeIcon: some View {
        if let rgb = preset.swatchRGB {
            Circle()
                .fill(Color(yeelightRGB: rgb))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func playbackText(for flow: ColorFlow) -> String {
        if flow.count == 0 {
            return "Repeats forever"
        }

        guard !flow.steps.isEmpty else {
            return "\(flow.count) transitions"
        }

        if flow.count.isMultiple(of: flow.steps.count) {
            let cycles = flow.count / flow.steps.count
            return "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
        }

        return "\(flow.count) transitions"
    }
}

private struct ModeLibraryEmptyDetail: View {
    let filter: ModeLibraryFilter

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Select a \(filter.selectionNoun)")
                .font(.headline)

            Text("Choose an item in the library to inspect details and manage actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct DetailBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

private struct FlowStepSummaryRow: View {
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
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.mode {
        case .color:
            Circle()
                .fill(Color(yeelightRGB: step.rgb))
                .frame(width: 16, height: 16)
                .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }
        case .colorTemperature:
            Image(systemName: "thermometer.sun")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        case .sleep:
            Image(systemName: "pause.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
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

private struct SaveCurrentLookSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    let onSave: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Save Current Look")
                    .font(.title2.weight(.semibold))

                Text("Save the selected bulb's color or color temperature and brightness as a reusable static mode. Power and active flows are not included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Mode") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || state.currentLightLook == nil)
            }
        }
        .padding(20)
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

    private func save() {
        guard !trimmedName.isEmpty, onSave(trimmedName) else {
            return
        }
        dismiss()
    }
}

private struct NewFlowSheet: View {
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Flow")
                    .font(.title2.weight(.semibold))
                Text("Create an ordered sequence that runs directly on the bulb without keeping YeelightBar open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

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

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Flow") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 680, height: 560)
        .onAppear {
            selectedStepID = steps.first?.id
            nameIsFocused = true
        }
        .onChange(of: steps.count) { _ in
            cycles = min(cycles, maximumCycles)
        }
    }

    private var playbackFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
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
                HStack(spacing: 12) {
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
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    .allowsHitTesting(false)
            }

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

private enum ModeCreator: String, Identifiable {
    case currentLook
    case flow

    var id: String { rawValue }
}

private enum ModeLibraryFilter: String, CaseIterable, Identifiable {
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

private extension FlowStopAction {
    var editorTitle: String {
        switch self {
        case .recover: return "Restore previous state"
        case .stay: return "Keep final state"
        case .turnOff: return "Turn off light"
        }
    }
}

private extension FlowStepMode {
    var editorTitle: String {
        switch self {
        case .color: return "Color"
        case .colorTemperature: return "Temperature"
        case .sleep: return "Hold"
        }
    }
}

private func formattedMilliseconds(_ value: Int) -> String {
    if value < 1000 {
        return "\(value) ms"
    }

    let seconds = Double(value) / 1000
    return String(format: seconds == floor(seconds) ? "%.0f s" : "%.1f s", seconds)
}
