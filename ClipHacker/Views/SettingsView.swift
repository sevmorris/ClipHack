import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Sample Rate")
                    Picker("", selection: $viewModel.settings.sampleRate) {
                        Text("44.1 kHz").tag(ClipHackerSettings.SampleRate.s44100)
                        Text("48 kHz").tag(ClipHackerSettings.SampleRate.s48000)
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Toggle("Stereo Output", isOn: $viewModel.settings.stereoOutput)
                        .gridCellColumns(2)
                }

                GridRow {
                    Text("Ceiling")
                    HStack {
                        Slider(value: $viewModel.settings.limitDb, in: -6 ... -1, step: 1)
                        Text(String(format: "%.0f dB", viewModel.settings.limitDb))
                            .frame(width: 80, alignment: .trailing)
                    }
                }

                GridRow {
                    Toggle("Level Audio", isOn: $viewModel.settings.levelingEnabled)
                        .gridCellColumns(2)
                }

                GridRow {
                    Text("Aggressiveness")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Slider(value: $viewModel.settings.levelingAmount, in: 0 ... 1)
                            Text(aggressivenessLabel(viewModel.settings.levelingAmount))
                                .frame(width: 80, alignment: .trailing)
                        }
                        Text("For broadcast clips (news, promos) — not dialog")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!viewModel.settings.levelingEnabled)

                GridRow {
                    Toggle("Loudness Norm", isOn: $viewModel.settings.loudnormEnabled)
                        .gridCellColumns(2)
                }

                GridRow {
                    Text("Target")
                    HStack {
                        Slider(value: $viewModel.settings.loudnormTarget, in: -30 ... -14, step: 1)
                        Text(String(format: "%.0f LUFS", viewModel.settings.loudnormTarget))
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                .disabled(!viewModel.settings.loudnormEnabled)

                GridRow {
                    Text("Output Dir")
                    HStack {
                        if let path = viewModel.settings.outputDirectoryPath {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                            Button("Reset") {
                                viewModel.settings.outputDirectoryPath = nil
                            }
                            .controlSize(.small)
                        } else {
                            Text("Same as source")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                viewModel.settings.outputDirectoryPath = url.path
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private func aggressivenessLabel(_ amount: Double) -> String {
        switch amount {
        case ..<0.25: return "Gentle"
        case ..<0.5:  return "Low"
        case ..<0.75: return "Medium"
        case ..<0.9:  return "High"
        default:      return "Aggressive"
        }
    }
}
