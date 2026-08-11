import SwiftUI

struct DownloadPopover: View {
    @Bindable var viewModel: ContentViewModel

    /// Every control in the popover lines up on this width.
    private static let fieldWidth: CGFloat = 340

    /// Notes-box height when the resize drag began, so the drag tracks the
    /// pointer instead of accumulating per-event deltas.
    @State private var dragStartHeight: Double?

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
                .frame(width: Self.fieldWidth)
                .onSubmit { viewModel.startDownload() }
                .disabled(viewModel.isDownloading)

            notesEditor

            Toggle("Save clip notes", isOn: $viewModel.clipNotesEnabled)
                .toggleStyle(.checkbox)
                .disabled(viewModel.isDownloading)
                .help("Saves file name, notes, and source URL to a text file inside the clip's own folder.")

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

    /// A TextEditor rather than a TextField so the box can be dragged taller —
    /// long X-post text and multi-clip timing notes don't fit four lines. Styled
    /// to match the .roundedBorder fields above it, with the placeholder drawn
    /// by hand (TextEditor has no prompt).
    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.downloadNotesField)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .disabled(viewModel.isDownloading)

            if viewModel.downloadNotesField.isEmpty {
                // Sits exactly where the editor's first glyph does: the same 4/3
                // padding, plus the text container's 5pt lineFragmentPadding on
                // the leading edge (measured against the hosted NSTextView).
                Text("Notes (optional, e.g. :30 to :12)")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .padding(.vertical, 3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Self.fieldWidth, height: viewModel.notesFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) { resizeGrip }
    }

    /// Corner grip for the notes box. Vertical only — the popover's controls all
    /// share one width, so there is nothing to gain from dragging sideways.
    private var resizeGrip: some View {
        ResizeGrip()
            .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(width: 11, height: 11)
            .padding(3)
            .contentShape(Rectangle())
            // .set() rather than push/pop: an onHover(false) that never arrives
            // would leave a push unbalanced and the resize cursor stuck.
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStartHeight ?? viewModel.notesFieldHeight
                        dragStartHeight = start
                        viewModel.notesFieldHeight = start + value.translation.height
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .help("Drag to resize")
            .accessibilityLabel("Resize notes field")
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
            Spacer()
            Button("Change…") { viewModel.chooseDownloadDirectory() }
                .controlSize(.small)
            if viewModel.settings.downloadDirectoryPath != nil {
                Button("Reset") { viewModel.resetDownloadDirectory() }
                    .controlSize(.small)
            }
        }
        .frame(width: Self.fieldWidth)
        .disabled(viewModel.isDownloading)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.downloadState {
        case .idle:
            Text("Each download gets its own folder. Video sources are saved as audio only.")
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

/// Three stepped diagonals in the corner — the standard "drag me" affordance.
private struct ResizeGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 1
        for fraction in [0.35, 0.65, 0.95] as [CGFloat] {
            let x = rect.minX + inset + (rect.width - inset * 2) * fraction
            let y = rect.minY + inset + (rect.height - inset * 2) * fraction
            path.move(to: CGPoint(x: x, y: rect.maxY - inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: y))
        }
        return path
    }
}

#Preview {
    DownloadPopover(viewModel: ContentViewModel())
}
