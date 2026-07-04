import SwiftUI

struct DownloadPopover: View {
    @Bindable var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Download Audio from URL")
                .font(.headline)

            TextField("https://…", text: $viewModel.downloadURLField)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)

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
