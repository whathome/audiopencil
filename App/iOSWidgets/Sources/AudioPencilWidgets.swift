import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AudioPencilWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        RecordControl()
    }
}

/// Pencil amber (the extension has its own copy of the colour asset).
private let pencil = Color("AccentColor")

// MARK: Live Activity

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenRecording(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StateMark(state: context.state).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(state: context.state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Controls(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(pencil)
            } compactTrailing: {
                Clock(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(pencil)
            }
            .keylineTint(pencil)
        }
    }
}

private struct LockScreenRecording: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                StateMark(state: state)
                Spacer()
                Clock(state: state)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Controls(state: state)
        }
    }
}

/// "Recording · EN", or "Paused" with the reason when there is one.
private struct StateMark: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(state.isPaused ? "Paused" : "Recording")
            } icon: {
                Image(systemName: state.isPaused ? "pause.circle.fill" : "record.circle")
                    .foregroundStyle(pencil)
            }
            .font(.headline)
            .foregroundStyle(.white)
            Text(verbatim: [state.notice, state.language].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

/// Counts up while recording and stops while paused, without the app having to update it.
private struct Clock: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.clockStart...Date.distantFuture, pauseTime: state.pausedAt, countsDown: false, showsHours: false)
            .multilineTextAlignment(.trailing)
    }
}

private struct Controls: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            if state.isPaused {
                Button(intent: ResumeRecordingIntent()) {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
            } else {
                Button(intent: PauseRecordingIntent()) {
                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
            }
            Button(intent: StopRecordingIntent()) {
                Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .tint(pencil)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white.opacity(0.2))
        .font(.callout.weight(.semibold))
    }
}

// MARK: Control Centre, Lock Screen and Action Button

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.weshopkins.audiopencil.record") {
            ControlWidgetButton(action: ToggleRecordingIntent()) {
                Label("Record a Note", systemImage: "mic.fill")
            }
        }
        .displayName("Record a Note")
        .description("Starts an Audio Pencil recording, or stops and saves the one that's running.")
    }
}
