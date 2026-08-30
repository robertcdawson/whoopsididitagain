# Implementation Tasks

`PROJECT_PLAN.md` defines milestone scope and acceptance criteria. This file tracks execution.

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
  was performed. The exact intermittent framework failure remains unproven; phone acceptance follows.
- [ ] Confirm repeated phone launches and Apple Health synchronization without resetting data.

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
