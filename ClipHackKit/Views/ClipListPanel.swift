import AppKit
import SwiftUI

/// This show's clip list: one editable row per notes sidecar in the download
/// folder, and the numbered list they add up to.
///
/// A view over the sidecars, not a document of its own. Every edit writes
/// straight back to that clip's own `.txt`, so there is exactly one source of
/// truth — and the list survives quitting, a week of prep, and the audio being
/// processed and trashed, because the sidecars outlive the files they describe.
///
/// Scope comes from the download folder, which the session picker points at an
/// episode's `clips` folder — so this is always the current session's list, and
/// a session is a folder rather than a record that could fall out of sync.
struct ClipListPanel: View {
    @Bindable var viewModel: ContentViewModel

    /// Export numbers keyed by sidecar, matching what `numberedList` will emit
    /// so a row's badge is the number it actually exports as.
    private var exportNumbers: [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        var next = 1
        for row in viewModel.clipListRows
        where ClipListEntry.isListable(person: row.person, description: row.description) {
            numbers[row.id] = next
            next += 1
        }
        return numbers
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if viewModel.clipListRows.isEmpty {
                    emptyState
                } else {
                    rowList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 760, height: 540)
        .onAppear { viewModel.loadClipList() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clip List")
                    .font(.headline)
                Text(viewModel.sessionTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(viewModel.clipListDirectory.path)
            }
            Spacer()
            Button {
                viewModel.loadClipList()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Re-read the notes files in this folder")
        }
        .padding(12)
    }

    // MARK: - Rows

    private var rowList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.clipListRows) { row in
                    rowView(row)
                }
            }
            .padding(12)
        }
    }

    private func rowView(_ row: ContentViewModel.ClipListRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(exportNumbers[row.id].map { "\($0))" } ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(exportNumbers[row.id] == nil ? .tertiary : .secondary)
                .frame(width: 30, alignment: .trailing)
                .help(exportNumbers[row.id] == nil ? "Blank rows are left out of the copied list" : "")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Person", text: binding(id: row.id, \.person))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)

                    Text(ClipListEntry.separator)
                        .foregroundStyle(.secondary)

                    TextField("What they said, or what the clip is about",
                              text: binding(id: row.id, \.description))
                        .textFieldStyle(.roundedBorder)

                    TextField("1:13 to :55", text: binding(id: row.id, \.timestamp))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .help("The cut. Kept in the notes file, left out of the copied list.")
                }

                HStack(spacing: 8) {
                    Text(row.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !row.hasAudio {
                        Label("audio removed", systemImage: "waveform.slash")
                            .help("The notes for this clip are still here, but its audio is gone.")
                    }

                    if !row.extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("notes", systemImage: "text.alignleft")
                            .help(row.extra)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.number")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No clip notes in this folder")
                .font(.headline)
            Text("Clips get a notes file when \"Save clip notes\" is on in the download popover. Pick or start a session from the toolbar to see that episode's list here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // The rows show the stored form (name as typed, dash between the
            // fields); the clipboard gets the name in capitals and no dash. One
            // sample line keeps that from being a surprise on paste.
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let previewLine {
                    Text("Copies as  \(previewLine)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 12)
            Button("Copy List") {
                viewModel.copyClipList()
            }
            .disabled(exportNumbers.isEmpty)
            .help("Copy the numbered clip list to the clipboard")
            Button("Done") {
                viewModel.isClipListPresented = false
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// The first listable row as it will actually be copied.
    private var previewLine: String? {
        guard let first = viewModel.clipListRows.first(where: {
            ClipListEntry.isListable(person: $0.person, description: $0.description)
        }) else { return nil }
        return "1) " + ClipListEntry.exportLine(person: first.person, description: first.description)
    }

    private var countLabel: String {
        let listable = exportNumbers.count
        let total = viewModel.clipListRows.count
        if total == 0 { return "No clips" }
        if listable == total { return listable == 1 ? "1 clip" : "\(listable) clips" }
        return "\(listable) of \(total) clips — the rest are blank"
    }

    // MARK: - Bindings

    /// A binding that writes through to the sidecar on every keystroke.
    ///
    /// Keyed by the row's sidecar URL, never by its position: `loadClipList`
    /// re-sorts the array (Refresh, ⇧⌘C and switching session all reload), and
    /// an index captured when the field was drawn can by then name a different
    /// clip — writing the typed text into that clip's notes and destroying what
    /// was there.
    private func binding(
        id: UUID,
        _ keyPath: WritableKeyPath<ContentViewModel.ClipListRow, String>
    ) -> Binding<String> {
        Binding(
            get: { viewModel.clipListRows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { viewModel.updateClipListRow(id: id, keyPath: keyPath, value: $0) }
        )
    }
}
