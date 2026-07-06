import SwiftUI

struct DownloadPopover: View {
    @Bindable var viewModel: ContentViewModel

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
                .frame(width: 340)
                // Fires on paste (⌘V) and edits too, not just Return — this is
                // the path that catches a URL pasted straight into the field.
                .onChange(of: viewModel.downloadURLField) {
                    viewModel.downloadURLFieldChanged()
                }
                .onSubmit {
                    viewModel.prefillNotesFromURL(viewModel.downloadURLField)
                    viewModel.startDownload()
                }
                .disabled(viewModel.isDownloading)

            TextField("Custom file name (optional — keeps source title)", text: $viewModel.downloadNameField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)

            TextField("Notes (optional, e.g. :30 to :12)", text: $viewModel.downloadNotesField, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .frame(width: 340)
                .disabled(viewModel.isDownloading)

            Toggle("Save clip list", isOn: $viewModel.clipListEnabled)
                .toggleStyle(.checkbox)
                .disabled(viewModel.isDownloading)
                .help("Appends file name, notes, and source URL to a daily clip-list file next to the download.")

            statusLine

            HStack {
                Spacer()
                actionButton
            }
        }
        .padding()
        .onAppear { viewModel.prefillDownloadFromPasteboard() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.downloadState {
        case .idle:
            Text("Video sources are saved as audio only, into ~/Music/ClipHack.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .frame(maxWidth: 340, alignment: .leading)
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
        }
    }
}

#Preview {
    DownloadPopover(viewModel: ContentViewModel())
}
