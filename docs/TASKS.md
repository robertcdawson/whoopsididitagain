# Implementation Tasks

`PROJECT_PLAN.md` defines milestone scope and acceptance criteria. This file tracks execution.

## Branch integration (August 30, 2026)

- [x] Diagnose the signed `main` build failure: missing development team; unsigned source build passed.
- [x] Preserve both `main` (`4824786`) and the stability/experiment branch (`01b70dd`) in a merge.
- [x] Retain protocol intake/docket and experiment, workout editing, HealthKit, and WHOOP improvements.
- [x] Resolve overlapping Xcode project IDs and verify source membership from both parents.
- [x] Combine all 19 SwiftData record types without renaming entities or resetting data.
- [x] Verify synthetic disk-backed upgrades from both parent schemas, including all stored fields.
- [x] Add a timed-protocol restriction bridge regression and protocol-capture keyboard coverage.
- [x] Restore the existing signing team and pass a normally signed iPhone build without installing.
- [x] Complete final full unit/UI suites after the docket accessibility correction: 147 unit and
  22 UI tests, zero failures.
- [ ] Confirm the integrated build on the physical iPhone without deleting the existing app.

Final verification (August 30):

- Simulator result: `/tmp/whoops-integration-derived/Logs/Test/Test-WhoopsApp-2026.08.30_19-29-16--0700.xcresult`.
- Signed iPhone build: `/tmp/whoops-integration-device-derived`; code-signature verification passed.
- Synthetic macOS SwiftData upgrades: 17-type main and 16-type feature stores to the combined
  19-type schema; retained fields and nil values passed for both parents.
- Built-in parser: 30 evaluation and 12 fresh fixtures passed. Apple-model acceptance is unchanged.
- Backend: lint, typecheck, all 10 tests, and production build passed with native ARM64 Node 24.
- Strict Swift formatting, project/source-reference integrity, 13 JSON files, and diff checks passed.
- The first docket UI run exposed inherited accessibility IDs; the corrected targeted rerun and
  final full suite passed. No physical-phone installation or production deployment was performed.

See `BRANCH_INTEGRATION.md` for scope, migration-check limitations, and Xcode update steps.

## Milestone 0: Project Foundation

- [x] Create the monorepo implementation structure.
- [x] Create the native SwiftUI project and four-tab shell.
- [x] Create the Next.js TypeScript backend.
- [x] Add the versioned backend health endpoint.
- [x] Define shared success and error contracts.
- [x] Add protocol boundaries for external systems and core engines.
- [x] Add placeholder environment configuration without secrets.
- [x] Add realistic synthetic fixtures.
- [x] Add backend unit and route tests.
- [x] Add iOS unit and UI test targets.
- [x] Add formatting, linting, and CI configuration.
- [x] Verify backend install, lint, typecheck, tests, and production build.
- [x] Verify iOS formatting, app/test-bundle build, unit tests, and UI smoke test.

Milestone 0 completed on August 15, 2026.

## Milestone 1: WHOOP Vertical Slice

- [x] Implement WHOOP authorization-code OAuth with one-time state and app exchange codes.
- [x] Encrypt WHOOP access and refresh credentials at rest.
- [x] Serialize rotating refresh-token updates per app installation.
- [x] Issue short-lived app access sessions and Keychain-backed refresh sessions.
- [x] Add connection status and disconnect/revoke controls.
- [x] Import 180 days of v2 cycle, recovery, sleep, and workout collections.
- [x] Follow continuation tokens and protect against pagination loops.
- [x] Add incremental synchronization with overlap and per-resource checkpoints.
- [x] Store source records idempotently in local SwiftData.
- [x] Display recovery and sleep history.
- [x] Add backend security, OAuth, refresh-race, pagination, and failure tests.
- [x] Verify the backend suite and Swift 6 iOS build.

Live acceptance completed on August 27, 2026: Robert connected the physical iPhone through the
production OAuth callback, and the app imported 693 WHOOP records spanning roughly 180 days. No
credential or personal health payload belongs in source control.

- [x] Deploy the backend to its production HTTPS Vercel domain.
- [x] Provision and migrate persistent Neon PostgreSQL storage for OAuth credentials and checkpoints.
- [x] Configure WHOOP credentials and backend encryption/session keys in Vercel environments.
- [x] Register the production callback URI in the WHOOP Developer Dashboard.
- [x] Connect the physical iPhone and confirm the real 180-day import.
- [x] Use wake-day WHOOP stage totals for Today sleep, readiness, trends, and experiments.

## Milestone 2: HealthKit and Unified Timeline

- [x] Add the read-only HealthKit capability and privacy description.
- [x] Request only the selected physiology, sleep, activity, workout, and body sample types.
- [x] Import incrementally with a durable query anchor per sample type.
- [x] Register observer queries and hourly background delivery where iOS supports it.
- [x] Store source samples idempotently and reconcile HealthKit deletions.
- [x] Preserve the source time zone, UTC offset, and local day for every sample.
- [x] Link likely WHOOP/HealthKit duplicate workouts without deleting either source record.
- [x] Keep WHOOP HRV RMSSD and Apple Health HRV SDNN separate.
- [x] Display a unified daily physiology view with visible source attribution.
- [x] Add reversible per-metric Apple Health inclusion controls that apply to all projections.
- [x] Tolerate partially denied read access and keep imported history available offline.
- [x] Add tests for partial access, idempotency, deletion, workout linking, and travel/DST days.
- [x] Verify the Swift 6 app build and all iOS unit tests.

Live acceptance remaining: confirm an observer-driven update after the app is backgrounded. Apple
does not support HealthKit background delivery in Simulator. Authorization and a real 85,126-record
import were verified on Robert's iPhone on August 27, 2026.

Physical-device follow-up found August 27, 2026:

- [x] Install and launch the app on Robert's iPhone.
- [x] Complete Apple Health authorization with selected read categories.
- [x] Replace the memory-unsafe unlimited first import with 180-day, 500-sample anchored pages.
- [x] Commit every page before advancing its durable anchor and use fresh persistence contexts.
- [x] Aggregate recent history in bounded pages and add paged-import regression coverage.
- [x] Install the corrected build and confirm that real records import without a memory termination.
- [ ] Confirm an observer-driven update after the app is backgrounded and a new sample arrives.

## Milestone 3: Daily Assessment and Symptom Logging

- [x] Add a low-friction morning symptom, energy, motivation, and illness check-in.
- [x] Seed editable injury restrictions and support adding, changing, disabling, and deleting them.
- [x] Calculate robust 28-day personal medians and median absolute deviations.
- [x] Keep WHOOP HRV RMSSD and Apple Health HRV SDNN in separate readiness components.
- [x] Add a versioned deterministic readiness rules engine that does not require an LLM.
- [x] Make hard movement restrictions override otherwise strong systemic readiness.
- [x] Keep the tissue score consistent with an active hard restriction without inventing missing check-in data.
- [x] Lower confidence and expose reason codes when source data or baselines are incomplete.
- [x] Display the recommendation, component scores, confidence, and strongest signals on Today.
- [x] Persist assessments and preserve user overrides and annotations separately.
- [x] Add configurable wake, sleep-duration, latency, and wind-down settings and deadlines.
- [x] Add unit coverage for baselines, restrictions, missing data, deadlines, and persistence.
- [x] Verify the Swift 6 app build, all iOS unit tests, and the morning-check-in UI path.

Live acceptance remains: review the seeded personal restrictions, set the intended sleep schedule,
complete a real morning check-in, and confirm that the resulting reasons and recommendation match
Robert's judgment. These personal inputs should be edited whenever the underlying condition changes.

## Milestone 4: Workout Parsing and Scaling

- [x] Add raw-workout paste and a parser-independent manual-entry path.
- [x] Replace the placeholder parser contract with a strict, versioned JSON Schema.
- [x] Add a canonical movement catalog with aliases, demand tags, and substitution candidates.
- [x] Parse representative for-time, AMRAP, rounds, strength, and interval wording locally.
- [x] Preserve unknown lines and missing prescriptions as explicit ambiguities.
- [x] Reject malformed, out-of-range, and unknown-canonical-movement parser payloads.
- [x] Evaluate canonical movement demands against every active restriction.
- [x] Make hard conflicts return Modify and caution conflicts return Proceed with limits.
- [x] Explain the intended stimulus preserved and the specificity compromised by substitutions.
- [x] Allow editing plan metadata, segments, movements, quantities, loads, durations, and notes.
- [x] Store planned prescriptions separately from completed movement values.
- [x] Record session RPE, movement-specific pain, post-session pain, modifications, and notes.
- [x] Add parser, ambiguity, schema-validation, scaling, persistence, and UI-flow tests.
- [x] Verify the Swift 6 app and test-bundle build.

Live acceptance remains: paste programming from Robert's gym, confirm the structured plan matches
the coach's intent, review the right-triceps conflict and candidates, then record one real session's
actual work, RPE, and pain response. New aliases can be added when real programming exposes gaps.

Live-parser acceptance defect found August 16, 2026:

- [x] Normalize mathematical-bold and other compatibility Unicode before parsing.
- [x] Treat a standalone workout heading as the title rather than a movement.
- [x] Represent repeated explicit rest lines as interval rest instead of movements.
- [x] Preserve heart-rate and intended-RPE targets as context instead of movements.
- [x] Add regression coverage for Robert's four-effort Echo Bike interval workout.

Workout-editor usability follow-up found August 16, 2026:

- [x] Replace placeholder-only workout fields with persistent labels.
- [x] Verify populated rest and context fields remain identifiable in the review flow.

Rest-semantics follow-up found August 16, 2026:

- [x] Define work-segment rest as one uniform interval between rounds or efforts.
- [x] Make dedicated Rest segments duration-only with no movements or secondary rest value.
- [x] Reject contradictory rest configurations at the parser boundary and save boundary.
- [x] Add explicit work/rest segment controls and regression coverage.

Saved-workout inspection follow-up found August 16, 2026:

- [x] Make every planned workout card open a read-only detail screen.
- [x] Show full segment, recovery, movement prescription, context, evaluation, and source details.
- [x] Make recent completed-workout rows open their recorded actual values.
- [x] Keep Edit and Record actual as separate actions and cover detail navigation in UI tests.

Workout-completion acceptance follow-up found August 28, 2026:

- [x] Preserve calorie prescriptions through Record actual, persistence, and read-only details.
- [x] Give populated actual-workout fields persistent visible labels instead of placeholder-only labels.

Pasted-workout acceptance follow-up found August 29, 2026:

- [x] Recognize spelled-out AMRAP, leading list bullets, and parenthesized/bare pound symbols.
- [x] Keep reported scores out of planned rounds, durations, movements, and stimulus targets.
- [x] Preserve reported-result text in editable segment notes without creating actual-workout records.
- [x] Add explicit overhead/American kettlebell swings to the merged movement library.
- [x] Require manual restriction review for unmapped movements instead of silently clearing them.
- [x] Add synthetic parser, load-unit, library-upgrade, persistence, restriction, and UI regression coverage.
- [ ] Confirm the corrected pasted-workout review on the physical iPhone.

Verification follow-up from August 29, 2026:

- [x] Investigate the background-thread publication warning emitted by the HealthKit metric-toggle
  unit test. Metric-inclusion notifications now publish on `MainActor`, with a regression that
  failed before the fix and passes afterward; see the HealthKit stability follow-up below.

Workout-editor acceptance follow-up (August 30, 2026):

- [x] Populate editable completed rounds and additional reps from unambiguous reported scores.
- [x] Show deterministic movement totals and prefill actual repetitions without overwriting the plan.
- [x] Use minutes with up to two decimal places for all workout duration editors and summaries.
- [x] Preserve fractional seconds in additive storage columns and keep older whole-second records readable.
- [x] Add independent movement duplication and persist movement order through save/reopen.
- [x] Replace free-text load units with lbs/kg options in planned and actual-work editors.
- [x] Add synthetic calculation, persistence, locale/precision, and editor-flow regressions.
- [x] Pass the final full unit/UI suites after editor changes: 106 unit + 15 UI, zero failures.
  Result: `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_02-13-53--0700.xcresult`.
  All 42 parser fixtures, backend lint/typecheck/10 tests, unsigned iPhone build, Swift formatting,
  schema JSON syntax, and diff checks also passed. No phone installation was performed.
- [ ] Confirm the updated editor on the physical iPhone without deleting the existing app.

Reported-total correction follow-up (August 30, 2026):

- [x] Add a discoverable editable total to each movement, separate from prescribed reps and score.
- [x] Preserve explicitly edited totals (including zero) through score changes and save/reopen;
  offer Use calculated total to reset and label manual corrections in the summary.
- [x] Keep corrections local to reviewed plans, use them in completion prefill, and leave existing
  completion records unchanged. Do not copy corrections to duplicated prescriptions.
- [x] Add synthetic calculation, reset, persistence, validation, and editor-flow regressions.
- [x] Pass targeted checks and the full unit/UI suites for the reported-total correction change:
  110 iOS unit tests, 16 UI tests, 10 backend tests, and 42 built-in parser fixtures, zero failures.
  Result: `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_13-18-26--0700.xcresult`.
  Unsigned iPhone build, strict Swift formatting, and diff checks also passed. The new UI regression
  covers correction, score changes, reset, zero, and save/relaunch persistence. No phone installation,
  commit, or push was performed.
- [ ] Confirm editable reported totals on the physical iPhone.

Keyboard-focus follow-up (August 30, 2026):

- [x] Replace the global keyboard-dismiss action with screen-scoped SwiftUI focus management.
- [x] Clear Train's source-field focus before presenting review and on sheet dismissal.
- [x] Apply consistent Done, single-line submit, scroll, navigation, save/cancel, and background
  behavior across text-entry forms; retain multiline input and independent focus for repeated rows.
- [x] Include movement search focus and explicit dismissal before opening movement editors.
- [x] Add UI regressions for the reported keyboard-return issue and multiline notes.
- [x] Pass targeted UI checks, full unit/UI suites, formatting, and an unsigned iPhone build.
  Validation: 110 iOS unit tests, 18 UI tests, and 10 backend tests, zero failures. Backend lint
  and type checking, strict Swift formatting, project-file validation, and diff checks passed.
  Result: `/tmp/whoops-apple-parser-derived/Logs/Test/Test-WhoopsApp-2026.08.30_13-51-16--0700.xcresult`.
  UI coverage includes submit/Done, scrolling, multiline notes, background/foreground, nested
  editors, cancel/save, reopening a plan, and recording actual work. No phone installation,
  commit, or push was performed.
- [ ] Confirm keyboard behavior on the physical iPhone after updating from Xcode.

Workout editing follow-up (August 30, 2026):

- [x] Audit planned/completed fields and document editable fields versus system-managed provenance.
- [x] Add explicit Edit entry points to both detail screens; preserve saved actual values on reopen.
- [x] Edit completed title, start/end/date, decimal duration, RPE, pain, notes, and score.
- [x] Edit all actual movement values/mapping; add, duplicate, remove with confirmation, and reorder.
- [x] Expose planned estimates/order/type corrections and keep timing inputs consistent.
- [x] Validate upserts before mutation and cover stable identity, optional clearing, and plan separation.
- [x] Run full unit/UI suites, targeted reruns, formatting, backend checks, and unsigned iPhone build.
  Final code passed all 118 iOS unit tests and 19/20 UI tests in
  `Test-WhoopsApp-2026.08.30_14-27-26--0700.xcresult`. The remaining startup/provenance UI test
  crashed before editor interaction during HealthKit query activation; all three targeted repeats
  passed in `Test-WhoopsApp-2026.08.30_14-40-48--0700.xcresult`. Both new edit flows passed,
  including save/cancel/relaunch, decimal load/duration, RPE/pain, and multiline targets.
  All 42 parser fixtures, backend lint/typecheck/10 tests/build, unsigned iPhone build, strict Swift
  formatting, schema JSON, project-file validation, and diff checks passed. No phone installation,
  commit, or push was performed.
- [x] Investigate the intermittent simulator startup crash separately: the captured stack is in
  HealthKit predicate/date formatting (`HKAnchoredObjectQuery.activation`, `EXC_BAD_ACCESS`), not
  workout editor frames. Confirmed application races and mitigation are documented below; the
  precise framework failure remains unproven.
- [x] Confirm editing a previously saved workout on the physical iPhone (Robert, August 30).

HealthKit stability follow-up (August 30, 2026):

- [x] Inspect the original crash and repeat baseline launches (10/10 passed; intermittent crash).
- [x] Reproduce overlapping queries/stale anchors, duplicate observer registration, and off-main
  notifications with three failing synthetic tests before changing production code.
- [x] Serialize query/import/anchor advancement with a cancellation-aware FIFO permit shared by
  manual refreshes and observers; leave history reads responsive during suspended queries.
- [x] Claim observer startup before suspension and publish metric changes on the main actor.
- [x] Cover failure recovery, observer/manual overlap, queued and active cancellation, and history
  reads during a suspended query. All 125 unit tests pass, including seven new regressions.
- [x] Pass 20 post-fix repeated simulator launches with no failures.
- [x] Pass all 42 built-in parser fixtures, backend lint/typecheck/10 tests/build, and an unsigned
  iPhone build. Strict Swift formatting, project-file validation, and diff checks pass.
- [x] Complete the full UI suite before committing and pushing the verified source checkpoint:
  20/20 UI tests passed with no crashes or failures, including the previously affected startup test.
  Final unit result: `Test-WhoopsApp-2026.08.30_15-01-12--0700.xcresult` (125/125).
  Repeated-launch result: `Test-WhoopsApp-2026.08.30_15-02-35--0700.xcresult` (20/20).
  Full UI result: `Test-WhoopsApp-2026.08.30_15-06-07--0700.xcresult` (20/20).
  Bundles are in `/tmp/whoops-apple-parser-derived/Logs/Test/`. No phone installation or data reset
  was performed during automated verification. The exact intermittent framework failure remains
  unproven despite passing checks.
- [x] Commit and push the verified workout-editing and HealthKit stability checkpoint:
  `2a149e4` (`fix: stabilize HealthKit sync and complete workout editing`) on
  `codex/milestone-6-experiments`. This includes the earlier editor and keyboard improvements;
  their preceding no-commit/no-push notes describe the state at those earlier validation stages.
- [x] Confirm repeated phone launches and Apple Health synchronization without resetting data
  (Robert, August 30, 2026: “Works.” following the Xcode update and phone-check instructions).

This closes the foreground launch/manual-sync acceptance check. The Milestone 2 check for a new
observer-driven update while backgrounded and the Apple parser's quality/device gates remain open.

See `HEALTHKIT_STABILITY.md` for evidence, implementation boundaries, and phone acceptance steps.

Apple on-device parser prototype (August 30, 2026):

- [x] Add a mockable Foundation Models provider with iOS availability checks and no cloud calls.
- [x] Validate source-quoted quantities, convert units in code, and retain deterministic restrictions.
- [x] Separate reported results and preserve missing/unsupported details as review notes.
- [x] Add on-demand serialized sessions, bounded generation, timeout, cancellation, and visible fallback.
- [x] Add test-only Train inclusion controls and review provenance without migrating saved workouts.
- [x] Add synthetic unit/UI boundary tests and a standalone production-code evaluation harness.
- [x] Complete live-model fixture evaluation and record its limitations (initial candidate: 3/30).
- [x] Implement sequential one-line classification with explicit label-to-field mapping and
  code-owned quantities, source IDs, ordering, assembly, and all-or-nothing fallback.
- [x] Compare the staged design against unchanged original expectations plus 12 fresh examples:
  28/30 original, 4/12 fresh; the fresh set prevents treating the original improvement as readiness.
- [ ] Pass the revised live accuracy gate; timed work, rest, and instruction variations still fail.
- [x] Address baseline fixture gaps: time-cap/strength headers, standalone set counts, unknown-movement
  quantities, dedicated rest, ambiguous numbers, clock durations, and the plural goblet-squat alias.
  The deterministic baseline now matches 30/30 original and 12/12 fresh fixtures.
- [x] Pass the final full unit and UI suites (98 unit + 14 UI), unsigned physical-device build,
  and backend checks. The built-in-parser phone update is ready; live Apple phone acceptance
  remains held for model quality.
- [x] Separate the phone-update path from the experiment: normal app runs use only the built-in
  parser, ignore any old Apple opt-in, and hide Apple controls; retain synthetic simulator tests
  and standalone live-model research. No phone data reset or signing/bundle-ID change is required.
- [ ] Confirm Apple parsing, fallback, latency, and peak memory on the physical iPhone.

## Milestone 4.1: Personal Movement Library and WOD Lab Migration

- [x] Persist stable personal movement facts separately from workout prescriptions.
- [x] Merge personal names and aliases with the bundled catalog for parsing and scaling.
- [x] Remember clean, unmapped movements when a reviewed plan is saved.
- [x] Rank movement selection using history-derived recency and frequency.
- [x] Support editing and archival without rewriting historical plans or completions.
- [x] Add a versioned WOD Lab movement importer with a reviewable preview.
- [x] Normalize and deduplicate imports idempotently.
- [x] Reject malformed or unsupported exports without partial writes.
- [x] Treat untagged personal movements as requiring manual restriction review.
- [x] Add persistence, matching, importer, parser-integration, safety, and UI tests.

Live acceptance remains: create one personal movement, save a plan, relaunch, and reuse the
movement. Then import Robert's WOD Lab version 1 export twice and confirm the second import adds no
duplicates. Review the demand tags for any personal movement before relying on restriction checks.

## Milestone 5: Trends and Weekly Review

- [x] Define versioned, deterministic trend and weekly-review models.
- [x] Expose historical check-ins, assessments, and injury records without exposing secrets.
- [x] Add recovery decomposition history with source-specific baselines and data sufficiency.
- [x] Add sleep trends with WHOOP-first daily observations and Apple Health fallback.
- [x] Add logged session-RPE load and unit-preserving strength-volume summaries.
- [x] Add a basic injury timeline and descriptive pain-by-movement analysis.
- [x] Generate a seven-day weekly review with sample sizes, one action, and one caveat.
- [x] Keep optional narration downstream of the deterministic report.
- [x] Export normalized local records and derived summaries as JSON and CSV.
- [x] Add analytics, missing-data, association-language, export-redaction, and UI tests.
- [x] Verify backend checks, Swift formatting, iOS builds, unit tests, and UI tests.

Live acceptance remains: review Trends after enough personal history has accumulated, share one
JSON and one CSV export to a private destination, and confirm that the summaries and wording match
Robert's judgment. The deterministic calculations remain authoritative if narration is added later.

## Redesign Phase 1: Protocol Intake and Tap-Chip Review

`docs/DESIGN.md` defines the redesign and its implementation priority. Phase 1 is camera/OCR
intake plus the tap-chip parse review (`Capture` and `ParseReview` mockups).

- [x] Add the protocol domain model: source, phase and unlock milestone, per-item cadence.
- [x] Add a versioned deterministic protocol parser that shares the movement catalog.
- [x] Surface partial movement matches as tap-to-choose candidates, never guesses.
- [x] Mark unmatched movements as new and add them to Your Movements with one tap.
- [x] Capture screen with three equal paths: camera scan, paste, and dictation.
- [x] Run Vision OCR on-device so the photographed sheet never leaves the phone.
- [x] Require on-device speech recognition for the dictation path or decline with a fallback.
- [x] Parse review with per-item cadence preset chips (daily, n×/wk, custom weekdays).
- [x] Run the shared restriction evaluation over resolved items before save.
- [x] Support swipe-left row drops with a transient undo.
- [x] Persist saved protocols and list them on Train with delete support.
- [x] Add camera, microphone, and speech-recognition usage descriptions.
- [x] Add parser, review-resolution, cadence, restriction-check, and persistence tests.
- [x] Add a UI test covering the paste path into the tap-chip review.

Deferred to later phases per the design's priority order: protocol recurrence and docket
generation, one-tap "as prescribed" logging, widget/notification completion, quick-action pain
logging, and the "bring to PT" export summary. The saved protocol stores per-item cadence so
docket generation can build on it without another migration.

Live acceptance remains: photograph the real PT sheet on Robert's iPhone, confirm the parsed
items match the sheet, resolve any candidate prompts, and confirm the restriction line reflects
the current right-arm restrictions before saving.

## Redesign Phase 2: Protocol Recurrence and Docket Generation

Phase 2 of the `docs/DESIGN.md` implementation priority: resolve per-item cadence into the
generated daily checklist on Today.

- [x] Add docket models: item kinds, generated items, and persisted completions.
- [x] Add a versioned deterministic docket engine that recomputes the docket from stored
      protocols, workouts, sleep settings, and completions — no pre-generated rows to go stale.
- [x] Resolve daily and weekday cadences against the local calendar day.
- [x] Keep times-per-week items due until the target count of completions exists in the
      calendar week, with the week's progress shown on the row.
- [x] Respect protocol active ranges and archival when generating items.
- [x] Include today's committed workouts with status mirrored from the record-actual flow.
- [x] Include the sleep wind-down item derived from the existing sleep deadline.
- [x] Render the docket on Today with drawn checkboxes, strike-through completion, and PT tags.
- [x] Complete protocol and wind-down items with one tap: haptic, drawn-check stroke
      animation, and a transient undo.
- [x] Persist completions idempotently (one per item per day) with delete for undo.
- [x] Run the iOS unit-test suite in CI on every push.
- [x] Add engine, cadence-recurrence, range, workout, wind-down, and persistence tests plus a
      docket UI test.

One-tap "as prescribed" recording with editable deviations (the RecordActual pattern) is the
next phase; until then, workout docket rows mirror the Train tab's record-actual state instead
of fabricating session RPE or pain values, and protocol-item completions record the tap without
per-set actuals. Widget/notification completion, quick-action pain logging, and the "bring to
PT" adherence export remain later phases.

Live acceptance remains: with the real protocol saved, confirm tomorrow morning's docket lists
the right items for the day and the week counts advance as items are completed.

## Redesign Phase 3: One-Tap As-Prescribed Recording

Phase 3 of the `docs/DESIGN.md` implementation priority: one-tap "as prescribed" logging with
editable deviations (the RecordActual pattern), and docket-launched workout recording.

- [x] Add `DocketActual` and snapshot-on-completion `DocketCompletion.asPrescribed(item:day:)`,
      so a one-tap completion asserts and snapshots the prescription rather than fabricating it.
- [x] Add six additive optional actual/pain/note/as-prescribed columns to
      `DocketCompletionRecord`; all-nil marks a legacy phase-2 tap-only completion, never
      backfilled.
- [x] Make the (day, kind, source) upsert overwrite a previously recorded actual, so re-logging a
      correction is idempotent rather than stacking rows.
- [x] Add `RecordActualDraft`: clamped sets/reps/hold-duration steppers, a tap-only pain scale
      that stays nil until touched, and a note, seeded from an item's prescription.
- [x] Add `JournalStepper` and `JournalScaleChip`/`JournalScaleChipRow` to the field-journal
      design system for deviation and scale entry.
- [x] Add `RecordActualSheet`: giant "as prescribed" button, steppers and pain chips for logging
      a deviation, and a note field, matching the `RecordActual` mockup.
- [x] Wire the docket: row tap logs as prescribed; a trailing "log details" button opens the
      deviation sheet; the undo bar gains "adjust" to reopen that sheet seeded from the
      completion just written.
- [x] Render a deviation aside (e.g. `2×15 · pain 1`) on a completed row only when its actual is
      not as prescribed.
- [x] Launch `WorkoutCompletionView` from workout docket rows instead of completing inline, using
      the same `saveCompletedWorkout` path the Train tab uses.
- [x] Convert `WorkoutCompletionView`'s session RPE, post-session pain, per-movement pain, and
      actual-repetitions controls from sliders/steppers/a number-pad field to the chip and
      stepper components, and rewrite the UI tests those controls previously drove.
- [x] Convert `MorningCheckInView`'s pain, energy, and motivation sliders to chip rows (T6 — a
      phase 1 leftover folded into this phase at the user's request, not new phase 3 scope).

Deferred to later phases: widget/notification completion, quick-action pain logging, and the
"bring to PT" adherence export. The three-zone visual migration is tracked separately below.

Phase 3 is complete, as confirmed by Robert. When accepting the journal visual migration below,
the real-protocol spot check is to log one item as prescribed and one as a deviation, then confirm
the deviation aside and times-per-week count still behave as before.

## Native Journal Visual Migration (after redesign phase 3)

- [x] Apply the supplied HTML mockups to the native app, not a separate web prototype.
- [x] Replace the four-tab shell with Today / Work / Body and a Settings gear.
- [x] Bundle Literata / Caveat and licenses; reuse shared paper, strokes, and chips.
- [x] Prioritize Today verdict/docket and retain detailed metrics, source status, and overrides.
- [x] Lead Work with taped protocol cards and retain workout intake, editing, and actual history.
- [x] Lead Body with named body-part records and real restrictions; keep weekly review, all
      trends, experiments, and exports reachable without fabricated healing milestones.
- [x] Restyle morning check-in, protocol flows, and record-actual; preserve keyboard dismissal.
- [x] Add left-handed margin/gear alignment and respect Reduce Motion on drawn completion.
- [x] Complete unit/UI regression tests and source-to-simulator visual comparison.
- [x] Confirm the redesigned app on Robert's phone after building this checkout in Xcode.

Initial simulator verification (August 31): **161 unit tests and 31 UI tests passed**, with zero failures;
the unsigned physical-iPhone target build passed. Normal/Accessibility XXXL, left-handed,
and entry-flow captures were compared with the HTML sources. Swift formatting, property-list
validation, and diff checks passed. Evidence and intentional native adaptations are recorded in
[`design-qa.md`](../design-qa.md).

### Daily-use dependability follow-up (August 31)

Physical-phone feedback reopened visual acceptance despite the initial simulator pass.

- [x] Reproduce the obscured bottom link with a coordinate-tap regression, not just `isHittable`.
- [x] Reserve a bounded layout row for navigation; keep the last page action above it.
- [x] Use separate readiness rows with color, icons, accessible status words, and honest missing data.
- [x] Make text actions recognizable as underlined links with 44-point touch targets.
- [x] Apply paper backgrounds, transparent rows, and bordered/focused inputs to secondary screens.
- [x] Wrap long workout titles and retain persistent workout-field labels and keyboard behavior.
- [x] Remove the duplicate Body prompt and clean only the exact shipped restriction rationale.
- [x] Add four unit regressions for presentation bands and narrowly scoped note cleanup.
- [x] Fix invalid numeric-edit update loops; add an input-state regression and UI rejection check.
- [x] Stack completed-workout history rows at accessibility sizes to keep long titles readable.
- [x] Apply readable status inks consistently and test text/input-border contrast on paper.
- [x] Add UI coverage for bottom actions at normal/Accessibility XXXL sizes and secondary routes.
- [x] Finish final-source unit/UI suites, phone-target compile, and screenshot comparison.
- [x] Replace the ambiguous Work toolbar icons with a labeled overflow menu while retaining
      capture/import, new movement, and movement-store import actions.
- [x] Add a stable affected-area catalog and additive optional restriction persistence without
      inferring anatomy from existing prose or resetting older stores.
- [x] Add the coarse full-body to focused front/back picker, explicit multi-select, list fallback,
      removable selections, one-handed confirmation, and Reduce Motion behavior.
- [x] Highlight mapped areas on Body and reuse the same picker from Body and restriction editing.
- [x] Add catalog, persistence, invalid-payload, target-size, selection, and persistence UI coverage.
- [x] Expose Restrictions as a first-class labeled Settings route.
- [x] Rename the Body record menu to “Choose restriction” and keep anatomy selection separate.
- [x] Expand the stable catalog to practical external musculoskeletal regions across the full body.
- [x] Make focus navigation visually neutral; derive highlights, rows, chips, counts, and
      confirmation copy only from selected IDs.
- [x] Connect Body selection by stable restriction identity rather than editable display names.
- [x] Add regressions proving one selected arm area does not highlight Torso or inflate the count.
- [x] Robert approves the phone checks before any remaining feature work starts.

Final follow-up verification (August 31): **167 unit tests and 33 UI tests passed**, zero failures;
unsigned physical-iPhone target build and synthetic 19-model store-upgrade checks passed.
Final captures were compared with all five annotated phone references; bottom-link coordinate
taps pass at normal and Accessibility XXXL sizes. Formatting, property-list validation, and diff
checks passed. See [`design-qa.md`](../design-qa.md) for exact output and the phone checklist.
The structured body-map follow-up adds no analytics and does not change restriction evaluation.
Targeted catalog/persistence checks and the body-map UI flow pass; the shared-architecture run
passes **171 unit tests**. The final complete UI run passes **35 of 35 cases**, including the
Settings Restrictions route and the one-arm/Torso selection-state regression.
The unsigned physical-iPhone target build, historical 19-model store upgrades, formatting,
property-list/asset JSON validation, visual comparison, and diff checks pass. Robert approved the
physical-phone checks on September 1, 2026. This checkout has not been committed or pushed in
this follow-up.

Priority is **dependable daily use → user approval → remaining low-friction logging**. No new
analytics in this pass. Preserve existing data, source connections, editing, and export access.

Remaining feature phases are **4: widget/notification completion**, **5: ad-hoc pain entry and
quick action**, and **6: bring-to-PT summary**. Phase 3 remains complete; visual rollout is not
evidence that these additional features are complete.

## Milestone 6: Personal Experiment Laboratory

- [x] Define the initial feature-flagged experiment contract and defer unsupported advanced models.
- [x] Add versioned experiment, observation, outcome, and analysis domain models.
- [x] Persist experiment definitions and one auditable observation per local day.
- [x] Resolve supported outcomes from normalized local health, workout, and check-in history.
- [x] Add deterministic, threshold-gated intervention-versus-comparison summaries.
- [x] Add experiment list, editor, detail, observation, exclusion, and archive flows.
- [x] Add an off-by-default local feature flag and experimental-data warning.
- [x] Add persistence, resolution, analysis, missing-data, feature-gating, and UI tests.
- [x] Update architecture, decision log, README status, and app version.
- [x] Verify Swift formatting, iOS builds, unit tests, UI tests, and repository checks.

Live acceptance remains: enable **Personal Experiment Lab** in Settings, create a two-condition
experiment using a metric that already has local history, log days through the single daily check-in,
and confirm the same-day or following-day outcome matches its source. Exclude one day with a reason
and confirm it remains visible but leaves the sample count. Keep the feature disabled for decisions
until both conditions reach the configured minimum and Robert's judgment supports using the result.

### Acceptance simplification

- [x] Add one Today/Lab daily check-in that saves choices across all active experiments.
- [x] Explain that conditions classify what actually happened rather than schedule future behavior.
- [x] Add explicit same-day and following-day outcome timing with safe defaults.
- [x] Move the day-logging action to the top of experiment detail.
- [x] Show custom condition names and exact remaining-day counts throughout detail and analysis.
- [x] Preserve intentional same-experiment, same-day updates with an update notice.
- [x] Cover timing, batch persistence, custom labels, and simplified UI behavior with tests.
- [x] Let the user delete experiment days and whole experiments with clear confirmation.
- [x] Audit user-entered records: delete standalone history, clear overrides, and explain why
      referenced movement definitions are archived instead of deleted.
- [x] Load and save condition days independently from deterministic outcome refresh.
- [x] Distinguish logged condition days from usable days with resolved outcomes.
- [x] Explain when a selected outcome requires direct WHOOP history rather than Apple Health.
- [x] Keyset-page and cache source-specific history projections instead of scanning unrelated samples.
- [x] Move an edited condition day to a new date without copying it or overwriting an occupied day.
