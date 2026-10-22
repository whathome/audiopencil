import APCore
import SwiftUI
import UIKit

/// Recordings waiting to be written, ones copied but not filed, and the notes already filed. Every one can
/// be copied.
struct NotesView: View {
    let app: PhoneModel

    private var notes: PhoneNotes { app.notes }

    var body: some View {
        NavigationStack {
            List {
                if !app.vault.settings.isConfigured {
                    Section {
                        NavigationLink {
                            StorageSettingsView(vault: app.vault, sync: app.sync)
                        } label: {
                            Label("Choose where notes go", systemImage: "externaldrive.badge.exclamationmark")
                        }
                    } footer: {
                        Text("Until then, filed notes wait on this iPhone.")
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
                }
            }
            .navigationTitle("Notes")
        }
    }

    // MARK: Sections

    private var waiting: some View {
        Section {
            ForEach(notes.queue) { item in
                HStack {
                    NoteRow(title: NoteRenderer.fallbackTitle(from: item.transcript), detail: item.recorded.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
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
                HStack(spacing: 12) {
                    NoteRow(title: item.note.title, detail: "\(item.styleName) · \(item.note.recorded.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                    CopyButton(label: "Copy the note") { item.note.body }
                    Button("File") { notes.file(item) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityHint(Text("Files it in your notes folder with its audio, as Make Note would have."))
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
                HStack {
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
        if app.vault.layout == .obsidian, let url = app.vault.obsidianURL(for: note.path) {
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
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless) // its own tap target inside a row that opens the note
        .tint(done ? .green : Color.pencil)
        .sensoryFeedback(.success, trigger: done) { _, new in new }
        .sensoryFeedback(.error, trigger: failed)
        .accessibilityLabel(Text(done ? "Copied" : label))
    }
}
