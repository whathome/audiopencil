import APCore
import SwiftUI
import UIKit

/// Recordings waiting to be written, ones copied but not filed, and the notes already filed. Every one can
/// be copied.
struct NotesView: View {
    let app: PhoneModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: UUID?
    @State private var noteText: String?
    @State private var reading = false
    @State private var retry = UUID()

    private var notes: PhoneNotes { app.notes }
    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    contents
                } detail: {
                    NavigationStack {
                        noteDetail
                    }
                }
            } else {
                NavigationStack { contents }
            }
        }
        .task(id: [selected?.uuidString ?? "", retry.uuidString]) {
            noteText = nil
            guard let selected else { return }
            if let item = notes.copiedNotes.first(where: { $0.id == selected }) {
                noteText = item.note.body
            } else if let item = notes.queue.first(where: { $0.id == selected }) {
                noteText = item.transcript
            } else if let item = notes.recent.first(where: { $0.id == selected }) {
                reading = true
                defer { reading = false }
                let text = await notes.text(of: item)
                guard !Task.isCancelled else { return }
                noteText = text
            }
        }
    }

    private var contents: some View {
            List {
                if !app.vault.settings.isConfigured {
                    Section {
                        NavigationLink {
                            StorageSettingsView(vault: app.vault, sync: app.sync)
                        } label: {
                            Label("Choose where notes go", systemImage: "externaldrive.badge.exclamationmark")
                        }
                    } footer: {
                        Text("Until then, filed notes wait on this device.")
                    }
                }
                if let processing = notes.processing, !app.recorder.isActive {
                    Section {
                        StatusRow(symbol: nil, text: processing)
                    }
                }
                if !notes.queue.isEmpty { waiting }
                if !notes.copiedNotes.isEmpty { copied }
                if !notes.recent.isEmpty { filed }
            }
            .overlay {
                if notes.recent.isEmpty, notes.queue.isEmpty, notes.copiedNotes.isEmpty, notes.processing == nil {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "doc.text")
                    } description: {
                        Text("Recordings become notes: written up in a style, with their audio, filed in your notes folder. Review them on your Obsidian board.")
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Notes")
    }

    @ViewBuilder private var noteDetail: some View {
        if reading {
            ProgressView("Reading note…")
        } else if let selected {
            let recent = notes.recent.first { $0.id == selected }
            let copied = notes.copiedNotes.first { $0.id == selected }
            let title = recent?.title ?? copied?.note.title ?? String(localized: "Transcript")
            ScrollView {
                if let noteText {
                    Text(verbatim: noteText)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Note unavailable", systemImage: "doc.badge.ellipsis")
                    } description: {
                        Text("Connect your storage and try again.")
                    } actions: {
                        Button("Retry") { retry = UUID() }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let noteText {
                    ToolbarItem {
                        Button("Copy Note", systemImage: "doc.on.doc") { UIPasteboard.general.string = noteText }
                    }
                }
                if let recent, let url = app.vault.obsidianURL(for: recent.path) {
                    ToolbarItem { Link("Open in Obsidian", destination: url) }
                }
                if let copied {
                    ToolbarItem { Button("File Note", systemImage: "folder") { notes.file(copied) } }
                }
            }
        } else {
            ContentUnavailableView("Select a note", systemImage: "doc.text",
                                   description: Text("Read a transcript or note beside your recordings. Your storage remains the library."))
        }
    }

    // MARK: Sections

    private var waiting: some View {
        Section {
            ForEach(notes.queue) { item in
                rowLayout {
                    selectableRow(item.id, title: NoteRenderer.fallbackTitle(from: item.transcript), detail: item.recorded.formatted(date: .abbreviated, time: .shortened))
                    if !typeSize.isAccessibilitySize { Spacer() }
                    CopyButton(label: "Copy the transcript") { item.transcript }
                }
            }
            // Nothing is running and nothing stops it: let it be started by hand.
            if let reason = notes.waitingReason, !app.recorder.isActive, UIApplication.shared.applicationState == .active {
                Button {
                    notes.processQueue()
                } label: {
                    Label("Write them now", systemImage: "pencil.and.scribble")
                }
                .accessibilityHint(Text(reason))
            }
        } header: {
            Text("Waiting to be written")
        } footer: {
            Text(notes.waitingReason ?? String(localized: "Written up one at a time while Audio Pencil is open; leaving or recording pauses it."))
        }
    }

    private var copied: some View {
        Section {
            ForEach(notes.copiedNotes) { item in
                rowLayout {
                    selectableRow(item.id, title: item.note.title, detail: "\(item.styleName) · \(item.note.recorded.formatted(date: .abbreviated, time: .shortened))")
                    if !typeSize.isAccessibilitySize { Spacer() }
                    HStack(spacing: 12) {
                        CopyButton(label: "Copy the note") { item.note.body }
                        Button("File") { notes.file(item) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint(Text("Files it in your notes folder with its audio, as Make Note would have."))
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { notes.delete(item) }
                }
            }
        } header: {
            Text("Copied, not filed")
        } footer: {
            Text("These went to the clipboard only. File one to put it in your notes folder with its audio, or swipe to delete it.")
        }
    }

    private var filed: some View {
        Section {
            ForEach(notes.recent) { note in
                rowLayout {
                    filedRow(note)
                    CopyButton(label: "Copy the note") { await notes.text(of: note) }
                }
            }
        } header: {
            Text("Filed")
        } footer: {
            if app.vault.layout == .obsidian, let name = app.vault.vaultName {
                Text("Tap a note to open it in Obsidian, in the vault named \(name).")
            }
        }
    }

    @ViewBuilder
    private func filedRow(_ note: RecentNote) -> some View {
        let row = NoteRow(title: note.title, detail: "\(note.styleName) · \(note.recorded.formatted(date: .abbreviated, time: .shortened))")
        // In an Obsidian vault, a tap opens the note there.
        if sizeClass == .regular {
            Button {
                selected = note.id
            } label: {
                row.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if app.vault.layout == .obsidian, let url = app.vault.obsidianURL(for: note.path) {
            Link(destination: url) {
                HStack {
                    row
                    Spacer()
                    Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the note in Obsidian."))
        } else {
            row
            Spacer()
        }
    }

    @ViewBuilder private func selectableRow(_ id: UUID, title: String, detail: String) -> some View {
        if sizeClass == .regular {
            Button { selected = id } label: {
                NoteRow(title: title, detail: detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NoteRow(title: title, detail: detail)
        }
    }
}

private struct NoteRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.system(.body, design: .serif))
            Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Copies a note's text, showing a tick for a moment once it's on the clipboard.
private struct CopyButton: View {
    let label: LocalizedStringResource
    let text: () async -> String?
    @State private var done = false
    @State private var failed = false

    var body: some View {
        Button {
            Task {
                guard let text = await text(), !text.isEmpty else {
                    failed.toggle()
                    return
                }
                UIPasteboard.general.string = text
                done = true
                try? await Task.sleep(for: .seconds(1.5))
                done = false
            }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless) // its own tap target inside a row that opens the note
        .tint(done ? .green : Color.pencil)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .sensoryFeedback(.error, trigger: failed)
        .accessibilityLabel(Text(done ? "Copied" : label))
    }
}
