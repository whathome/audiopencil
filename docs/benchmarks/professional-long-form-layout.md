# Professional long-form layout on SmolLM3-3B

The [Qwen3-4B-Instruct benchmark](qwen3-4b-instruct-vs-smollm3.md) found that SmolLM3-3B (the default
writing model) ignored the Professional long-form layout: one paragraph, no key-point bullets, no
"Action items" list, in 3 of 3 runs. This note covers the prompt change that fixes that.

**Result:** in 17 of 17 runs, the long-form Professional output now has a Summary, Key points and
Action items. Before the change, 0 of 7 runs had that structure. The quick-note cases and Diary are
unchanged. The cost is about 52 more prompt tokens (+0.3–0.4 s to first token) and longer output:
a long-form rewrite of the benchmark fixture now takes 8.8–9.6 s.

## The change

`PromptBuilder.prompt` (only for long-form styles that extract action items and rewrite heavily,
which today means Professional):

- The system rule now reads `End with an "Action items" list of what I committed to.` It used to
  read `…of what the speaker committed to, if anything.`
- After `</transcript>` in the user message, it adds:

  ```
  Write it as me, in three sections, in this order:
  **Summary**: 2–3 sentences.
  **Key points**: bullets, grouped under a bold heading per theme.
  **Action items**: a bullet for each thing I said I'd do, or just "None".
  ```

`Style.swift` is unchanged. Saved styles keep their own instructions, so a fix in the Professional
preset's text would only reach new installs and reset styles. The fix in `PromptBuilder` reaches
everyone. Quick dictation still gets `No action items list.` and no layout block, and so do
long-form Polished and Diary.

## Before / after (work ramble → Professional, long-form)

Before. Every run was one paragraph like this one (19 Oct, run 1):

> I'm considering improving the backup system for our home server. Currently, everything is backed
> up to an external drive nightly, but it's located in the same room, posing a risk if there's a
> fire. Options include … To test restoring, I'll set up the cottage sync this weekend, ask Dave if
> the router there can provide a static IP, and perform a test restore of the photos folder next week.

When the old prompt did produce a list, it produced only the list and invented a commitment
(20 Oct, same-session "before" run):

> Action items:
>
> - Swap external drive monthly with parents' drive.
> - Set up Nextcloud backup at cottage this weekend.
> - …

After (20 Oct, run 3):

> **Summary**: I'm considering three backup options: swapping drives monthly with my parents, using
> Nextcloud at the cottage, or paying for cloud storage. I'm leaning towards the cottage because it's
> automatic, but the slow upload speed (10Mbps) means the first sync would take a week. I'll test
> restoring the photos folder next week and ask Dave if the cottage router can provide a static IP.
>
> **Key points**:
> - **Backup Options**: Monthly swap with parents, Nextcloud at the cottage, or cloud storage.
> - **Cottage Backup**: Automatic, slow upload (10Mbps), first sync will take a week.
> - **Testing**: Test restore of photos folder next week.
> - **Router Configuration**: Ask Dave if cottage router can provide static IP.
>
> **Action items**:
> - Test restore of photos folder next week.
> - Ask Dave if cottage router can provide static IP.
> - Set up cottage sync this weekend.

## Quality across runs

The final prompt ran 17 times on the work-ramble fixture: 3 benchmark runs plus 14 prompt-lab runs
with the same prompt. The old prompt ran 7 times: 3 benchmark runs on 19 Oct, 1 on 20 Oct, and 3
lab runs.

| | Old prompt (7 runs) | New prompt (17 runs) |
|---|---|---|
| Summary + Key points + Action items | 0 | 17 |
| Key points grouped under theme labels | 0 | 16 (1 flat list) |
| Action items as a bulleted list | 2 (list only, nothing else) | 16 (1 written inline) |
| Invented commitment ("swap drives monthly", an option the speaker only weighed) | 2 | 1 |
| Second person / "the speaker" | 0 | 0 |

Diary transcript through long-form Professional, which has no real commitments (4 runs): every run
listed only "Run three times a week". The speaker did say "I want to keep the running going, maybe
three times a week", so that is an intention turned into an action item, not an invention.

The run that invented a commitment (benchmark run 2) also asked "if Nextcloud at cottage can have
static IP" where the speaker said the router. One distortion appears with both prompts: the summary sometimes merges "I should test restoring" with
"set up the cottage sync this weekend" into "test restoring … this weekend".

## Timings

Benchmark (`SummaryBenchmarkTests`, SmolLM3-3B-4bit only), 20 Oct, 01:58–02:03. Runs in order: after,
after, before, after.

| Run | Load | Polished | Quick Prof. | Diary | Long-form Prof. | Section notes | Gen tok/s | Peak MLX | Process peak |
|---|---|---|---|---|---|---|---|---|---|
| after 1 | 2.7 s | 3.1 s | 3.0 s | 6.0 s | 9.6 s | 6.8 s | 30 | 2.21 GB | 2.38 GB |
| after 2 | 2.6 s | 3.2 s | 3.0 s | 5.5 s | 8.8 s | 6.6 s | 30 | 2.21 GB | 2.38 GB |
| before | 2.6 s | 3.1 s | 2.9 s | 5.8 s | 4.2 s ¹ | 7.5 s | 29 | 2.18 GB | 2.32 GB |
| after 3 | 2.6 s | 3.2 s | 3.1 s | 5.7 s | 9.0 s | 6.7 s | 30 | 2.21 GB | 2.38 GB |

¹ The "before" long-form run wrote only a 46-token Action items list. The old prompt's normal
one-paragraph output is 142 tokens: 8.6–9.1 s on 19 Oct at 21–24 tok/s, or about 7.3 s at today's
30 tok/s.

Long-form Professional, old → new:

- Prompt: 416 → 468 tokens. First token 2.4 → 2.8 s.
- Output: 142 → 175–208 tokens (+1.1–2.2 s at 30 tok/s).
- Total: about 7.3 s (estimated at today's speed) → 8.8–9.6 s.
- Peak MLX memory: +0.03 GB.

The quick-note prompts are byte-for-byte unchanged, and so are their times.

## What didn't work

From 10 prompt-lab batches, 3–8 runs per variant, all on one loaded SmolLM3:

- **Layout in the system rules**, however phrased (prose, a skeleton, or a bold-heading template):
  0 of 15 runs had the structure. SmolLM3 writes the summary paragraph, which already mentions every
  plan, and stops. Moving the same instructions after the transcript was the change that mattered.
- **A literal skeleton with `<Theme>` placeholders**: the model copies them ("**<Theme> Backup
  Options**"). With `…` or "First theme" placeholders it ignores the themes or copies the label.
- **"Leave out Action items if I committed to nothing"**: the model stops before the list.
  **A required list with no "None" option**: it invents items to fill the list (2 runs added "swap
  drives monthly").
- **Limiting the summary** ("1–2 sentences: the gist", "without the plans"): ignored. Removing the
  layout sentence from the style's own instructions made the summary drop the options.
- **Without the system-side Action items rule** the after-transcript block gets Action items only
  2/5 times. With it: 5/5.
- **"Write three sections"** without "as me" (with the system rule) slipped into "You're considering…" in 2 of 11 runs. Adding
  "as me" removed that.
- **Adding "(not options)" or "only what I said I'll do"** to the Action items line made it worse:
  one invented commitment, and two runs with no Action items.

## Method

- Benchmark: `Packages/AudioPencilKit/Tests/APSummaryTests/SummaryBenchmarkTests.swift` with the
  first-token, section-notes and process-peak additions from the Qwen benchmark branch
  (`claude/bench-qwen3-4b-instruct-c46037`). Those additions were used for these runs but aren't
  part of this change. Command as in that note, with
  `TEST_RUNNER_AUDIOPENCIL_BENCH_MODELS=mlx-community/SmolLM3-3B-4bit`. The "before" run rebuilt
  with `PromptBuilder.swift` from `HEAD`.
- Prompt lab: a throwaway opt-in test that loaded SmolLM3 once and ran prompt variants back to back.
  It was not committed. Temperature 0.3 and top-p 0.9, as in the app.
- Run conditions: MacBookAir10,1 (M1, 8 GB), macOS 15.8.1, Xcode 26.3, mlx-swift-lm 3.31.4.
  Before each benchmark run, a preflight required Audio Pencil (running, from another session) at
  < 15% CPU, free memory ≥ 25%, normal memory pressure, no compiler processes and ≥ 70% CPU idle.
  Free memory was 47–55% and generation held at 29–30 tok/s in every run. Lab runs used a 50% idle
  bar instead, because an `ANECompilerService` job and other sessions were busy. Lab timings are
  therefore noisy (13–30 tok/s), and only the benchmark runs above are used for timing.
- Not covered: long recordings that are split into sections. Their final pass uses the same
  long-form prompt on combined section notes, but no benchmark fixture exercises it.
