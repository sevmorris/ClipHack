import SwiftUI

struct DownloadPopover: View {
    @Bindable var viewModel: ContentViewModel

    /// Every control in the popover lines up on this width.
    private static let fieldWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Download Audio from URL")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.isDownloadPopoverPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }

            TextField("https://…", text: $viewModel.downloadURLField)
                .textFieldStyle(.roundedBorder)
                .frame(width: Self.fieldWidth)
                .onChange(of: viewModel.downloadURLField) { viewModel.downloadURLFieldChanged() }
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)

            TextField("Custom file name (optional — keeps source title)", text: $viewModel.downloadNameField)
                .textFieldStyle(.roundedBorder)
                .frame(width: Self.fieldWidth)
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)

            TextField("Cut (optional) — 1:13 to :55", text: $viewModel.downloadTimestampField)
                .textFieldStyle(.roundedBorder)
                .frame(width: Self.fieldWidth)
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)
                .help("The cut to make. It ends the file name, colons written as periods (1.13 to .55), and is written under the clip's file name in the session's notes file, marked CUT.")

            Toggle("Save clip notes", isOn: clipNotesBinding)
                .toggleStyle(.checkbox)
                .disabled(viewModel.isDownloading || viewModel.isTemporarySession)
                .help(viewModel.isTemporarySession
                      ? "A temporary session keeps no notes file."
                      : "Saves the file name, the cut, and the source URL to this session's notes file, in the download folder.")

            destinationRow

            statusLine

            HStack {
                Spacer()
                actionButton
            }
        }
        .padding()
        .onAppear { viewModel.prefillDownloadFromPasteboard() }
    }

    /// Unchecked in a temporary session, which saves nothing, without
    /// clearing the preference the episodes use.
    private var clipNotesBinding: Binding<Bool> {
        Binding(
            get: { viewModel.clipNotesEnabled && !viewModel.isTemporarySession },
            set: { viewModel.clipNotesEnabled = $0 }
        )
    }

    private var destinationRow: some View {
        HStack(spacing: 6) {
            Text("Destination:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.downloadDirectoryDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(viewModel.downloadDirectoryDisplayPath)
            // No minimum gap: a session's name runs `HT_0382 2026-09-22/clips`,
            // and the default one truncated it.
            Spacer(minLength: 0)
        }
        .frame(width: Self.fieldWidth)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.downloadState {
        case .idle:
            Text(viewModel.isTemporarySession
                 ? "Temporary session: downloads land in this folder and no notes file is kept. Video sources are saved as audio only."
                 : "Downloads land in this folder. Video sources are saved as audio only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.fieldWidth, alignment: .leading)
        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(4)
                .frame(maxWidth: Self.fieldWidth, alignment: .leading)
        case .alreadyDownloaded(_, let filename):
            Text("This link was already downloaded as \"\(filename)\", which has since been processed or filed. Download it again?")
                .font(.caption)
                .lineLimit(4)
                .frame(maxWidth: Self.fieldWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.downloadState {
        case .downloading:
            Button("Cancel") { viewModel.cancelDownload() }
                .tint(.red)
        case .idle, .failed:
            Button("Download") { viewModel.startDownload() }
                .keyboardShortcut(.defaultAction)
                .disabled(ContentViewModel.validatedWebURL(viewModel.downloadURLField) == nil)
        case .alreadyDownloaded:
            Button("Download Again") { viewModel.startDownload(again: true) }
                .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    DownloadPopover(viewModel: ContentViewModel())
}
