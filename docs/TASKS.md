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
