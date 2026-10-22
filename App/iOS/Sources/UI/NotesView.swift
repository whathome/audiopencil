import APCore
import SwiftUI
import UIKit

/// Recordings waiting to be written, ones copied but not filed, and the notes already filed. Every one can
/// be copied.
struct NotesView: View {
    let app: PhoneModel
    /// Why the last copy didn't happen, shown for a moment at the bottom.
    @State private var copyProblem: String?

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
                if notes.processing != nil, !app.recorder.isActive {
                    Section {
                        WritingProgressRow(notes: notes)
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
                        Text("Recordings become notes: written up in a style, with their audio, filed in your notes folder. Review them on your Obsidian board. Ones you only copy wait here until you file them.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let copyProblem {
                    Label(copyProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: copyProblem)
            .navigationTitle("Notes")
        }
    }

    // MARK: Sections

    private var waiting: some View {
        Section {
            ForEach(notes.queue) { item in
                HStack {
                    NoteRow(title: NoteRenderer.fallbackTitle(from: item.transcript), detail: details(item.duration, item.recorded))
                    Spacer()
                    CopyButton(label: "Copy the transcript", failed: reportCopyProblem) { item.transcript }
                }
            }
            // Nothing is running and nothing stops it: let it be started by hand.
            if let reason = notes.waitingReason, !app.recorder.isActive, UIApplication.shared.applicationState == .active {
                Button {
                    notes.processQueue()
                } label: {
                    Label("Write them now", systemImage: "pencil.and.scribble")
                        .font(.body.weight(.semibold))
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
                    NoteRow(title: item.note.title, detail: details(item.note.duration, item.note.recorded, style: item.styleName))
                    Spacer()
                    CopyButton(label: "Copy the note", failed: reportCopyProblem) { item.note.body }
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
                    CopyButton(label: "Copy the note", failed: reportCopyProblem) { await notes.text(of: note) }
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

    /// "Polished · 12m 40s · Oct 22 at 1:05 PM": the length tells a walk from a quick thought.
    private func details(_ duration: TimeInterval?, _ recorded: Date, style: String? = nil) -> String {
        let length = duration.map {
            Duration.seconds($0.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
        }
        return [style, length, recorded.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
    }

    /// A copy that couldn't happen says why, on screen and to VoiceOver, instead of only buzzing.
    private func reportCopyProblem() {
        let message = String(localized: "Couldn't copy it: your storage can't be reached, and this note's text isn't on this iPhone.")
        copyProblem = message
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: .seconds(4))
            if copyProblem == message { copyProblem = nil }
        }
    }

    @ViewBuilder
    private func filedRow(_ note: RecentNote) -> some View {
        let row = NoteRow(title: note.title, detail: details(note.duration, note.recorded, style: note.styleName))
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
    let failed: () -> Void
    let text: () async -> String?
    @State private var done = false
    @State private var failures = 0

    var body: some View {
        Button {
            Task {
                guard let text = await text(), !text.isEmpty else {
                    failures += 1
                    failed()
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
        .sensoryFeedback(.error, trigger: failures)
        .accessibilityLabel(Text(done ? "Copied" : label))
    }
}
