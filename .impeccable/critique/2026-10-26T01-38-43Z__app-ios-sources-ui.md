---
target: ios
total_score: 28
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:/Users/wes/Development/audiopencil/App/iOS/Sources/UI"
timestamp: 2026-10-26T01-38-43Z
slug: app-ios-sources-ui
---
Method: design review only (detector not applicable, native platform)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Meetings progress is a bare ProgressView(text) |
| 2 | Match System / Real World | 3 | "Play / Pause Recording", "File / Update Note" slash labels |
| 3 | User Control and Freedom | 3 | "Mark Reviewed" also files, silently |
| 4 | Consistency and Standards | 2 | Two recorders that look like different apps; copy feedback differs |
| 5 | Error Prevention | 3 | Long discards confirmed on both tabs |
| 6 | Recognition Rather Than Recall | 3 | Filed meetings absent from Notes |
| 7 | Flexibility and Efficiency | 3 | Lock Screen, Siri, Action Button; copy everywhere |
| 8 | Aesthetic and Minimalist Design | 2 | New Meeting repeats four paragraphs; review has ~10 actions |
| 9 | Error Recovery | 3 | New Meeting "Download … in Settings" without a link |
| 10 | Help and Documentation | 3 | Consent line clipped behind the Start bar |
| **Total** | | **28/40** | **Good** |

## Design Specificity Verdict
Record is the most authored screen (serif words, one amber control, clock). Meetings' recorder is a generic settings Form (toggles, a progress bar as level meter, text buttons). Deterministic scan: not applicable (native platform).

## Priority Issues
1. [P1] Two recorders: Meetings' recording state (MobileMeetingsView recording Form: largeTitle clock, ProgressView as level meter, text buttons) shares nothing with Record's instrument. Fix: reuse Record's circle controls, clock and level bars; Form for setup only. Command: layout.
2. [P2] Meeting review offers ~10 actions; Mark Reviewed silently files. Fix: one primary File/Update Note button, the rest in a ··· menu; say Mark Reviewed files or stop it. Command: distill.
3. [P2] Filed meetings don't appear in Notes › Filed. Fix: list them with a people marker, opening their review. Command: layout.
4. [P2] New Meeting repeats explanation every visit; consent line clipped behind the Start bar; models text without a link; duplicate back + clock toolbar buttons. Fix: fold explanation, consent in the Start bar, link to Models, drop the clock. Command: distill.
5. [P3] Slash labels ("Play / Pause Recording", "File / Update Note"); Copy Meeting Note silent. Fix: state labels; reuse CopyButton. Command: clarify.

## Persona Red Flags
- Casey: meeting Pause/Stop/Discard as stacked full-width rows.
- Jordan: "Process after recording" unexplained; Retry/Process buttons expose pipeline steps.
- Sam: level meter announced as progress; Play/Pause label doesn't say which.
- Meeting host: note not with other notes; setup prose every time.

## Minor Observations
- Older Filed rows lack a length.
- "New Meeting" both a list row and a toolbar +.
- Meetings and Notes word device-only status differently.

## Questions to Consider
- Long-press Record to start a meeting, Meetings tab only for review?
- File meetings straight away and review on the Obsidian board?
- One Library tab for notes and meetings?
