import APCore
import SwiftUI

/// PRD review flow: approve the suggested title, tags and folder, or skip straight away.
struct ReviewView: View {
    let item: PendingNote
    let knownTags: [String]
    /// Approve with the title, tags and folder as edited.
    let approve: (_ title: String, _ tags: [String], _ folder: String) -> Void
    let skip: () -> Void

    @State private var title: String
    @State private var tags: [String]
    @State private var acceptedNewTags: Set<String>
    @State private var folder: String
    @State private var newTag = ""

    init(item: PendingNote, knownTags: [String], approve: @escaping (String, [String], String) -> Void, skip: @escaping () -> Void) {
        self.item = item
        self.knownTags = knownTags
        self.approve = approve
        self.skip = skip
        _title = State(initialValue: item.note.title)
        _tags = State(initialValue: item.note.tags)
        _acceptedNewTags = State(initialValue: [])
        _folder = State(initialValue: item.note.folder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.title3)
                    LabeledContent("Recorded") {
                        Text("\(item.note.recorded.formatted(date: .abbreviated, time: .shortened)) · \(Self.minutes(item.note.duration))")
                    }
                    TextField("Folder", text: $folder, prompt: Text(NoteFiling.defaultFolder))
                }

                Section {
                    FlowTags(tags: tags) { tag in tags.removeAll { $0 == tag } }
                    if !item.newTags.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested new tags (added to your tag list if you keep them)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                ForEach(item.newTags, id: \.self) { tag in
                                    Toggle(tag, isOn: Binding(
                                        get: { acceptedNewTags.contains(tag) },
                                        set: { if $0 { acceptedNewTags.insert(tag) } else { acceptedNewTags.remove(tag) } }
                                    ))
                                    .toggleStyle(.button)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("Add a tag", text: $newTag)
                            .onSubmit(addTag)
                        Menu("Your tags") {
                            ForEach(knownTags.filter { !tags.contains($0) }, id: \.self) { tag in
                                Button(tag) { tags.append(tag) }
                            }
                        }
                        .disabled(knownTags.allSatisfy(tags.contains))
                        .fixedSize()
                    }
                } header: {
                    Text("Tags")
                }

                Section("Note") {
                    ScrollView {
                        Text(Self.preview(item.note.body))
                            .font(.system(.body, design: .serif))
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160)
                }
            }
            .formStyle(.grouped)

            #if os(macOS)
            HStack {
                Text("Skipped notes are saved as “needs review” for your Obsidian board.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Skip", action: skip)
                    .keyboardShortcut(.cancelAction)
                Button("Approve", action: approveEdited)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            #else
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: skip) { Text("Skip").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button(action: approveEdited) { Text("Approve").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                Text("Skipped notes are filed as “needs review”.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .background(.bar)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    private func approveEdited() {
        approve(NoteRenderer.safeTitle(title), tags + item.newTags.filter(acceptedNewTags.contains), folder)
    }

    private func addTag() {
        let tag = TitleAndTags.normaliseTag(newTag)
        if !tag.isEmpty, !tags.contains(tag) { tags.append(tag) }
        newTag = ""
    }

    /// The note's Markdown as it will read in Obsidian: inline emphasis rendered, list dashes as bullets,
    /// line breaks kept.
    static func preview(_ markdown: String) -> AttributedString {
        let text = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.hasPrefix("- ") ? "•  " + line.dropFirst(2) : String(line)
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 1 ? "\(minutes) min" : "\(Int(seconds)) s"
    }
}

/// Removable tag chips.
private struct FlowTags: View {
    let tags: [String]
    let remove: (String) -> Void

    var body: some View {
        if tags.isEmpty {
            Text("No tags").foregroundStyle(.secondary)
        } else {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        Button { remove(tag) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove tag \(tag)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.pencil.opacity(0.18)))
                }
            }
        }
    }
}
