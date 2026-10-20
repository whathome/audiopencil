import APTranscription
import SwiftUI

/// First-time model preparation: the step, a running clock against the estimate, and a bar that fills
/// towards it (never quite full until it's done). The clock is the point: Core ML compiles in a system
/// process, so without it a long preparation looks like a hang.
struct PreparationStatus: View {
    let title: String
    let preparation: ModelPreparation
    /// Dictation waits for it (the model in use) rather than it running in the background.
    var blocking = true

    var body: some View {
        TimelineView(.periodic(from: preparation.startedAt, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(preparation.startedAt)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: title).font(.callout.weight(.medium))
                    Spacer()
                    Text(Self.progressText(elapsed: elapsed, estimate: preparation.estimatedSeconds))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(elapsed / max(preparation.estimatedSeconds, 1), 0.95))
                    .tint(Color.pencil)
                Text(elapsed > preparation.estimatedSeconds * 1.2
                     ? "Step \(preparation.step) of \(preparation.steps): \(preparation.part). Taking longer than usual, still working. Happens once per model."
                     : blocking
                     ? "Step \(preparation.step) of \(preparation.steps): \(preparation.part). Happens once per model; dictation waits until it's done."
                     : "Step \(preparation.step) of \(preparation.steps): \(preparation.part). Runs in the background; dictation keeps working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "4:12 of about 12 min"
    static func progressText(elapsed: Double, estimate: Double) -> LocalizedStringResource {
        estimate < 120
            ? "\(clock(elapsed)) of about \(Int(estimate.rounded())) s"
            : "\(clock(elapsed)) of about \(Int((estimate / 60).rounded())) min"
    }
}
