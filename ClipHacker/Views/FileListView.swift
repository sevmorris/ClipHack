import SwiftUI
import AppKit

struct FileListView: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        List(selection: $viewModel.selectedFileIDs) {
            ForEach(viewModel.files) { file in
                FileRowView(file: file, isProcessing: viewModel.isProcessing)
                    .tag(file.id)
            }
            .onDelete { offsets in
                viewModel.removeFiles(at: offsets)
            }
            .onMove { source, destination in
                viewModel.moveFiles(from: source, to: destination)
            }
        }
        .overlay {
            // Hidden button captures plain Delete key to remove selected files
            Button("") { viewModel.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .hidden()
        }
    }
}

struct FileRowView: View {
    let file: FileItem
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(file.url.lastPathComponent)
                    .font(.body)

                if case .processing = file.status {
                    ProgressView()
                        .controlSize(.small)
                } else if isProcessing, case .ready = file.status {
                    ProgressView(value: 0.0)
                        .controlSize(.small)
                        .opacity(0.35)
                }

                if file.hasHighNoiseFloor {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .help("High noise floor — level detection may be less accurate")
                }

                if file.isProcessed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Complete")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if let outputURL = file.outputURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                        } label: {
                            Image(systemName: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }
            }

            statusText
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch file.status {
        case .pending:
            Text("Waiting...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .analyzing:
            Text("Calculating stats...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .processing:
            Text("Processing...")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ready(let stats):
            let lufsStr = stats.lufs > -100 ? " \u{2022} \(String(format: "%.1f", stats.lufs)) LUFS" : ""
            Text("RMS \(String(format: "%.1f", stats.rms)) dBFS \u{2022} Peak \(String(format: "%.1f", stats.peak)) dBFS\(lufsStr)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .processed(let outputURL):
            Text("Output: \(outputURL.lastPathComponent)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let message):
            Text("Error: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
