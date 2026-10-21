import APCore
import SwiftUI

/// Notes waiting for review, and the ones already filed.
struct NotesView: View {
    let app: PhoneModel

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
                if let processing = app.notes.processing {
                    Section {
                        StatusRow(symbol: nil, text: processing)
                    }
                }
                if !app.notes.queue.isEmpty {
                    Section {
                        ForEach(app.notes.queue) { item in
                            NoteRow(title: NoteRenderer.fallbackTitle(from: item.transcript), detail: item.recorded.formatted(date: .abbreviated, time: .shortened))
                        }
                    } header: {
                        Text("Waiting to be written")
                    } footer: {
                        Text("Written up while Audio Pencil is open; leaving pauses it.")
                    }
                }
                if !app.notes.recent.isEmpty {
                    Section("Filed") {
                        ForEach(app.notes.recent) { note in
                            NoteRow(title: note.title, detail: "\(note.styleName) · \(note.recorded.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
            }
            .overlay {
                if app.notes.recent.isEmpty, app.notes.queue.isEmpty, app.notes.processing == nil {
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
