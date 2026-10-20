# Audio Pencil

Private, fully on-device dictation and summarisation for Mac (and later iPhone). See [docs/PRD.md](docs/PRD.md).

**Status:** milestone 5 (notes in Obsidian). Long recordings become reviewed notes with audio in your vault; a Bases board, guide and sample notes are created on first run. Milestone 4 (vault and sync): Connect your Obsidian vault on Nextcloud or in a folder on this Mac (e.g. iCloud Drive); styles, vocabulary and per-device settings sync through `Audio Pencil/Settings.md` in the vault. Hold Fn for a raw transcript, or double-tap Fn to dictate in a style (Polished, Diary, Professional, or your own), rewritten on this Mac by a small MLX language model.

## Build and run

Requirements: Xcode 26.3+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), macOS 15+, Apple silicon, and Xcode's Metal toolchain for MLX (`xcodebuild -downloadComponent MetalToolchain`, once).

MLX is pinned to `mlx-swift-lm` 3.31.4 / `mlx-swift` 0.31.4, the last versions that build with Swift 6.2. Newer `mlx-swift` needs Swift tools 6.3, so move up after updating Xcode.

```bash
xcodegen generate          # creates AudioPencil.xcodeproj (not committed)
open AudioPencil.xcodeproj # then Run, or:
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData -allowProvisioningUpdates build
```

### Signing (do this once)

Without a team the app is ad-hoc signed, and macOS treats every rebuild as a new app: you'd have to grant Accessibility again after each build. To fix that for free:

1. Xcode › Settings › Accounts › add your Apple ID (a free Personal Team is fine). If no "(Personal Team)" appears, accept the agreement at developer.apple.com/account, then sign out and back in.
2. Open the project and pick the team under the AudioPencil target › Signing & Capabilities. Note the `DEVELOPMENT_TEAM` value Xcode writes into the project.
3. Run `scripts/set-team.sh <TEAMID>`. It writes the gitignored `Config/Signing.local.xcconfig`, which survives `xcodegen generate`.
4. `xcodegen generate`, then build with `-allowProvisioningUpdates` (Xcode creates the Apple Development certificate on the first build).
5. Remove the old Audio Pencil entry under Accessibility and grant it one last time.

### First run

The main window is a setup checklist:

- **Microphone**: needed to record.
- **Accessibility**: needed to watch the Fn key and to paste. After granting it, the hotkey starts within a second without a relaunch.
- **Fn key free**: System Settings › Keyboard › "Press 🌐 key to" must be **Do Nothing**, and the Dictation shortcut must not be "Press 🌐 twice". Otherwise macOS acts on the same key.
- **Model**: the first launch downloads Whisper small.en (~480 MB) to `~/Library/Application Support/AudioPencil/Models`. Core ML then compiles it for this Mac, which takes a minute or two once.

Input Monitoring is shown for diagnosis but isn't requested: the active event tap works under Accessibility.

## Using it

| Action | Keys |
| --- | --- |
| Raw transcript (push to talk) | Hold **Fn**, talk, release. Another key while holding cancels, so Fn still works as a modifier |
| Dictate in a style | Double-tap **Fn** (or ⌃⌥Space). Starts in the style last used in this app |
| Switch style while talking | Click the style name in the recording indicator for a menu, or press **1–9** (**0** for raw). The menu shows each style's number |
| Stop and paste | Single tap **Fn** or **Return** (configurable: double-tap Fn; Return can be turned off) |
| Cancel | **Esc**, at any point, including during a rewrite; nothing is pasted |

Styles (Styles page): **Raw** (0), **Polished** (1, the default: cleaned-up text in your words), **Diary** (2, filler removed, wording kept), **Professional** (3, summary plus key points), and **Like me** (4, milestone 6). Edit their instructions, renumber them, or add your own. Optionally (Settings), a picker appears after stop with this app's style preselected; it picks automatically after a second unless you press a number.

The writing model (default SmolLM3 3B, 1.7 GB, downloaded once from the Styles page) never sits in memory alongside Whisper. A styled dictation swaps Whisper out, rewrites, then swaps Whisper back in the background. On the M1 Air a styled quick note takes about 5–7 s from stop to paste; raw is about 0.5 s. See [docs/benchmarks](docs/benchmarks) for the model comparison.

Recording starts about 0.05 s after the second Fn tap: the mic comes on at the first tap and goes off again within a second if no second tap follows. Turn this off in Settings if the brief mic-indicator flash on a lone Fn tap bothers you.

Settings (⌘,) also has:

- **Microphones**: a priority list. The first connected one is used, otherwise the system default. Unplugged entries stay in the list.
- **Custom vocabulary**: one term per line, passed to Whisper as spelling hints. In a test, "next cloud / web dev / whisker kit" became "Nextcloud / WebDAV / WhisperKit".
- **Menu bar only** (hides the Dock icon) and **Launch at login**.

### Notes

A hotkey recording longer than the long-form threshold (5 minutes by default; Notes page) doesn't paste. Instead, Audio Pencil:

1. Keeps the audio (`Audio Pencil/Recordings/*.m4a`, AAC mono, about 1.2 MB for 5 minutes).
2. Writes it up in the recording's style. Long transcripts go section by section, and summaries are combined from per-section notes.
3. Suggests a title and tags (preferring the tag list in the settings file).
4. Sends a notification. The review window lets you edit the title, tags and folder, then **Approve** (`status: reviewed`) or **Skip** (`status: needs-review`). Pending reviews wait on the Mac, and the Notes page lists them.

Notes are `YYYY-MM-DD HHmm Title.md` in the style's folder (Styles page), or `Audio Pencil/Notes`. They carry the PRD frontmatter (`type`, `style`, `status`, `recorded`, `duration`, `device`, `mode`, `tags`, `audio`), with the transcript folded in a callout under rewritten text. Uploads go through the offline queue. Optionally, quick dictations are saved too (no audio, no review).

On first connecting a vault the app adds `Audio Pencil/Audio Pencil.base` (Kanban "Professional review" by status, "Diary", "All recordings"), `Audio Pencil guide.md`, and three sample notes tagged `sample`. The board and guide are recreated if missing; the samples never are.

### Vault settings file

Once a vault is connected (Vault page), the app keeps `Audio Pencil/Settings.md` in it: a short note with one `yaml` block holding the shared styles, vocabulary and tags, plus a section per device (microphones, hotkey options, models). Edit it in Obsidian and the app picks the changes up within a minute, or when you switch to it. Changes made on both sides merge field by field against the last synced version. If both sides changed the same style, the vault's version wins. If the YAML has a mistake, syncing pauses until you fix it, and the file is never overwritten. Per-app style memory and stats stay on the device.

The text is left on the clipboard as well. If the focused element clearly isn't a text field, nothing is pasted and the indicator shows "On clipboard".

The hotkey doesn't work while macOS Secure Input is on: password fields, Terminal with Secure Keyboard Entry, some password managers.

## Layout

```
project.yml                   XcodeGen definition (app target, signing, schemes)
Config/Signing.xcconfig       ad-hoc by default; includes Signing.local.xcconfig if present
App/macOS/Sources             thin macOS app: event tap, paste, indicator panel, windows
Packages/AudioPencilKit       shared Swift package (reused by iOS in phase 2)
  APCore                      settings, Fn tap/hold detection, styles, prompt builder, per-app memory, stats
  APAudio                     16 kHz mono capture (off the main thread), mic catalogue, levels, cues
  APModels                    ModelCoordinator (one large model resident at a time), catalogue
  APTranscription             WhisperKit wrapper, streaming transcriber
  APSummary                   MLX writing model (SmolLM3 by default), Hugging Face download, benchmark
  APStorage                   vault storage: Nextcloud WebDAV + Login Flow v2, local folder (iCloud Drive), Keychain
  APSync                      shared settings file (YAML in Markdown), three-way merge, offline upload queue
```

Memory rule: every model load goes through `ModelCoordinator.ensureLoaded`, which unloads whatever else is resident first. Whisper and the writing model are both `ManagedModel`s, so they can't be loaded at the same time.

## Tests

```bash
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData test
```

There's also an opt-in end-to-end WhisperKit test. It synthesises speech with `say`, streams it through the real model, and prints stop-to-text latency:

```bash
cd Packages/AudioPencilKit && AUDIOPENCIL_INTEGRATION=1 swift test --filter WhisperIntegration
```

Debug builds can be driven without key presses, for end-to-end timing. These dictations never paste; the transcript goes to the log. Use `say` to talk to the mic:

```bash
scripts/debug-dictation.sh tap-start   # or: start (cold), warm (a lone first tap), stop, cancel
scripts/debug-dictation.sh key:fnDown 0.6 key:fnUp   # simulated keys: fnDown, fnUp, other, escape, return, 0–9
```

Writing-model benchmark (downloads each candidate; must run through xcodebuild for Metal):

```bash
cd Packages/AudioPencilKit && TEST_RUNNER_AUDIOPENCIL_BENCH=1 TEST_RUNNER_AUDIOPENCIL_BENCH_OUT=$PWD/../../docs/benchmarks/run.md xcodebuild test -scheme AudioPencilKit-Package -destination platform=macOS -only-testing:APSummaryTests
```

Logs: `log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'`. Each dictation logs its stop→text and stop→paste times.

## Milestones

1. **Bare loop** (done): hotkey, record, live transcription, stop, paste raw text.
2. **Dictation polish** (done): instant start, mic priority list, Dock/menu-bar mode, launch at login, custom vocabulary.
3. **Styles** (done): hold-for-raw, MLX writing model with swapping, presets, number keys and clickable style menu, picker, per-app defaults, Styles page.
4. **Vault and sync** (done): Nextcloud (Login Flow v2) or a local/iCloud folder, folder selection, shared YAML settings file with three-way merge and ETag retries, offline upload queue.
5. **Notes in Obsidian** (this): long-form promotion (5 min, configurable), m4a audio, sectioned summaries, suggested title and tags, review prompt and notification, notes and frontmatter via the offline queue, optional saving of quick dictations, Bases board, guide and samples. One-year audio retention moves to milestone 6.
6. "Like me" and model discovery.
