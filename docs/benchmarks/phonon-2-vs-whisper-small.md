# Phonon-2 against Whisper Small (English) on the M1 MacBook Air (8 GB)

[Phonon-2](https://huggingface.co/FermionResearch/Phonon-2) is FermionResearch's 2.1-bit, quantization-aware
retrain of NVIDIA's Parakeet TDT 0.6B v3. It is English only and licensed CC-BY-4.0. It runs on the Neural Engine
through the Core ML build [FluidInference/phonon-2-coreml](https://huggingface.co/FluidInference/phonon-2-coreml)
and the [FluidAudio](https://github.com/FluidInference/FluidAudio) Swift package. Is it worth replacing
`openai_whisper-small.en`, the app's English model?

**Recommendation: yes, as the English engine on the Mac, but not as a drop-in swap.** It made about a quarter fewer
errors than Whisper Small on clean speech and 40% fewer on harder speech, and it is 5–6× faster. Its transcript of a
5-minute recording took 1.6 s. Three things need design work first:

- **The glossary.** The app's vocabulary list (Whisper's glossary prompt) has no Phonon equivalent.
- **The live transcript.** FluidAudio's streaming manager lost whole sentences.
- **First-time preparation.** It takes about 5 minutes on this Mac, against 1.5 for Whisper.

The iPhone wasn't tested.

## Method

- **Audio:**
  - LibriSpeech test-clean and test-other, first 5 clips per speaker: 200 clean clips (30 min) and 165 harder clips
    (20 min).
  - One long recording: about 5 minutes of test-clean chapter 1089/134686, joined with 0.5 s gaps.
  - The app's backup-plan script, spoken by the system voice Samantha (19 s).
- **Whisper as the app runs it.** WhisperKit 1.1.1 through the app's own `WhisperEngine` and `ModelCoordinator`,
  with no glossary. Clips went through `StreamingTranscriber.finish()`, the app's stop path. The long recording was fed
  in half-second chunks with `passIfNeeded()` after each, then `finish()`.
- **Phonon-2 through FluidAudio** (revision c79c4106b9).
  - `AsrModels.downloadAndLoad(version: .phonon2)` and `AsrManager.transcribe`, with fresh decoder state per clip.
  - The long recording was transcribed twice: as one file, and through `SlidingWindowAsrManager` (FluidAudio's streaming
    path) in half-second buffers.
- **Word error rate (WER)** uses the app's `WordErrorRate`: it ignores case and punctuation and does no spelling
  normalisation. So "backup" against "back up" counts as an error, and the absolute numbers run higher than published
  leaderboards. Corpus WER is word-weighted over all clips.
- **The run:**
  - One model per process.
  - Each model ran twice, on Oct 21 2026, macOS 15.8.1, with the app idle.
  - Memory is the process's footprint, sampled every 200 ms.
  - Load times are from a separate load-only run, explained under Load times below.
- The harness was a throwaway Swift package outside the repo. Nothing in the app changed.

## Results

| | Whisper Small (English) | Phonon-2 |
|---|---|---|
| test-clean WER (200 clips) | 3.17–3.21% | **2.44%** |
| test-other WER (165 clips) | 7.09–7.15% | **4.32%** |
| Clips with zero errors (clean / other) | 115 / 78 | **127 / 100** |
| Clips where it was the worse of the two (clean / other) | 41 / 51 | 21 / 14 |
| Speed on clips (× real time) | 12–13× | **66–83×** |
| Median clip time / slowest clip | 0.48–0.62 s / 4.7 s | **0.07–0.09 s / 0.3 s** |
| 5-minute recording: final WER | 2.5–2.6% (streamed, as the app) | **1.1%** (one pass at stop) |
| 5-minute recording: stop → text | **0.6 s** (the live passes did the rest) | 1.6–2.0 s for the whole file |
| App script (system voice) | 3.0% | 1.5% |
| First-time preparation on this Mac | **81–99 s** | 305–334 s |
| Warm load (compile cache hit) | **0.8–0.9 s** | 1.3–1.6 s |
| Download / on disk | 464 MB | **368 MB** |
| Process footprint after load / peak | 41–43 / 129–133 MB | 48–55 / 111–123 MB |

Both models make the same kind of mistakes, and Phonon makes fewer of them. In the app script, Whisper wrote "backup"
for "back up". Phonon wrote "flawed" for "flood". On the hardest test-other clip (dialect speech), both were poor:
Whisper 79%, Phonon 64%. Phonon's one clearly worse clip was a 3-word archaic phrase ("when churchyards ywn").

The memory figures leave out the Neural Engine's copy of the weights, for both models. So they say the two are similar,
not what either really costs. Both fit the 0.98 GB transcription budget on disk size alone.

### Streaming

The app shows a live transcript while you talk.

- **Whisper.** On this Mac, the live passes took about 0.7–0.8 s of compute per second of audio (212–239 s for 295 s).
  Very little was left at stop, which is why stop → text is 0.6 s.
- **Phonon through `SlidingWindowAsrManager`.**
  - WER on the 5-minute recording was **9.7%**: it returned 655 words where the whole-file pass returned 722.
  - It dropped whole sentences ("After early nightfall the yellow lamps would light up…").
  - Stop → text was 3.9–4.8 s.
  - The audio arrived faster than real time, but this manager queues every buffer unbounded and processes 2 + 11 + 2 s
    windows in order. So the losses come from how it joins windows, not from the pacing.
- **Phonon in the app.** Parakeet's encoder takes at most 15 s per window, so the app's live passes would need their
  own design for Phonon. Running `AsrManager` over the recent audio is cheap: 80× real time leaves plenty of room. The
  final transcript would come from one pass over the whole recording at stop: 1.6 s for 5 minutes, at 1.1% WER.

### Load times, and a compile-cache finding

The first time a model is loaded, Core ML compiles it for the Neural Engine and caches the result. Phonon's encoder ships
three window sizes (5, 10 and 15 s), so it compiles three times. That is why it takes about 5 minutes here, against
1.5 for Whisper.

When the cache was kept, back-to-back launches loaded in 0.8–0.9 s (Whisper) and 1.3–1.6 s (Phonon). But during the
full benchmark runs, the cache was dropped between runs. Each model's second run spent the full first-time compile
again: 91 s and 305 s.

This Mac's data volume is 98% full (11 GB free), and macOS removes purgeable caches when space runs low. That is the
likely cause, though not proven. It matters to the app whichever engine it uses. The `.audiopencil-prewarmed` marker
would still say the model is ready, and the "loads in seconds" path would then take minutes with no preparation
progress shown.

## What switching would take

- **A new `SpeechTranscribing` engine** for English, with FluidAudio as a dependency, plus attribution in About for
  the CC-BY-4.0 licence.
- **Vocabulary.** Phonon has no prompt.
  - FluidAudio's vocabulary boosting rescores with a separate CTC model. That is another download, and it wasn't tested
    here.
  - Without it, the vocabulary setting does nothing for English. One option: keep Whisper for English when a vocabulary
    is set.
- **The live transcript**, as described under Streaming above. Don't use `SlidingWindowAsrManager` as it stands.
- **The preparation screen.** It already shows progress per part; Phonon needs about 5 minutes of it on an M1.
- **The iPhone needs its own test.**
  - Untested: Neural Engine compile time on the phone, memory under the app's 9b background recording, and
    `SpeechTranscribing` while locked.
  - Phonon runs on the Neural Engine, not the GPU, so iOS's background-GPU limit shouldn't apply. But this needs
    checking on the phone.

## Not covered

- **Plain Parakeet TDT 0.6B v3** (`.v3` in FluidAudio). It covers 25 European languages, French and Spanish among
  them. It could replace Large v3 Turbo for those languages, whose first-time preparation takes 12.5 minutes
  ([multilingual Whisper](multilingual-whisper.md)). That deserves its own benchmark against the same clips.
- Real (non-LibriSpeech) dictation from a phone microphone outdoors, where both models will do worse.
