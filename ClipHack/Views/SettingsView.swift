import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row("Sample Rate") {
                    Picker("", selection: $viewModel.settings.sampleRate) {
                        Text("44.1 kHz").tag(ClipHackSettings.SampleRate.s44100)
                        Text("48 kHz").tag(ClipHackSettings.SampleRate.s48000)
                    }
                    .pickerStyle(.segmented)
                }

                row("Output") {
                    Picker("", selection: $viewModel.settings.stereoOutput) {
                        Text("Mono").tag(false)
                        Text("Stereo").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                row("Channel") {
                    Picker("", selection: $viewModel.settings.channel) {
                        Text("Left").tag(ClipHackSettings.MonoChannel.left)
                        Text("Right").tag(ClipHackSettings.MonoChannel.right)
                    }
                    .pickerStyle(.segmented)
                }
                .disabled(viewModel.settings.stereoOutput)
                .opacity(viewModel.settings.stereoOutput ? 0.4 : 1)
                .help(viewModel.settings.stereoOutput ? "Only applies in Mono output mode" : "")

                Divider().padding(.vertical, 6)

                row("Ceiling") {
                    HStack(spacing: 6) {
                        Slider(value: $viewModel.settings.limitDb, in: -6 ... -1, step: 1)
                        Text(String(format: "%.0f dB", viewModel.settings.limitDb))
                            .font(.system(size: 11).monospaced())
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .help("Brick-wall limiter true-peak ceiling. Sets the maximum output level.")

                row("High Pass") {
                    HStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.dcBlockHz) },
                                set: { viewModel.settings.dcBlockHz = Int($0) }
                            ),
                            in: 20...90,
                            step: 5
                        )
                        Text(viewModel.settings.dcBlockHz == 20 ? "DC Block" : "\(viewModel.settings.dcBlockHz) Hz")
                            .font(.system(size: 11).monospaced())
                            .frame(width: 55, alignment: .trailing)
                    }
                }

                Divider().padding(.vertical, 6)

                row("Noise Reduction") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: $viewModel.settings.noiseReductionEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                            Text("RNNoise (ML)")
                        }
                        Text("Check output before editing — artifacts are possible on heavy noise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                row("De-esser") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $viewModel.settings.deEsserEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text("Gentle (7.5 kHz)")
                    }
                }

                Divider().padding(.vertical, 6)

                row("Level Audio") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $viewModel.settings.levelingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text("dynaudnorm")
                    }
                }

                row("Aggressiveness") {
                    HStack(spacing: 6) {
                        Slider(value: $viewModel.settings.levelingAmount, in: 0 ... 1)
                        Text(aggressivenessLabel(viewModel.settings.levelingAmount))
                            .font(.system(size: 11).monospaced())
                            .frame(width: 68, alignment: .trailing)
                    }
                }
                .disabled(!viewModel.settings.levelingEnabled)
                .opacity(!viewModel.settings.levelingEnabled ? 0.4 : 1)
                .help(!viewModel.settings.levelingEnabled ? "Enable Level Audio to adjust" : "")

                Divider().padding(.vertical, 6)

                row("Loudness Norm") {
                    Toggle("", isOn: $viewModel.settings.loudnormEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                row("Target") {
                    HStack(spacing: 6) {
                        Slider(value: $viewModel.settings.loudnormTarget, in: -35 ... -14, step: 1)
                        Text(String(format: "%.0f LUFS", viewModel.settings.loudnormTarget))
                            .font(.system(size: 11).monospaced())
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!viewModel.settings.loudnormEnabled)
                .opacity(!viewModel.settings.loudnormEnabled ? 0.4 : 1)

                Divider().padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text("OUTPUT DIR")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .kerning(0.4)
                    if let path = viewModel.settings.outputDirectoryPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(path)
                    } else {
                        Text("Same as source")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
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
                        if viewModel.settings.outputDirectoryPath != nil {
                            Button("Reset") {
                                viewModel.settings.outputDirectoryPath = nil
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .padding(12)
        }
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            content()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
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
