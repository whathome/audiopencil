---
target: App/iOS/Sources/UI
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:/Users/wes/Development/audiopencil/App/iOS/Sources/UI"
timestamp: 2026-10-22T21-49-44Z
slug: app-ios-sources-ui
---
Method: design review only (detector not applicable, native platform)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Waiting reasons and paused-while-recording now shown; copy failures only haptic |
| 2 | Match System / Real World | 3 | Daily-note heading field unlabelled ("## Audio Pencil") |
| 3 | User Control and Freedom | 2 | One tap discards a recording, no undo; waiting recordings can't be removed |
| 4 | Consistency and Standards | 3 | Sheet "Discard" in amber, not destructive red |
| 5 | Error Prevention | 2 | 56 pt discard ✕ beside Stop in the thumb zone, no confirmation |
| 6 | Recognition Rather Than Recall | 3 | Meeting and Daily note visible before and during recording |
| 7 | Flexibility and Efficiency | 3 | Lock Screen, Control Centre, Action Button, Siri; copy everywhere |
| 8 | Aesthetic and Minimalist Design | 3 | Settings leads with an unusable Daily note group |
| 9 | Error Recovery | 2 | Missing writing model note has no way forward; failed copy silent |
| 10 | Help and Documentation | 3 | Footers explain the why |
| **Total** | | **27/40** | **Acceptable** |

## Design Specificity Verdict
Recorder authored to DESIGN.md (serif words, one amber control, quiet clock); Forms native. Notes tab rows are generic (no duration, audio or meeting marker). Deterministic scan: not applicable (native platform).

## Priority Issues
1. [P1] One tap throws away a recording: RecordView ✕ (cancel) and the Write it as Discard, no confirmation or undo. Fix: confirmationDialog with the length for recordings over ~30 s. Command: harden.
2. [P2] "The writing model isn't on this iPhone yet" on Write it as is a dead end. Fix: link or button to get the writing model (1.7 GB). Command: onboard.
3. [P2] Waiting recordings can't be removed; a failing one blocks the queue. Fix: swipe to delete with confirmation. Command: harden.
4. [P2] Settings: Daily note group second, three controls greyed without storage; heading TextField unlabelled; disabled text not dimmed. Fix: one "Daily note" row in the core group opening its own page with a labelled field. Command: layout.
5. [P2] Copy failure (old filed note, storage unreachable) only an error haptic. Fix: inline message plus VoiceOver announcement. Command: harden.

## Persona Red Flags
- Casey: discard ✕ a thumb from Stop; leaving pauses writing, said only on Notes.
- Jordan: styles offered that can't run yet; Daily note group with core-plugin talk before storage is set up.
- Sam: idle clock fixed 44 pt; failed copy only haptic; language badge looks tappable but disabled with one language.
- Walker: rows lack duration; 25 min and 20 s recordings look alike.

## Minor Observations
- Record placeholder says "then written up as a note"; copy exists now.
- Sheet Discard tinted amber.
- Copied row File doesn't say where it goes without storage.
- Notes empty state doesn't mention Copy to Clipboard.

## Questions to Consider
- "Recently discarded" for a day instead of a confirmation?
- Durations and meeting/audio markers on Notes rows?
- Write it as showing only runnable styles plus a row to get the writing model?
