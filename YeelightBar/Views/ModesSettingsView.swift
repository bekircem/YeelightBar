import AppKit
import Foundation
import SwiftUI

struct ModesSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: ModeLibraryFilter = .all
    @State private var presentedCreator: ModeCreator?
    @State private var confirmReset = false

    var body: some View {
        libraryContent
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

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            libraryHeader

            HSplitView {
                modeList
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 480, maxHeight: .infinity)

                selectedPresetDetail
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
            HStack(spacing: YeelightDesignTokens.spaceS) {
                Button {
                    presentedCreator = .currentLook
                } label: {
                    Label("Save Current Look…", systemImage: "camera.aperture")
                }
                .buttonStyle(.glass)
                .disabled(state.currentLightLook == nil)
                .help(state.currentLightLook == nil ? "Select a bulb before saving its look" : "Save the selected bulb's static look")

                Button {
                    presentedCreator = .flow
                } label: {
                    Label("New Flow…", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.glass)
                .help("Create a color flow without changing the bulb")
            }
        }
        .controlSize(.small)
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
