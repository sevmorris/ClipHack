import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(nil) {
                    Picker("", selection: $viewModel.settings.sampleRate) {
                        Text("44.1 kHz").tag(ClipHackSettings.SampleRate.s44100)
                        Text("48 kHz").tag(ClipHackSettings.SampleRate.s48000)
                    }
                    .pickerStyle(.segmented)
                }

                row(nil) {
                    Picker("", selection: $viewModel.settings.stereoOutput) {
                        Text("Mono").tag(false)
                        Text("Stereo").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                row(nil) {
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

                row("Ceiling", caption: "True-peak ceiling for the brick-wall limiter") {
                    HStack(spacing: 6) {
                        Slider(value: $viewModel.settings.limitDb, in: -6 ... -1, step: 1)
                        Text(String(format: "%.0f dB", viewModel.settings.limitDb))
                            .font(.system(size: 11).monospaced())
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                .help("Brick-wall limiter true-peak ceiling. Sets the maximum output level.")

                row("High Pass", caption: "Removes rumble and low-frequency noise; DC Block only removes offset") {
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

                row("Loudness Norm", caption: "Two-pass EBU R128 normalization to a target loudness") {
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
    private func row<Content: View>(
        _ label: String?,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.4)
            }
            content()
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

}
