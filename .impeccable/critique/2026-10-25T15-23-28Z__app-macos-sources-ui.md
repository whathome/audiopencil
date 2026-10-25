---
target: macOS desktop UI
total_score: 28
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:/Users/wehopkin/Development/audiopencil/App/macOS/Sources/UI"
timestamp: 2026-10-25T15-23-28Z
slug: app-macos-sources-ui
closed: true
---
Method: dual-agent (A: 2aeb3682-effa-4006-a5b3-8099e1c673df · B: e55e3fa7-3934-453c-9489-9b12046ca810)

## Desktop critique: 28/40 — Good

**A solid native foundation. The biggest opportunity is trustworthy behavior, not a visual redesign.**

### Design specificity

Audio Pencil feels authored for its purpose: visible hotkey gestures, local-model feedback, spoken-text typography and the Obsidian handoff reinforce a quiet writing tool. Preserve that identity.

The HTML/CSS detector returned zero findings, but **does not validate SwiftUI**. Fresh native screenshots covered Dictation, Storage, Meetings and 520-point Storage. No browser overlay applies. Destructive actions and failure recovery were assessed from source, not exercised; VoiceOver, keyboard focus and measured contrast remain unverified. Live meeting-audio permission/recording verification remains intentionally incomplete from the earlier session.

### Design health

| Heuristic | Score | Key observation |
|---|---:|---|
| Visibility of system status | 3/4 | Strong progress states; processing context disappears on disabled pages. |
| Match with the real world | 4/4 | Familiar gestures and plain-language explanations. |
| User control and freedom | 2/4 | Cancel retains a new style; sample deletion lacks recovery. |
| Consistency and standards | 3/4 | Cohesive native controls; some actions break their label's promise. |
| Error prevention | 2/4 | Writing samples lack the deletion safeguards used elsewhere. |
| Recognition over recall | 3/4 | Good contextual guidance; error recovery requires diagnosis. |
| Flexibility and efficiency | 3/4 | Useful shortcuts; broad processing locks impede unrelated tasks. |
| Aesthetic and minimalist design | 3/4 | Restrained hierarchy; the writing interview is less distilled. |
| Error recovery | 2/4 | Unrelated dictation errors lead to Permissions. |
| Help and documentation | 3/4 | Setup guidance is stronger than unexpected-failure guidance. |
| **Total** | **28/40** | **Good** |

### What's working

- **Learning by doing:** the dictation test area teaches the actual interaction, rather than adding a separate tutorial.
- **Honest local processing:** model preparation and progress feedback explain why the Mac sometimes needs time.
- **Consistent desktop structure:** fresh captures show aligned Settings cards, a working narrow-layout provider menu and uniformly sized sidebar symbols.

### Priority issues

1. **P1 — Protect saved writing samples.** Delete removes and syncs a saved sample without confirmation or visible Undo. A stray click risks losing valuable personal writing. Add Undo or a confirmation naming the sample. Evidence: `App/macOS/Sources/UI/WritingPage.swift:89–94,154–155`. Suggested command: `/impeccable harden`.

2. **P2 — Make Cancel actually cancel.** A new style is added before its editor opens; Cancel/Escape dismisses the editor but leaves the style behind. Keep new styles as drafts until Save. Evidence: `App/macOS/Sources/UI/StylesPage.swift:29–32,217–218`. Suggested command: `/impeccable harden`.

3. **P2 — Match recovery to the error.** Dictation directs every error to Permissions, including transcription and rewrite failures. Users reach a settings page that cannot fix the problem. Offer contextual recovery: Permissions, model retry, or a nonblocking raw-text fallback notice. Evidence: `App/macOS/Sources/UI/DictationPage.swift:302–303`; `App/macOS/Sources/DictationController.swift:440–443,492–496`. Suggested command: `/impeccable clarify`.

4. **P2 — Narrow the meeting-processing lock.** Processing disables entire Dictation, Styles, My writing and Settings pages, while progress is shown in meeting review. Navigating elsewhere can produce an unexplained inert interface. Keep safe editing and inspection available; disable only conflicting actions and expose persistent processing status. Evidence: `App/macOS/Sources/UI/MainWindow.swift:79–84`; `App/macOS/Sources/UI/MeetingsPage.swift:302–306`. Suggested command: `/impeccable harden`.

### Cognitive load and emotional journey

**Moderate, localized load:** two checklist concerns are weak chunking of the 11-prompt writing interview and recall-heavy error recovery. Six labeled navigation destinations and six Settings categories are reasonable native navigation—not reasons to reorganize again. Grouping, task focus and progressive disclosure are generally strong; all 11 prompts are rendered, not necessarily simultaneously visible.

The journey starts calmly and rewards users when speech becomes text. Confidence drops during incorrect recovery or unexplained processing locks. Preserve the quiet tone; make those failure moments more reassuring.

### Persona red flags

- **First-timer:** a transcription failure sends them to already-granted permissions, with no useful next step.
- **Power user:** Escape leaves a new style behind; meeting processing blocks otherwise independent work.
- **Keyboard/VoiceOver user:** disabled pages lack local processing explanations. Focus visibility and announcements need direct verification.

### Minor observations

Dictation instructions look faint in fresh captures; give essential test-area guidance more prominence. The Settings warning badge blends into its amber selected background. Meetings' disabled Start Meeting button needs an adjacent reason, such as choosing a call app when that is the missing prerequisite. These are visual/clarity observations, not measured accessibility failures.

### Decisions to revisit

Define Cancel as a no-persistence contract, give personal writing the same deletion protection as generated notes, and identify exactly which actions genuinely conflict with meeting processing.
