import SwiftUI

struct PresetPicker: View {
    @Bindable var viewModel: ContentViewModel
    @State private var showingSaveSheet = false
    @State private var newPresetName = ""

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Built-in Presets") {
                    ForEach(ClipHackPreset.builtIn) { preset in
                        Button(preset.name) {
                            viewModel.applyPreset(preset)
                        }
                    }
                }

                if !viewModel.presetStore.presets.isEmpty {
                    Section("Custom Presets") {
                        ForEach(viewModel.presetStore.presets) { preset in
                            Button(preset.name) {
                                viewModel.applyPreset(preset)
                            }
                        }
                    }
                }

                Divider()

                Button("Save Current Settings…") {
                    newPresetName = ""
                    showingSaveSheet = true
                }

                if !viewModel.presetStore.presets.isEmpty {
                    Menu("Delete Preset") {
                        ForEach(viewModel.presetStore.presets) { preset in
                            Button(preset.name, role: .destructive) {
                                viewModel.presetStore.deletePreset(preset)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text(currentPresetName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 120, maxWidth: 200, alignment: .leading)
            .help(currentPresetName)
        }
        .sheet(isPresented: $showingSaveSheet) {
            SavePresetSheet(
                presetName: $newPresetName,
                existingNames: Set(viewModel.presetStore.allPresets.map { $0.name })
            ) {
                if !newPresetName.isEmpty {
                    viewModel.saveCurrentAsPreset(name: newPresetName)
                }
                showingSaveSheet = false
            } onCancel: {
                showingSaveSheet = false
            }
        }
    }

    private var currentPresetName: String {
        viewModel.presetStore.selectedPreset?.name ?? "Custom"
    }
}

struct SavePresetSheet: View {
    @Binding var presetName: String
    let existingNames: Set<String>
    let onSave: () -> Void
    let onCancel: () -> Void

    private var trimmedName: String {
        presetName.trimmingCharacters(in: .whitespaces)
    }

    private var isDuplicate: Bool {
        existingNames.contains(trimmedName)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Save Preset")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Preset Name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onSubmit {
                        if !trimmedName.isEmpty { onSave() }
                    }

                if isDuplicate {
                    Text("A preset named \"\(trimmedName)\" already exists.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 250, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }

                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
    }
}
