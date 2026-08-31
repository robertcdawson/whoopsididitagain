# Apple workout parser prototype

The Apple model only extracts workout drafts. It cannot access WHOOP credentials, read health
history, invoke tools, change restrictions, save plans, or log completed work. The original paste
is retained and every plan still requires user review and confirmation.

**Status: research retained; unavailable in normal app runs.** The broad single-pass extractor has been
replaced by a staged hybrid with explicit field mapping. The built-in parser remains the default. The Apple provider,
validation, fallback, UI controls, and evaluation harness are implemented, but Apple extraction is
not approved for normal use or default-on rollout.

The phone-update path supplies no Apple model and hides its controls, even if an old opt-in is
stored. Only DEBUG simulator runs with explicit synthetic test-provider settings expose those
controls. The standalone Mac harness still evaluates the real model. Committing the research code
does not enable it in the phone app or clear its live quality gate.

## One part at a time, with explicit field mapping

The `apple-extraction-2.0.0` provider asks Apple for one classification label per source line, in
fresh sequential sessions. It does not ask Apple to write a complete workout document, select
catalog IDs, copy quantities, remember earlier output, or calculate anything. Line IDs and ordering
are owned by code. Source scores are removed before any model call and restored as reported notes.

| Apple label | Fields controlled by code |
| --- | --- |
| `exercise_line` | Movement row; numeric/unit tokens read from that original line |
| `amrap_header` / `emom_header` | Workout format; explicit duration becomes the work time limit |
| `for_time_header` | For-time format, without inventing a work duration |
| `round_count_header` / `set_count_header` | Prescribed repeat count, never completed-score rounds |
| `strength_header` | Explicit strength heading, not a classification of a loaded exercise |
| `time_cap_line` | Global time cap, not another exercise |
| `rest_line` | Separate duration-only rest segment |
| `context_line` | Recognized title/target metadata, not a hidden unknown movement |

For example, code reads `9 Strict Press (42 lb)` as 9 repetitions with 42 lb. Apple only needs to
label it `exercise_line`; `strength_header` would be rejected. Generic `strength` labels were
ambiguous because the model confused exercise type with workout structure.

The complete attempt is bounded to 2,400 source bytes, 16 parts, 40 generated tokens per part, and
one 20-second total deadline. No parallel model allocations or automatic retry loop. Code checks
source-number coverage, explicit format evidence, unit validity, bounds, repeat scope, and final
domain validity. A failed part discards the whole draft and returns an explained built-in fallback;
cancellation returns no draft. No saved workouts are rewritten. Multi-exercise lines, complex
scoping, and ambiguous quantities can still require fallback/manual review.

## Repeatable live-model evaluation

Building this prototype requires Xcode 26 with the Foundation Models SDK. The app still targets
iOS 18; the framework is weak-linked and guarded at runtime, so unsupported devices use the built-in
parser. Simulator boundary tests do not require an available model.

On an Apple Intelligence-capable Mac running macOS 26 or later, with the system model ready:

```sh
sh scripts/evaluate-apple-parser.sh
sh scripts/evaluate-apple-parser.sh amrap_1
sh scripts/evaluate-apple-parser.sh amrap_2 for_time_1 rounds_1
sh scripts/evaluate-apple-parser.sh --built-in
sh scripts/evaluate-apple-parser.sh --fresh
sh scripts/evaluate-apple-parser.sh --built-in --fresh
```

The harness compiles the production parser, model client, and domain models into a temporary
executable. It evaluates 30 synthetic fixtures in `fixtures/workouts/apple-parser-evaluation.json`
without routing failures through the deterministic fallback. It checks exact format, time cap,
segment structure, movement IDs, quantities, units, percentages, and work/rest timing. It reports
elapsed parsing time, ambiguity count, mismatches, and unavailable-model errors. Diagnostics print
synthetic outputs only. Do not replace these fixtures with personal health exports.
The optional `--built-in` run evaluates the existing deterministic parser on the same expectations,
without invoking the model. `--fresh` selects 12 independent follow-up examples, including clock
times, different numbers, unfamiliar exercises, trailing rest, and deliberately ambiguous values.
Any mismatches produce exit status 1 and must not be treated as a passing quality gate. A projection
match with missing-source warnings is also a failure. Rejected attempts and all-attempt latency
are reported separately; fast rejection is not fast successful parsing.

This is an initial regression set, not a statistical accuracy estimate: several cases intentionally
vary the formatting of the same workout. The set includes AMRAP, for-time, rounds, strength,
unit conversion, timed movements, unknown movements, scores, and explicit rest. It should grow with
independent synthetic examples of new gym syntax, rather than relaxing expected outputs to fit the
model. Complex multi-movement lines, alternative prescriptions, tempo, and unusual units may need
manual review. Do not infer overall model quality from a successful simple example.

## Automated boundary tests

`OnDeviceWorkoutParserTests` uses a fake provider to cover grounded extraction, invented values,
reported-score isolation, source references, unknown/omitted movements, unit conversion, invalid
rest, string-null normalization, disabled/unavailable models, bounded input, timeout, and caller
cancellation. The app falls back if Apple drops quantities or leaves source lines unstructured,
even when the raw extraction passes shape validation. Simulator UI tests use DEBUG-only
fixture/failure providers, never a live model, so they prove workflow behavior rather than model
quality. Normal app runs never create the Apple provider; the live provider is evaluated separately
by the standalone Mac harness.
Staged-provider tests additionally verify isolated ordered requests, blank/result-line source IDs,
fixed label-to-field mappings, strength/rest assembly, partial failure, part-count limits, and
cancellation before the next part. These prove assembly behavior, not live classification accuracy.

## Phone acceptance (held until the live accuracy gate passes)

This is a future Apple-provider acceptance checklist, not instructions for the current built-in-only
phone update. Its controls must be explicitly reintroduced after the live quality gate passes.

1. Enable Apple Intelligence in device Settings and allow its model assets to become ready.
2. In Train, explicitly enable **Try Apple Intelligence (experimental)** and parse representative
   programming. The default is off; ordinary parsing does not initialize the model.
3. Confirm the review says **Parsed with Apple Intelligence · On device**. If it falls back, read
   the reason under Parser notes; a successful fallback is not evidence that Apple parsing worked.
4. Compare every prescription with the original, including scores versus planned rounds. Confirm
   restriction warnings and manual corrections still work. Saving creates a plan, not actual work.
5. Cancel a parse, try manual entry, then disable the toggle and confirm the built-in parser works.
6. Test cold and repeated requests, navigation/backgrounding, and offline operation. Profile the
   real device with Instruments for responsiveness and peak memory; a CLI process's memory does
   not include all OS-managed model-service memory.

Re-run live evaluations after material prompt/schema changes and system-model/OS updates. Record
the OS build alongside parser version; Apple does not expose a stable model-weight revision here.

## Verification record

- August 30, 2026, macOS 26.6.2 (25G83), on-device system model: the guided-generation candidate
  matched **3/30** expected structures in both the initial and final full runs. Observed failures
  included omitted reps/weights, duplicated
  movements, fabricated rest, copying numbers from a worked example, and confusing a time cap with
  prescribed work duration. Strict source validation rejected many outputs; it does not guarantee
  semantic correctness. In-app fallback is not counted as a model success.
- Two earlier alternatives (required-string quantities and a smaller freeform JSON prompt) each
  matched **0/6** targeted fixtures. They are not the retained production candidate.
- The original deterministic `deterministic-1.3.0` baseline matched **19/30**, not 30/30. Its gaps included
  turning time-cap/strength headings into unknown movement rows, missing standalone set counts,
  omitting quantities for unknown movements, and representing a standalone rest as uniform recovery.
  These gaps are fixed in `deterministic-1.4.0`: **30/30 original and 12/12 fresh fixtures passed**.
  Fresh testing exposed a missing explicit plural `goblet squats` alias, which was added with a
  regression test; no fixture expectations were weakened. Source text and review remain essential.
- The first staged hybrid asked for independent role/format labels and matched **4/30 original,
  5/12 fresh**. The model confused an exercise's type (strength) with a workout heading. Replacing
  those labels with one explicit category (`exercise_line`, `strength_header`, etc.) improved the
  retained candidate to **28/30 original (confirmed in a repeat run) but only 4/12 fresh**. This is a
  hybrid result: code, not Apple, extracts numbers/units and assembles segments. It is not a
  pure-model accuracy score.
- The retained staged candidate failed on a timed movement and an explicit rest in the original
  set. Fresh failures included clock-format instructions, a different round-count example, timed
  work, rest, and the two deliberately ambiguous cases. All 10 failures across both sets were
  rejected rather than silently accepted as matching drafts; the app would use visible fallback.
  Fresh unambiguous cases were **4/10**, so even allowing the two correct ambiguity rejections does
  not clear the accuracy gate. The repeated original formats are a development regression set,
  not a representative generalization benchmark.
- Mac all-attempt latency for the retained candidate: original median **1.133 s**, p95 **1.529 s**;
  fresh median **1.058 s**, p95 **1.830 s**. These include early rejection and are not phone latency
  or peak-memory acceptance. The built-in parser took approximately **1–4 ms** per fixture here.
- Direct diagnostic questions to the local model produced unreliable advice (including claiming
  exercise lines have no numbers/units). That feedback was inspected but not adopted as a source
  of truth. Evaluation expectations and deterministic restrictions remain authoritative.
- Pre-staging automated regression results: **83 iOS unit tests and 13 UI tests passed**, with zero
  failures, on the iPhone 17 Pro / iOS 26.5 simulator. Result bundle:
  `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_00-33-47--0700.xcresult`.
  The focused three-case AI UI run also passed. The settings reader uses `UserDefaults.bool(forKey:)`
  so launch-argument and stored Boolean preferences agree.
- Backend lint, typecheck, all 10 tests, and production build passed. The backend code was unchanged;
  native tests/build used the installed arm64 Node 24 runtime after the shell selected x64 Node.
  Swift formatting, shell syntax, Xcode project validation, and diff checks passed. The existing
  HealthKit publication warning remains tracked separately; its unit assertions passed.
- Final staged-parser verification: **97 iOS unit tests and 13 UI tests passed**, with zero failures,
  including the final explicit-label mapping and plural alias. Result bundle:
  `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_01-25-05--0700.xcresult`.
  Swift formatting, shell syntax, Xcode project validation, and diff checks passed. The backend was
  not changed or rerun during this staged revision; its preceding verification is recorded above.
- Pre-commit phone-update verification: **98 iOS unit tests and 14 UI tests passed**, including
  normal-run isolation from a stored Apple opt-in. Result bundle:
  `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_01-45-12--0700.xcresult`.
  The unsigned physical-device build passed; no phone installation was performed. All 42 built-in
  parser fixtures passed again. Backend lint, typecheck, all 10 tests, and production build passed.
  Swift formatting, shell syntax, Xcode project validation, and diff checks passed.
- No physical-device quality, latency, or peak-memory acceptance has been performed for the Apple
  prototype. The automated passes do not clear the live accuracy gate. Normal phone updates use
  the built-in parser while the prototype stays inaccessible.

## Platform references

- [Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
- [Foundation Models overview and guided generation](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Generation controls and model-version caveats](https://developer.apple.com/videos/play/wwdc2025/301/)
