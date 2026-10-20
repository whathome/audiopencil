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
                if !app.notes.pending.isEmpty {
                    Section("To review") {
                        ForEach(app.notes.pending) { item in
                            Button { app.notes.reviewing = item } label: {
                                NoteRow(title: item.note.title, detail: item.note.recorded.formatted(date: .abbreviated, time: .shortened))
                            }
                            .tint(.primary)
                        }
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
                if app.notes.pending.isEmpty, app.notes.recent.isEmpty, app.notes.processing == nil {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "doc.text")
                    } description: {
                        Text("Recordings become notes: written up in a style, with their audio, filed in your notes folder.")
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
