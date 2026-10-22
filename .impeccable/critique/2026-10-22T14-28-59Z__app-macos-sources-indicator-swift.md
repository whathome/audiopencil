---
target: App/macOS/Sources/Indicator.swift
total_score: 27
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/wes/Development/audiopencil/App/macOS/Sources/Indicator.swift"
target_fingerprint: "sha256:251f3db8c66119a6ddbc2dc327e4dd5c6c9bf08bceb7e99fc967142bb25b6f03"
target_path: /Users/wes/Development/audiopencil/App/macOS/Sources/Indicator.swift
timestamp: 2026-10-22T14-28-59Z
slug: app-macos-sources-indicator-swift
---
Method: design review only (detector not applicable, native platform)

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Daily-note link is a bare 9 pt calendar glyph; silence is a red ✕ |
| 2 | Match System / Real World | 3 | "Paste only" beside "Paste" during push-to-talk reads as a contradiction |
| 3 | User Control and Freedom | 3 | Cycling is forward-only; overshooting costs a full lap |
| 4 | Consistency and Standards | 2 | Three click models (cycle, cycle, menu), only the chip looks clickable; two clipboard capsules side by side |
| 5 | Error Prevention | 2 | In push-to-talk the Paste toggle can still be clicked to Note, filing a full note |
| 6 | Recognition Rather Than Recall | 3 | Daily-note toggle only in the menu |
| 7 | Flexibility and Efficiency | 3 | No key for Paste/Note/Meeting or the destination |
| 8 | Aesthetic and Minimalist Design | 3 | Push-to-talk adds a fifth element that duplicates the fourth |
| 9 | Error Recovery | 2 | Errors are one truncated line that vanish after 3 s, no action |
| 10 | Help and Documentation | 3 | Menu tip and VoiceOver hints; no hover tooltips possible |
| **Total** | | **27/40** | **Acceptable** |

## Design Specificity Verdict
Authored and specific at the core (amber style chip with number badge, non-activating panel). The newer delivery toggle, language badge and destination badge are generic grey capsules that read as status labels, not controls. Deterministic scan: not applicable (native platform).

## Priority Issues
1. [P1] Push-to-talk shows two competing "where it goes" controls. "Paste" (delivery toggle) beside "Paste only" (destination badge), same icon. Clicking the first sets Note, which files a full long-form note and ignores the destination (DictationController.swift:390). Fix: in push-to-talk hide DeliveryToggle; the destination badge takes its slot: "Paste" → "Paste + Daily note" → "Paste + Inbox". Command: distill.
2. [P1] Clickable controls don't look clickable. DeliveryToggle and DestinationBadge are flat capsules without chevron; the panel never gets hover. During push-to-talk a click is the only way to choose. Fix: shared cycle affordance (glyph + hairline like the chip), pointing-hand cursor set from gateMouse when over a control frame. Command: polish.
3. [P2] The centred pill changes width (red ✕ inserted after 1.5 s quiet, Paste/Note/Meeting widths, calendar glyph), so targets move under the pointer during repeated clicks. Fix: fixed toggle width (widest label), no-audio shown inside the meter, anchor the leading edge while recording. Command: layout.
4. [P2] Unlabelled icons: daily-note link is a tiny calendar; no-audio red ✕ reads as close. Fix: mic.slash in the meter; "Note + Daily" text. Command: clarify.
5. [P2] Errors and notices: lineLimit(1), 3 s flash, no action ("Microphone access needed"). Fix: two lines to 460 pt, persist until the next hotkey, click to open System Settings. Command: harden.

## Persona Red Flags
- Alex: no key for delivery or destination; forward-only cycling.
- Sam: panel never key, so VoiceOver can't reach toggle/badge/chip despite good labels; mirror in the menu bar menu.
- Riley: push-to-talk + Paste click → long-form note; "Journal/2026/Log.md" shows as "+ Log"; ✕ insertion shifts targets.

## Minor Observations
- Menu header "Deliver this dictation as" (styles) collides with "When you stop" (delivery); "Write it as" would match the iPhone.
- Amber now marks chip, Note text and push destination; DESIGN.md reserves it for the chip and long-form warning.
- DESIGN.md Recording Pill spec omits the delivery toggle, language badge and destination badge.
- PickerRow.choice body over-indented.

## Questions to Consider
- Push-to-talk with no on-pill decision: a second held hotkey for "paste and add to the daily note"?
- Language badge on every recording, or only when it differs from the app's usual language?
- Clickable things as amber outlines, everything else plain white text?
