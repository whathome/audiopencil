---
target: Mac app UI
total_score: 29
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/wes/Development/audiopencil/App/macOS/Sources/UI"
timestamp: 2026-10-20T01-53-38Z
slug: app-macos-sources-ui
---
Method: design review only (detector not applicable, native platform)
Target: Mac app main window (6 pages), recording indicator, review sheet. Operate mode. Dark appearance, 1100 pt window. Review sheet capture predates last ReviewView change.

## Design Health Score
| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | Indicator has no elapsed time; 5-min paste-to-note switch is invisible |
| 2 | Match System / Real World | 3 | WebDAV, SmolLM3 3B, 400 ms, Nextcloud 27.1.11 jargon |
| 3 | User Control and Freedom | 3 | Esc, Skip, reset, trash |
| 4 | Consistency and Standards | 2 | Two settings idioms; Settings page on a different left edge |
| 5 | Error Prevention | 3 | Like me gated, shortcut clash blocked, backups |
| 6 | Recognition Rather Than Recall | 3 | Indicator chip never shows the style's number key |
| 7 | Flexibility and Efficiency | 3 | No Cmd-1..6 page shortcuts |
| 8 | Aesthetic and Minimalist Design | 3 | Stat tiles and empty activity grid outweigh the output |
| 9 | Error Recovery | 3 | Banners with actions, Repair with backups |
| 10 | Help and Documentation | 3 | Inline footers, How it works, vault guide |
| Total | | 29/40 | Good |

## Design Specificity Verdict
Half authored, half kit. Specific: keycap gestures, serif titles and output, amber tint, indicator pill. Generic: rounded cards with uppercase tracked labels everywhere, big-number stat tiles, GitHub activity grid. Missed: the product's output (your words, in serif) sits at the bottom of the home page.

## Priority Issues
- [P1] Settings split across Settings, Notes and Vault in two visual languages (grouped Form vs custom cards; different left edge). Fix: grouped Form for all configuration, same page edge; cards only for status/content. /impeccable layout
- [P1] Paste-to-note promotion invisible while recording. Fix: elapsed time in pill after ~30 s; chip turns "-> Note" near threshold with a soft cue. /impeccable clarify
- [P2] Home page leads with machinery; Last dictation last; 4 equal stat tiles; "1 days" pluralisation. Fix: lead with last dictation, one-line status, compact stats. /impeccable distill
- [P2] Zero accessibilityLabels: icon-only rail, meter, activity grid, colour-only dots, keycaps read "fn fn". /impeccable audit

## Persona Red Flags
- Alex: no Cmd-1..6, no Cmd-N on Styles; chip hides number keys; Edit is a small link, card not clickable.
- Sam: rail items unnamed; colour-only states; focus rings disabled on custom sidebar buttons.
- Mid-thought dictator: silent long-form promotion; last result buried; no "always skip review".

## Minor Observations
- Notes: How it works (bordered) vs Open board (link) mismatch; retention footnote jargon.
- Vault: full-width segmented control reads as tabs; monospace paths only here.
- My writing: wall of 11 identical Answer buttons; show progress and highlight next.
- Styles: Raw card lacks a trailing control, breaking alignment.
- Review sheet (stale capture): duplicate Folder label, literal markdown in preview, third-person summary.
- 9 fixed .system(size:) fonts; matters for iOS phase 2.

## Questions to Consider
- Home page as your last few dictations, status only on trouble?
- My writing as a Like me onboarding inside Styles?
- Indicator that says what will happen at stop?
