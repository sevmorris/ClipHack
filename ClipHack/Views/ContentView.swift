import AppKit
import SwiftUI

struct ContentView: View {
    @State private var viewModel = ContentViewModel()
    @State private var fileListWidth: CGFloat = 250
    @State private var showSettings: Bool = true

    private var selectedFile: FileItem? {
        guard viewModel.selectedFileIDs.count == 1,
              let id = viewModel.selectedFileIDs.first,
              let file = viewModel.files.first(where: { $0.id == id })
        else { return nil }
        return file
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            HStack(spacing: 0) {
                fileListSection
                    .frame(width: fileListWidth)

                draggableDivider

                waveformSection
                    .frame(minWidth: 260)

                if showSettings {
                    staticDivider
                    SettingsView(viewModel: viewModel)
                        .frame(width: 260)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .dropDestination(for: URL.self) { urls, _ in
            var handled = false
            let localURLs = urls.filter { $0.isFileURL }
            if !localURLs.isEmpty {
                viewModel.addFiles(localURLs)
                handled = true
            }
            // A web URL dragged from a browser prefills the download popover;
            // the download itself only starts from its Download button.
            if let webURL = urls.first(where: { !$0.isFileURL }) {
                handled = viewModel.acceptDroppedURL(webURL.absoluteString) || handled
            }
            return handled
        }
        .alert(viewModel.alertTitle, isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("Already Processed?", isPresented: $viewModel.showReprocessWarning) {
            Button("Add Anyway") { viewModel.confirmReprocessWarning() }
            Button("Cancel", role: .cancel) { viewModel.dismissReprocessWarning() }
        } message: {
            Text("One or more files look like ClipHack outputs (*clipped*.wav). Re-processing will create another generation.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.cancelProcessing()
            // Terminates the yt-dlp child (cancellation handlers run
            // synchronously) so quitting mid-download leaves no orphan.
            viewModel.cancelDownload()
        }
    }

    private var headerView: some View {
        HStack {
            PresetPicker(viewModel: viewModel)

            Spacer()

            Button {
                viewModel.isDownloadPopoverPresented.toggle()
            } label: {
                Label("Add from URL", systemImage: "link")
            }
            .help("Download audio from a web URL")
            .keyboardShortcut("l", modifiers: .command)
            .popover(isPresented: $viewModel.isDownloadPopoverPresented, arrowEdge: .bottom) {
                DownloadPopover(viewModel: viewModel)
            }

            Divider().frame(height: 20)

            if viewModel.isProcessing {
                Button {
                    viewModel.cancelProcessing()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .tint(.red)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    viewModel.process()
                } label: {
                    Label("Process", systemImage: "play.fill")
                }
                .disabled(!viewModel.hasProcessableFiles || viewModel.isAnyFileAnalyzing)
                .help(viewModel.isAnyFileAnalyzing ? "Waiting for analysis to complete…" : "")
                .keyboardShortcut(.return, modifiers: .command)
            }

            Menu {
                Button {
                    viewModel.removeSelected()
                } label: {
                    Label("Remove Selected", systemImage: "minus.circle")
                }
                .disabled(viewModel.selectedFileIDs.isEmpty)

                Button {
                    viewModel.removeProcessed()
                } label: {
                    Label("Remove Processed", systemImage: "checkmark.circle")
                }
                .disabled(!viewModel.files.contains { $0.isProcessed })
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .fixedSize()
            .disabled(viewModel.selectedFileIDs.isEmpty && !viewModel.files.contains { $0.isProcessed })

            Button {
                viewModel.clearAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])

            Divider().frame(height: 20)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help(showSettings ? "Hide Settings" : "Show Settings")
        }
        .padding()
        .background(.regularMaterial)
    }

    private var draggableDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1).onChanged { value in
                    let newWidth = fileListWidth + value.translation.width
                    fileListWidth = max(150, min(newWidth, 500))
                }
            )
    }

    private var staticDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1)
    }

    @ViewBuilder
    private var fileListSection: some View {
        if viewModel.files.isEmpty {
            EmptyStateView()
        } else {
            FileListView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var waveformSection: some View {
        if let file = selectedFile {
            VStack(alignment: .leading, spacing: 8) {
                Text(file.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.url.path)

                WaveformView(waveformData: file.outputWaveform ?? file.waveform)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                FileInfoStatsView(file: file)
            }
            .padding()
        } else {
            VStack {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select a file to view waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
}
