import APCore
import APSync
import SwiftUI

/// Minimal recent list (PRD: Obsidian is the library). Pending reviews, processing, and what was saved.
struct NotesPage: View {
    @Bindable var app: AppModel
    let notes: NoteMaker
    @State private var showingWalkthrough = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Notes", subtitle: "Long recordings become notes in your vault. Obsidian is where you read and organise them.")

                if !app.vault.settings.isConfigured {
                    Banner(symbol: "externaldrive.badge.exclamationmark", message: "Connect your vault so notes have somewhere to go. Until then they wait on this Mac.", actionTitle: "Set up vault") {
                        app.page = .vault
                    }
                }

                if app.vault.settings.isConfigured {
                    Card(title: "Your board") {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.split.3x1").foregroundStyle(Color.pencil)
                            Text("Review and organise notes in Obsidian with the Audio Pencil board.")
                            Spacer()
                            Button("How it works") { showingWalkthrough = true }
                            if let url = notes.obsidianURL(for: StarterKit.basePath) {
                                Link("Open board", destination: url)
                            }
                        }
                    }
                }

                if let status = notes.processing {
                    Card {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(status)
                        }
                    }
                }

                if !notes.pending.isEmpty {
                    Card(title: "Waiting for review") {
                        ForEach(notes.pending) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.note.title).font(.headline)
                                    Text("\(item.note.recorded.formatted(date: .abbreviated, time: .shortened)) · \(ReviewView.minutes(item.note.duration))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Skip") { notes.skip(item) }
                                Button("Review…") { notes.review(id: item.id) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                Card(title: "Recent") {
                    if notes.recent.isEmpty {
                        Text("Nothing saved yet. Recordings longer than \(Int(app.settings.longFormThreshold / 60)) minutes become notes; quick dictations too if you turn that on below.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(notes.recent) { note in
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(Color.pencil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                Text("\(note.styleName) · \(note.recorded.formatted(date: .abbreviated, time: .shortened)) · \(note.status.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = notes.obsidianURL(for: note.path) {
                                Link("Open in Obsidian", destination: url).font(.callout)
                            }
                        }
                    }
                }

                Card(title: "Saving") {
                    Toggle("Save quick dictations as notes too", isOn: $app.settings.saveQuickDictations)
                    HStack {
                        Text("Recordings longer than")
                        Stepper(value: $app.settings.longFormThreshold, in: 60...3_600, step: 60) {
                            Text("\(Int(app.settings.longFormThreshold / 60)) min")
                                .monospacedDigit()
                        }
                        .fixedSize()
                        Text("become long-form notes instead of pasting.")
                    }
                    Text("Notes go to each style's folder (set on the Styles page), or \(NoteMaker.defaultFolder.dropFirst()). Audio goes to \(NoteMaker.recordingsFolder.dropFirst()).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(isPresented: $showingWalkthrough) {
            BoardWalkthrough(boardURL: notes.obsidianURL(for: StarterKit.basePath), guideURL: notes.obsidianURL(for: StarterKit.guidePath))
        }
        .onAppear {
            if app.sync.showWalkthrough {
                app.sync.showWalkthrough = false
                showingWalkthrough = true
            }
        }
        .onChange(of: app.sync.showWalkthrough) { _, show in
            if show {
                app.sync.showWalkthrough = false
                showingWalkthrough = true
            }
        }
    }
}

/// PRD first run: a short tour of the review board.
private struct BoardWalkthrough: View {
    let boardURL: URL?
    let guideURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your review board is ready").font(.system(size: 24, weight: .bold, design: .serif))
            Text("Audio Pencil added a few files to your vault, in the Audio Pencil folder:").foregroundStyle(.secondary)
            step("rectangle.split.3x1", "Audio Pencil.base", "A board of your notes. The Professional review view has a column per status. Drag a card from needs-review to reviewed once you've read it, and to actioned when it's done.")
            step("book", "Audio Pencil guide", "What each property means, with worked examples.")
            step("doc.on.doc", "Three sample notes", "So the board has real cards. They're tagged sample and safe to delete.")
            step("checkmark.circle", "Reviewing", "When a long recording finishes you'll get a notification. Approve its title, tags and folder, or skip it and it waits on the board as needs-review.")
            HStack {
                if let guideURL { Link("Open the guide", destination: guideURL) }
                Spacer()
                if let boardURL { Link("Open the board in Obsidian", destination: boardURL).buttonStyle(.borderedProminent) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private func step(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.pencil).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
