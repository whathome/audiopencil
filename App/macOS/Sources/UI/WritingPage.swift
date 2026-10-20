import APCore
import SwiftUI

/// "My writing": samples of the user's own writing for the "Like me" style, via a short interview.
struct WritingPage: View {
    @Bindable var app: AppModel
    @State private var editing: WritingSample?
    @State private var editingPrompt: InterviewPrompt?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "My writing", subtitle: "Samples of how you write, so the Like me style sounds like you. Type them; don't dictate.")

                Card {
                    let count = app.writingSamples.count
                    let enough = count >= InterviewPrompt.minimumSamples
                    HStack(spacing: 12) {
                        Image(systemName: enough ? "checkmark.seal.fill" : "pencil.and.list.clipboard")
                            .font(.title2).foregroundStyle(enough ? .green : Color.pencil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(enough ? "Like me is ready" : "Write \(InterviewPrompt.minimumSamples - count) more to turn on Like me")
                                .font(.headline)
                            Text("\(count) sample\(count == 1 ? "" : "s"). For each note, Like me shows the model your two closest samples. More variety means a better match.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                Card(title: "Interview") {
                    Text("Answer in 100–300 words, the way you'd normally write it. Skip any that don't fit you.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(InterviewPrompt.all) { prompt in
                        let answer = app.writingSamples.first { $0.promptID == prompt.id }
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: answer == nil ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(answer == nil ? Color.secondary : Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prompt.title).font(.headline)
                                Text(prompt.prompt).font(.callout).foregroundStyle(.secondary)
                                if let answer {
                                    Text("\(answer.wordCount) words").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button(answer == nil ? "Answer…" : "Edit…") {
                                editingPrompt = prompt
                                editing = answer ?? WritingSample(kind: prompt.kind, text: "", promptID: prompt.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Card(title: "Your own samples") {
                    let own = app.writingSamples.filter { $0.promptID == nil }
                    if own.isEmpty {
                        Text("Paste in emails, posts or notes you've written. Pick the kind so the right ones get matched.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(own) { sample in
                        HStack {
                            Text(sample.kind).font(.caption.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            Text(sample.text).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            Button("Edit…") { editingPrompt = nil; editing = sample }
                        }
                    }
                    Button {
                        editingPrompt = nil
                        editing = WritingSample(kind: "other", text: "")
                    } label: {
                        Label("Add a sample", systemImage: "plus")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .sheet(item: $editing) { sample in
            SampleEditor(sample: sample, prompt: editingPrompt) { saved in
                app.saveSample(saved)
            } delete: {
                app.writingSamples.removeAll { $0.id == sample.id }
            }
        }
    }
}

private struct SampleEditor: View {
    @State var sample: WritingSample
    let prompt: InterviewPrompt?
    let save: (WritingSample) -> Void
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt {
                Text(prompt.title).font(.system(size: 22, weight: .bold, design: .serif))
                Text(prompt.prompt).foregroundStyle(.secondary)
            } else {
                Text("Writing sample").font(.system(size: 22, weight: .bold, design: .serif))
                Picker("Kind", selection: $sample.kind) {
                    ForEach(InterviewPrompt.kinds, id: \.self) { Text($0).tag($0) }
                }
                .fixedSize()
            }
            TextEditor(text: $sample.text)
                .font(.system(.body, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
                .frame(minHeight: 260)
            HStack {
                let words = sample.wordCount
                let inRange = InterviewPrompt.wordRange.contains(words)
                Text("\(words) words")
                    .monospacedDigit()
                    .foregroundStyle(inRange ? .green : .secondary)
                if prompt != nil, !inRange {
                    Text(words < InterviewPrompt.wordRange.lowerBound ? "aim for at least 100" : "300 is plenty")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !sample.text.isEmpty {
                    Button("Delete", role: .destructive) { delete(); dismiss() }
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(sample); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sample.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620, height: 480)
    }
}
