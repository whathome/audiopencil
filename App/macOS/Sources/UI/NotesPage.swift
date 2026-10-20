import APCore
import APSync
import AppKit
import SwiftUI

/// Minimal recent list (PRD: Obsidian is the library). Pending reviews, processing, and what was saved.
struct NotesPage: View {
    @Bindable var app: AppModel
    let notes: NoteMaker
    @State private var showingWalkthrough = false
    @State private var confirmingBoardRepair = false
    @State private var deleting: RecentNote?

    private var isObsidian: Bool { app.vault.layout == .obsidian }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Notes", subtitle: isObsidian
                           ? "Long recordings become notes in your vault. Obsidian is where you read and organise them."
                           : "Long recordings become Markdown notes in your notes folder, readable in any editor.")

                if !app.vault.settings.isConfigured {
                    Banner(symbol: "externaldrive.badge.exclamationmark", message: "Choose where notes go. Until then they wait on this Mac.", actionTitle: "Set up storage") {
                        app.page = .vault
                    }
                }

                if app.vault.obsidianUpgradeAvailable {
                    Banner(symbol: "sparkles", message: "This folder is now an Obsidian vault. Add the review board and guide?", actionTitle: "Add board") {
                        app.vault.adoptObsidianLayout()
                    }
                }

                if app.vault.settings.isConfigured, !isObsidian {
                    Card(title: "Your notes folder") {
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundStyle(Color.pencil)
                            Text("Notes and recordings are in the Audio Pencil folder, with About these notes.md explaining them.")
                            Spacer()
                            if let url = app.vault.localFileURL(for: "/Audio Pencil") {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                        }
                    }
                }

                if app.vault.settings.isConfigured, isObsidian {
                    Card(title: "Your board") {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.split.3x1").foregroundStyle(Color.pencil)
                            Text("Review and organise notes in Obsidian with the Audio Pencil board.")
                            Spacer()
                            Button("How it works") { showingWalkthrough = true }
                            if let url = notes.obsidianURL(for: StarterKit.basePath) {
                                Link("Open board", destination: url)
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        if let problem = app.sync.boardProblem {
                            HStack {
                                Label("The board file has a mistake, so it's been left alone.", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(problem)
                                Spacer()
                                Button("Repair…") { confirmingBoardRepair = true }
                            }
                        }
                        if let summary = app.sync.repairSummary, app.sync.repairedBoard {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
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

                if !app.sync.expiringSoon.isEmpty {
                    Card(title: "Audio expiring soon") {
                        Text("These recordings are a year old soon. Their notes stay; the audio goes unless you keep it.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(app.sync.expiringSoon) { item in
                            HStack {
                                Image(systemName: "waveform.badge.exclamationmark").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text("Audio removed \(item.expires.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Keep forever") { Task { await app.sync.archive(item) } }
                            }
                        }
                    }
                }

                Card(title: "Recent") {
                    if notes.recent.isEmpty {
                        Text("Nothing saved yet. Recordings longer than \(Int(app.settings.longFormThreshold / 60)) minutes become notes and show up here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(notes.recent) { note in
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(Color.pencil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: note.title)
                                Text(verbatim: "\(note.styleName) · \(note.recorded.formatted(date: .abbreviated, time: .shortened)) · \(note.status.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if note.retention == .archive {
                                Label("Kept forever", systemImage: "infinity").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = notes.openURL(for: note.path) {
                                Link(isObsidian ? "Open in Obsidian" : "Open", destination: url).font(.callout)
                            }
                            Menu {
                                Button("Keep forever") { notes.setRetention(.archive, for: note) }
                                    .disabled(note.retention == .archive)
                                Button("Delete…", role: .destructive) { deleting = note }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .accessibilityLabel(Text("More for \(note.title)"))
                        }
                    }
                }

                Button("Note saving and audio retention…") {
                    app.settingsTab = .general
                    app.page = .settings
                }
                .buttonStyle(.link)
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .confirmationDialog(
            "Delete this note and its recording?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { note in
            Button("Delete", role: .destructive) { notes.setRetention(.delete, for: note) }
        } message: { note in
            Text("“\(note.title)” and its audio go to the trash at the next check.")
        }
        .confirmationDialog("Repair the board?", isPresented: $confirmingBoardRepair) {
            Button("Repair") { Task { await app.sync.repairBoard() } }
        } message: {
            Text("Your views and settings that still read correctly are kept, and the views Audio Pencil needs are put back. A copy of the file as it is now goes to Audio Pencil/Backups first.")
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

    private func step(_ symbol: String, _ title: LocalizedStringResource, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.pencil).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
