# Qwen3-4B-Instruct-2507 vs SmolLM3-3B (current default)

Should the default writing model change from `mlx-community/SmolLM3-3B-4bit` to
`mlx-community/Qwen3-4B-Instruct-2507-4bit`, the model the app's model discovery suggested?

**Recommendation: no, keep SmolLM3-3B as the default.** Qwen3-4B-Instruct writes text that sounds
better, follows the Professional layout more closely and is more literal in Diary. It is also
about 25% slower at generating, uses about 0.5 GB more memory at peak, and pushes a Diary rewrite
past the 8 s budget. Worst for a dictation tool, it **adds facts and decisions the speaker didn't
say** in the Professional style, in every clean run. SmolLM3 sometimes leaves things out but never
invented anything here.

## Headline numbers

The clean runs only (see *Run conditions*): SmolLM3 runs 1–3 (excluding run 2's long-form case) and
Qwen runs 2–3. Ranges are min–max across those runs.

| | SmolLM3-3B-4bit | Qwen3-4B-Instruct-2507-4bit | Qwen vs SmolLM3 |
|---|---|---|---|
| Load (from local cache) | 2.7–2.9 s | 2.3–2.4 s | ~0.4 s faster |
| Quick note → Polished | 3.2–3.6 s | 4.4–4.5 s | +1.1 s |
| Quick note → Professional | 2.8–3.2 s | 3.2 s | ≈ same (Qwen writes less) |
| Diary → Diary | 6.3–6.9 s | 8.2–8.7 s | +1.9 s |
| Work ramble → Professional (long-form) | 8.6–9.1 s | 11.9–12.8 s | +3.5 s |
| Work ramble → section notes (long recordings) | 8.7–10.2 s | 10.8–11.5 s | +1.8 s |
| First-token latency (prefill) | 1.5–2.9 s | 1.6–3.0 s | ≈ same |
| Generation speed | 21–29 tok/s (≈26) | 17–23 tok/s (≈20) | ~25% slower |
| Prompt processing | 140–170 tok/s | 116–129 tok/s | ~20% slower |
| Peak MLX memory | 2.18 GB | 2.71 GB | +0.53 GB |
| Process peak footprint | 2.31–2.32 GB | 2.84 GB | +0.52 GB |
| Footprint after load | 1.69–1.71 GB | 2.18 GB | +0.48 GB |

Times are generation only. The app swaps the writing model in for each rewrite, so add the load time
to get what the user waits for. With load included, Polished takes about 6.1 s on SmolLM3 and 6.8 s
on Qwen; Diary takes about 9.3 s on SmolLM3 and 10.8 s on Qwen.

First-token latency is about the same despite Qwen's slower prefill: its tokenizer turns the same
prompt into 9–17% fewer tokens (Polished 188 vs 226, long-form 378 vs 416).

## Output quality

Checked against the prompt rules: first person, no preamble, the style's own rules, no invented
facts. At temperature 0.3, Qwen's clean runs were almost word-for-word identical. SmolLM3 varied
more between runs.

| | SmolLM3-3B | Qwen3-4B-Instruct |
|---|---|---|
| First person | ✓ all cases (long-form no longer says "the speaker" as it did in the first benchmark) | ✓ all cases |
| No preamble / wrappers | ✓ | ✓ |
| Polished | ✓ Clean. One run dropped "late" ("The finance numbers came in yesterday") | ✓ Clean, keeps the speaker's wording almost exactly |
| Quick Professional (no list) | ✓ Mostly. Tone wobbles: "I'm informing you that…" in one run, "Hey Sarah," in another | ~ Twice framed a delay as a choice: "I'm rescheduling the quarterly report" |
| Diary (keep every other word) | ✗ Over-edits: drops "actually", "Then", "though", "Yeah" (two runs drop the whole closing line); "haven't" → "hadn't" | ✓ Better: keeps "actually", "Then", "Yeah, that's about it". Leaves the filler "like" ("in like two weeks") and drops "though" |
| Long-form Professional (summary → themed bullets → Action items) | ✗ One paragraph with no bullets or Action items, in all 3 runs. The content is faithful and complete | ~ Summary paragraph plus bullets in every run, but the bullets aren't grouped by theme and only run 1 has an "Action items" heading |
| Section notes | ✓ Complete bullet notes | ✓ Tighter, more note-like bullets |
| Invented / distorted facts | None found. Minor: "our home server", one garbled "fire/fire etc." | **Yes, repeatedly** (see below) |
| Paragraph breaks in Diary | Neither model adds them | |

### What Qwen added that wasn't said

The transcript says *"I'm leaning towards the cottage… I should test restoring too… I'll do a test
restore of the photos folder next week."* Qwen's long-form Professional output:

> I've decided to prioritize the cottage solution because it's automatic and secure, …
>
> - I will document the restore process and any issues encountered.

The added action item ("I will document the restore process…") appeared in both clean runs, and so
did "secure", which the speaker never said. "Leaning towards" became "decided" or "choosing" in all
three runs. Run 1 also called the cottage "a more reliable, local backup solution" (it is off-site)
and left out the fire risk, the option of a drive at the parents' place and the slow upload. The
section notes also overstate the decision: "Chosen option: Nextcloud at cottage".

### What SmolLM3 does instead

Its long-form Professional output keeps every fact and commitment but ignores the layout:

> I've been considering the backup situation for the home server. Currently, everything is backed up
> nightly to an external drive, but it's located in the same room, so it's vulnerable to fire or
> other disasters. … I'll test restoring the photos folder next week. I'll also ask Dave if the
> cottage router can provide a static IP. I'll set up the cottage sync this weekend.

Qwen's structure is the more appealing output, but it is wrong about what the speaker decided and
committed to. SmolLM3's version is plainer and accurate. For notes people paste and rely on,
accuracy wins.

### Short excerpts side by side

| Case | SmolLM3-3B | Qwen3-4B-Instruct |
|---|---|---|
| Polished | "…so I'll have it for you on Thursday morning instead of Wednesday. No other changes." | "…so I'll have it to you Thursday morning instead of Wednesday. Nothing else has changed." |
| Quick Professional | "I'm letting you know the quarterly report will be a day late." | "I'm rescheduling the quarterly report to Thursday morning instead of Wednesday due to delayed finance numbers." |
| Diary opening | "Today was a pretty good day. … which I hadn't done in two weeks" | "Today was actually a pretty good day. … which I haven't done in like two weeks" |
| Section notes | "- Leaning towards cottage backup due to automatic nature" | "- Chosen option: Nextcloud at cottage (automatic, encrypted)" |

## Against the 8 GB and 5–8 s constraints

- **Time budget (~5–8 s per styled dictation).** For short quick notes (about 50 words), both
  models fit even with load included (≈6–7 s). For a ~100-word diary entry, generation alone is
  8.2–8.7 s on Qwen, already over budget before the 2.3 s load; SmolLM3 takes 6.3–6.9 s. Long-form
  Professional takes about 12 s on Qwen against about 9 s on SmolLM3, and the gap grows with
  length, because Qwen generates more slowly *and* writes 25–33% more tokens there.
- **Memory.** Whisper and the writing model are never resident together, so the 2.84 GB peak is
  workable. It is still 0.5 GB more on a machine that already had 4.0–4.9 GB of swap in use during
  these runs. That extra half gigabyte is what decides whether the other apps the user has open get
  swapped out.

## Recommendation

1. **Keep `mlx-community/SmolLM3-3B-4bit` as the default.** Qwen is slower, heavier and less
   faithful. Its gains (Professional layout, literal Diary) don't make up for invented commitments
   in a user's notes.
2. Don't promote Qwen3-4B-Instruct in model discovery as an upgrade. If it stays listed, describe it
   as "slower, larger; tends to embellish in Professional".
3. The real gap this benchmark found is SmolLM3 ignoring the Professional long-form layout (no
   bullets, no Action items) under the current prompt. That is a prompt problem worth fixing on
   its own. It is a cheaper and safer improvement than switching to a 4B model.

## Method

- Benchmark: `Packages/AudioPencilKit/Tests/APSummaryTests/SummaryBenchmarkTests.swift`, the same
  opt-in test and fixtures (`APSummary/BenchmarkFixtures.swift`) that produced
  [summary-models-m1-8gb.md](summary-models-m1-8gb.md) and
  [summary-models-short-prompts.md](summary-models-short-prompts.md), with today's `PromptBuilder`.
  Quick cases use `.quick` context. Long-form Professional uses `.longForm`. Section notes uses
  `PromptBuilder.sectionNotesPrompt` (part 1 of 2), the first pass the app runs on long recordings.
- Small additions to the test for this comparison (still opt-in behind `AUDIOPENCIL_BENCH=1`):
  first-token latency (time to the first streamed text, which is mostly prefill), process peak
  physical footprint (`ri_lifetime_max_phys_footprint`), and the section-notes case.
- Models were loaded from the app's existing cache
  (`~/Library/Application Support/AudioPencil/Models/huggingface`, `SummaryEngine`'s default root),
  so nothing was downloaded.
- Each model ran in its own `xcodebuild test-without-building` process, one at a time, in the order
  SmolLM3 → Qwen → Qwen → SmolLM3 → Qwen → SmolLM3, so the process peak belongs to one model. The
  build is Debug, the xcodebuild default and the same as the earlier docs. Generation used
  temperature 0.3 and top-p 0.9, as the app does.

```sh
cd Packages/AudioPencilKit
TEST_RUNNER_AUDIOPENCIL_BENCH=1 \
TEST_RUNNER_AUDIOPENCIL_BENCH_MODELS=mlx-community/Qwen3-4B-Instruct-2507-4bit \
TEST_RUNNER_AUDIOPENCIL_BENCH_OUT=/tmp/qwen.md \
xcodebuild test-without-building -scheme AudioPencilKit-Package -destination platform=macOS \
  -only-testing:APSummaryTests/SummaryBenchmarkTests
```

## Run conditions

MacBookAir10,1 (M1, 8 GB), macOS 15.8.1, Xcode 26.3 (17C529), mlx-swift-lm 3.31.4. Runs took place
on 19 Oct 2026, 22:19–22:26.

Before each run, a preflight checked `pgrep -x "Audio Pencil"` (CPU < 15%, RSS < 1 GB),
`memory_pressure` (free ≥ 25%, `kern.memorystatus_vm_pressure_level` normal), and from run 5 on, no
compiler processes and ≥ 70% CPU idle. Before the runs started, during the package build, pressure
was at warn level, so the runs waited for it to clear. During the runs, pressure stayed normal,
free memory was 51–62% and swap in use was 4.0–4.9 GB.

Another session was rebuilding and relaunching Audio Pencil during the window. The app restarted at
22:20:16, 22:23:03, 22:24:21 and 22:25:19.

| Run | Model | Start | Notes | Used |
|---|---|---|---|---|
| 1 | SmolLM3 | 22:19:16 | app idle | ✓ |
| 2 | Qwen | 22:20:07 | app relaunched 9 s in; Quick Professional / Diary fell to 13–14 tok/s | ✗ |
| 3 | Qwen | 22:22:07 | waited 60 s for app to idle | ✓ |
| 4 | SmolLM3 | 22:23:35 | long-form case fell to 16 tok/s, likely build activity before the 22:24:21 relaunch | ✓ except long-form |
| 5 | Qwen | 22:24:30 | relaunch at 22:25:19 may overlap the last case (section notes, 17 tok/s) | ✓ (section notes possibly low) |
| 6 | SmolLM3 | 22:25:27 | app idle | ✓ |

Per-run totals (generation only):

| Run | Model | Load | Polished | Quick Prof. | Diary | Long-form Prof. | Section notes | Avg tok/s | Peak MLX | Process peak |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | SmolLM3 | 2.7 s | 3.6 s | 3.2 s | 6.3 s | 8.6 s | 10.2 s | 25 | 2.18 GB | 2.32 GB |
| 2 | Qwen ✗ | 2.0 s | 4.5 s | 5.3 s | 10.6 s | 12.2 s | 10.6 s | 17 | 2.71 GB | 2.84 GB |
| 3 | Qwen | 2.3 s | 4.5 s | 3.2 s | 8.2 s | 12.8 s | 10.8 s | 20 | 2.71 GB | 2.84 GB |
| 4 | SmolLM3 | 2.9 s | 3.2 s | 3.2 s | 6.3 s | 11.1 s ✗ | 8.7 s | 25 | 2.18 GB | 2.32 GB |
| 5 | Qwen | 2.4 s | 4.4 s | 3.2 s | 8.7 s | 11.9 s | 11.5 s | 20 | 2.71 GB | 2.84 GB |
| 6 | SmolLM3 | 2.7 s | 3.2 s | 2.8 s | 6.9 s | 9.1 s | 9.0 s | 25 | 2.18 GB | 2.31 GB |
