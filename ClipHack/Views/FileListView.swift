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
        .background(
            Group {
                Button("") {
                    guard !viewModel.selectedFileIDs.isEmpty else { return }
                    viewModel.removeSelected()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .hidden()

                Button("") {
                    viewModel.selectedFileIDs = Set(viewModel.files.map { $0.id })
                }
                .keyboardShortcut("a", modifiers: .command)
                .hidden()
            }
        )
        .contextMenu {
            if viewModel.files.contains(where: { $0.isProcessed }) {
                Button {
                    viewModel.removeProcessed()
                } label: {
                    Label("Remove Processed Files", systemImage: "checkmark.circle")
                }
            }
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

                if file.hasHighNoiseFloor {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .help("High noise floor — loudness normalization may be less accurate. Consider enabling Noise Reduction.")
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

            if case .processing = file.status {
                ProgressView(value: nil as Double?)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            } else if isProcessing, case .ready = file.status {
                ProgressView(value: 0.0, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.secondary)
                    .opacity(0.35)
            }
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
