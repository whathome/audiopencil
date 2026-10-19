# Audio Pencil

Private, fully on-device dictation and summarisation for Mac (and later iPhone). See [docs/PRD.md](docs/PRD.md).

**Status:** milestone 1 (bare loop). Double-tap Fn, talk, stop, and the raw transcript is pasted into the active field.

## Build and run

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), macOS 15+, Apple silicon.

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
| Start | Double-tap **Fn** (or ⌃⌥Space) |
| Stop and paste | Single tap **Fn** or **Return** (configurable: double-tap Fn; Return can be turned off) |
| Cancel | **Esc**, at any point; nothing is pasted |

The text is left on the clipboard as well. If the focused element clearly isn't a text field, nothing is pasted and the indicator shows "On clipboard".

The hotkey doesn't work while macOS Secure Input is on: password fields, Terminal with Secure Keyboard Entry, some password managers.

## Layout

```
project.yml                   XcodeGen definition (app target, signing, schemes)
Config/Signing.xcconfig       ad-hoc by default; includes Signing.local.xcconfig if present
App/macOS/Sources             thin macOS app: event tap, paste, indicator panel, windows
Packages/AudioPencilKit       shared Swift package (reused by iOS in phase 2)
  APCore                      settings, Fn tap detection, async lock, diagnostics
  APAudio                     16 kHz mono capture, levels, synthesised cues
  APModels                    ModelCoordinator (one large model resident at a time), catalogue
  APTranscription             WhisperKit wrapper, streaming transcriber
```

Memory rule: every model load goes through `ModelCoordinator.ensureLoaded`, which unloads whatever else is resident first. The summarisation LLM (milestone 3) is another `ManagedModel`, so Whisper and the LLM can't be loaded at the same time.

## Tests

```bash
xcodebuild -project AudioPencil.xcodeproj -scheme AudioPencil -derivedDataPath build/DerivedData test
```

There's also an opt-in end-to-end WhisperKit test. It synthesises speech with `say`, streams it through the real model, and prints stop-to-text latency:

```bash
cd Packages/AudioPencilKit && AUDIOPENCIL_INTEGRATION=1 swift test --filter WhisperIntegration
```

Logs: `log stream --predicate 'subsystem == "com.weshopkins.audiopencil"'`. Each dictation logs its stop→text and stop→paste times.

## Milestones

1. **Bare loop** (this): hotkey, record, live transcription, stop, paste raw text.
2. Dictation polish: mic priority list, clipboard indicator details, settings, Dock/menu-bar mode, launch at login, custom vocabulary.
3. LLM and styles (MLX Swift): model swapping, presets, picker, per-app defaults.
4. Storage: offline-first queue, Nextcloud WebDAV, Login Flow v2, shared config with ETag merge.
5. Long-form and Obsidian: promotion, retention, notes and frontmatter, review prompt, Bases file.
6. "Like me" and model discovery.
