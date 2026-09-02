# Architecture Decisions

Decisions in `PROJECT_PLAN.md` remain settled. This log captures implementation-level choices.

## ADR-001: Version app-facing routes from the first endpoint

- **Date:** August 15, 2026
- **Status:** Accepted
- **Decision:** App-facing backend routes begin under `/api/v1`.
- **Rationale:** The iPhone app and deployed backend may update independently. Explicit versions
  prevent silent contract changes and support staged migrations.

## ADR-002: Use a uniform response envelope and request correlation ID

- **Date:** August 15, 2026
- **Status:** Accepted
- **Decision:** Successful responses use `{ data, meta }`; errors use `{ error, meta }`. Metadata
  includes a non-empty `requestId` that is also returned in the `x-request-id` header.
- **Rationale:** Stable error handling and correlation are needed before OAuth and synchronization
  add distributed failure modes. Sensitive payload logging is not required for diagnosis.

## ADR-003: Keep domain protocols independent of framework implementations

- **Date:** August 15, 2026
- **Status:** Accepted
- **Decision:** WHOOP, HealthKit, parsing, readiness, narration, and storage are represented by
  `Sendable` protocols in the iOS domain layer.
- **Rationale:** External systems can be mocked in tests, deterministic behavior stays separable
  from generated prose, and Swift concurrency assumptions are explicit.

## ADR-004: Require synthetic-only committed fixtures

- **Date:** August 15, 2026
- **Status:** Accepted
- **Decision:** Every committed health fixture is fabricated and includes an explicit synthetic
  notice where the format permits it.
- **Rationale:** Real personal health exports create unnecessary privacy and credential risk.

## ADR-005: Treat HealthKit read authorization as opaque and source preserving

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** After the authorization flow, the UI calls Apple Health `Connected` and immediately
  explains that imported categories depend on the user's choices because Apple does not reveal
  which read categories were denied. HealthKit records retain source and time-zone metadata, and
  likely duplicate workouts are linked instead of merged or deleted.
- **Rationale:** HealthKit intentionally does not disclose denied read categories. Preserving each
  source avoids false certainty, supports partial permission, and keeps later reprocessing auditable.
  `Connected` describes completion of setup; the adjacent explanation prevents it from claiming
  category-level authorization that HealthKit cannot confirm.

## ADR-006: Make readiness deterministic, versioned, and constraint-first

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** `readiness-1.0.0` calculates systemic, sleep, and tissue components locally from
  source-specific 28-day robust baselines, the morning check-in, and active restrictions. Hard
  restrictions are applied before the overall recommendation. Missing inputs lower confidence and
  emit reason codes. Overrides are annotations on the calculated assessment, not replacements.
- **Rationale:** The daily recommendation must remain available without an LLM, must never let a high
  recovery score erase a local injury constraint, and must be auditable when data is sparse or the
  user disagrees.
- **Amended August 28, 2026:** `readiness-1.0.1` caps a completed check-in's tissue score at 39 when
  an active `avoid` restriction exists. It preserves lower symptom-derived scores and leaves the
  tissue score missing when the check-in is missing; the independent hard override remains intact.

## ADR-007: Keep workout parsing local-first and schema-gated

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** `deterministic-1.5.0` is the default parser. It preserves raw text, applies Unicode
  compatibility normalization, maps only approved
  aliases, and reports unknown or incomplete prescriptions as explicit ambiguities. Parsed payloads
  must pass the versioned workout JSON Schema and domain validation, including mutually exclusive
  work-segment recovery and dedicated Rest segments. Manual entry remains available.
- **Rationale:** Core workout planning must work offline, missing quantities must never be invented,
  and a future LLM should be an optional structured-input producer rather than an authority.
- **Amended August 29, 2026:** Normalize leading list bullets and `#` load notation, recognize
  spelled-out AMRAP, and exclude explicit reported-result lines from prescription inference.
  Preserve reported scores in existing, editable segment notes without automatically recording
  actual work or adding a storage schema. Add explicit overhead swing aliases without guessing
  the range of motion of an unspecified swing. Unmapped movements retain restriction-review
  cautions. No AI provider or model is connected by this change; a future optional parser requires
  representative evaluations and the same validation, review, and deterministic safety boundaries.
- **Amended August 30, 2026:** Fix time-cap metadata, standalone strength sets, missing quantities on
  unmapped movements, and explicit rest structure. Preserve uncertain ranges/alternatives for review
  instead of selecting a number; recognize bounded clock-format durations.
- **Editor amendment August 30, 2026:** Store unambiguous reported round/repetition results separately
  from prescriptions and expose editable result fields. Code derives partial-round movement totals
  only for a single rep-based AMRAP/rounds segment, in written order. Saving a plan never creates a
  completion. Completion values are prefilled for explicit review; uncertain totals stay blank.
  Use Double seconds in the domain and additive optional precision columns in SwiftData, falling back
  to legacy integer columns. This supports hundredths of a minute without rounding subsecond values
  or changing existing attribute types. Persist explicit movement order and optional result snapshots.
  Duplicate prescriptions with fresh IDs; preserve their movement-library links. Unit pickers expose
  only lbs/kg, retain canonical lb/kg storage, and do not silently convert load values.
- **Reported-total correction amendment August 30, 2026:** Allow independent, visibly labeled manual
  movement totals, including zero, with a reset to calculated totals. Store overrides on the reviewed
  plan by movement ID, not in parser output or prescribed reps. Preserve them when the score changes,
  do not copy them when duplicating prescriptions, and remove them with deleted movements. Use an
  additive optional JSON column; old records need no reparse. Completion prefill prefers corrections
  without changing the separate reported score or previously saved completions.

## ADR-008: Preserve planned and actual training as separate records

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** Plans retain their parsed and user-edited segments and prescriptions. Completing a
  workout creates separate actual-movement records linked back to the plan and records modifications,
  RPE, and pain without overwriting planned values.
- **Rationale:** Intended-versus-actual analysis is impossible if completion mutates the source plan.
  Separate records also make user modifications and symptom responses auditable in later trends.

## ADR-009: Layer a personal movement library over bundled definitions

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** Store stable personal movement facts locally and merge them with the bundled catalog.
  Derive usage from workout history, keep prescriptions on plans and completions, and treat WOD Lab
  import as an idempotent local migration rather than synchronization.
- **Rationale:** Remembered names and aliases reduce repeated entry and improve parsing without
  leaking stale loads or repetitions into future workouts, mutating safety-reviewed bundled
  definitions, or creating a continuing dependency on WOD Lab.

## ADR-010: Make longitudinal summaries deterministic and export normalized projections only

- **Date:** August 21, 2026
- **Status:** Accepted
- **Decision:** `trends-1.0.0` consumes normalized repository snapshots and produces source-specific
  trends plus a structured weekly report. The primary window is seven local days, the comparison
  window is the prior seven, and baselines use at most 28 observations. Every statement carries a
  sample size or insufficient-data label and uses association language. JSON and CSV exports include
  normalized projections and derived results, never raw WHOOP payloads or authentication material.
- **Rationale:** A deterministic analytical boundary keeps charts, summaries, export, and optional
  narration consistent; prevents source-specific metrics from being blended; makes sparse-data
  behavior testable; and reduces the chance of exporting credentials or unnecessarily sensitive raw
  vendor payloads.

## ADR-011: Make personal experiments assignment-light and threshold-gated

- **Date:** August 22, 2026
- **Status:** Accepted
- **Decision:** `experiments-1.0.0` stores one intervention or comparison assignment per local day
  and resolves its outcome from normalized local history at analysis time. It reports arithmetic
  means and intervention-minus-comparison only after both conditions meet the configured minimum.
  Exclusions remain auditable, and the off-by-default feature never claims causation or treatment
  efficacy.
- **Rationale:** Re-entering WHOOP or Apple Health measurements creates needless daily work and
  inconsistent copies. Threshold gating, source reuse, sample counts, missing-value disclosure, and
  preserved exclusions make an N-of-1 comparison inspectable without overstating an early personal
  signal or introducing an immature predictive model.

## ADR-012: Log experiment conditions once and make outcome timing explicit

- **Date:** August 22, 2026
- **Status:** Accepted
- **Decision:** `experiments-1.1.0` treats a condition as a retrospective statement about what
  actually happened on a local day. One daily check-in can update all active experiments in one
  save. Each experiment explicitly resolves its outcome on either the condition day or the following
  day, with following-day defaults for morning physiology, sleep, and morning check-ins and a
  same-day default for completed-workout load. Individual day editing remains available for
  correction, exclusion, and context.
- **Rationale:** Separate per-experiment logging creates unnecessary daily work, while same-day-only
  matching can place a morning outcome before the behavior it is intended to follow. A single daily
  workflow and visible timing rule reduce interaction cost and make the temporal interpretation
  auditable without pretending arbitrary condition text can always be inferred from a workout.

## ADR-013: Delete standalone entries and preserve referenced definitions

- **Date:** August 22, 2026
- **Status:** Accepted
- **Decision:** User-entered standalone records expose a confirmed delete or clear action from the
  screen where they are viewed. Parent deletion removes records owned only by that parent, such as
  an experiment's condition days or a completed workout's actual movements. Stable movement
  definitions are archived instead of deleted because saved workouts may refer to them; the app
  explains this exception in plain language. Required singleton configuration, currently the sleep
  schedule, resets to defaults and explains why it cannot remain absent.
- **Rationale:** A personal health log should not trap corrections or accidental entries. Explicit
  ownership rules make deletion predictable, while archiving shared definitions keeps historical
  workouts readable and avoids dangling references.

## ADR-014: Bound HealthKit imports and advance anchors after durable pages

- **Date:** August 27, 2026
- **Status:** Accepted
- **Decision:** HealthKit anchored queries cover the latest 180 days and return at most 500 samples
  per page. The app persists each page in a fresh SwiftData context before saving that page's anchor
  and requesting the next page. History projections aggregate recent records in similarly bounded
  pages, and record counts use store-level counts rather than materializing every source record.
- **Rationale:** The first physical-device import was terminated while HealthKit attempted to return
  an unlimited result set, before any row reached SwiftData. Bounded queries and per-page anchors cap
  peak memory, preserve resumability after interruption, and retain idempotent deletion and upsert
behavior without weakening source fidelity.

## ADR-015: Build projections from source-specific, keyset-paged history

- **Date:** August 27, 2026
- **Status:** Accepted
- **Decision:** Keep normalized source records as the local source of truth, but build UI projections
  only from the metrics and repositories they require. HealthKit history uses metric-filtered,
  stable-ID keyset pages over the existing unique index and a cache invalidated by every committed
  sync page. Experiment
  condition days load independently from analysis, and condition-day saves do not wait for analysis
  refresh. Experiment results display logged counts separately from counts with resolved outcomes.
- **Rationale:** A physical-device import produced 85,126 HealthKit records, of which 66,724 were
  raw heart-rate samples not used by the current daily projection. Repeatedly scanning and sorting
  that full table on the main actor made experiment loading and saving appear stalled. Source-specific
  projections preserve deterministic semantics and source fidelity while making cost proportional
  to the data actually needed.

## ADR-016: Exclude Apple Health inputs at the repository projection boundary

- **Date:** August 27, 2026
- **Status:** Accepted
- **Decision:** Settings exposes a reversible inclusion toggle for every Apple Health metric used by
  the app. Disabled metrics remain imported and auditable but are filtered at the HealthKit
  repository boundary before Today, readiness, trends, or experiment analysis receives them.
  Synchronization continues so re-enabling an input is immediate and does not require a destructive
  re-import. New metric types default to included.
- **Rationale:** Authorization and local retention are different from analytical inclusion. A stale,
  partial, or unwanted source such as Apple Health HRV SDNN should be removable from every
  downstream calculation without disconnecting Apple Health, losing other useful metrics, or
  deleting recoverable source records.

## ADR-017: Use Apple's on-device model as a bounded workout extractor

- **Date:** August 30, 2026
- **Status:** Prototype implemented; live accuracy gate failed; not approved as the default parser
- **Decision:** Use Foundation Models as an optional, request-only workout extraction provider.
  Preserve the current deterministic parser, manual editor, merged movement catalog, restriction
  engine, and explicit save review. No cloud provider, API key, backend change, custom adapter, or
  downloadable third-party weights are part of this slice. After live testing found substantial
  extraction errors, the phone-update boundary supplies no model and hides the experimental Train
  toggle in normal runs, even if an old opt-in remains stored. Only DEBUG simulator synthetic-provider
  runs expose test controls; the standalone Mac harness retains real-model evaluation. The research
  code can be committed without enabling it on the phone. Do not promote this prototype based on
  mock tests alone.
- **Boundary:** The staged model chooses one explicit label per source line (such as `exercise_line`
  or `strength_header`); code maps that label to role/format fields. Code owns
  quantity extraction, source IDs, ordering, and assembly. Code checks evidence,
  converts units, maps movement IDs, calculates stimulus, and applies restrictions. Reported results
  are removed before generation and restored as separate notes. Generated demand tags, safety
  decisions, calculated training loads, and automatic actual-workout creation are prohibited.
- **Reliability:** Bound input, output, and time; serialize model sessions; discard late/cancelled
  results; show deterministic fallback provenance. Model unavailability must not block the rest of
  the app. Preserve iOS 18 compatibility with runtime availability checks.
- **Verification:** Mock-based unit/UI tests exercise failure boundaries separately from a
  standalone, production-code live-model evaluation over synthetic fixtures. Neither mocked tests
  nor Mac results substitute for phone latency/memory and user acceptance. OS updates require
  reevaluation because the system model may change.
- **Quality finding:** The first 30-case synthetic evaluation matched only 3 expected structures.
  Required-string fields and a smaller freeform JSON prompt each failed all six targeted cases.
  These experiments do not establish Apple's general capabilities, but this broad, single-pass
  extractor is not sufficient. The replacement staged hybrid uses fresh, sequential sessions and
  one unambiguous generated label per line. A failed or unverified part discards the assembled draft.
  The entire attempt retains its 20-second deadline, with at most 16 parts and 40 response tokens
  per part. The updated live accuracy gate remains separate from mocked assembly tests; see
  `APPLE_WORKOUT_PARSER.md` for measured results. No default-on or phone rollout is implied.

## ADR-018: Screen-scoped keyboard focus

- **Date:** August 30, 2026
- **Status:** Implemented
- **Decision:** Use SwiftUI `FocusState` scoped to each input screen and explicit focus clearing at
  navigation, save/cancel, sheet, and background boundaries. Give repeated fields independent IDs,
  provide a Done action and immediate scroll dismissal, and preserve multiline Return behavior.
  Clear the Train paste field before presenting review so it cannot regain focus on dismissal.
- **Scope:** All current text-entry forms and movement searches. No global UIKit responder
  broadcast, delayed dismissal, or catch-all tap gesture. Domain values and persistence are unchanged.
- **Verification:** UI regressions assert keyboard disappearance through nested editing, sheet
  dismissal, save/cancel, tab changes, and background/foreground; multiline notes remain editable.
- **Reference:** [Apple FocusState documentation](https://developer.apple.com/documentation/swiftui/focusstate).

## ADR-019: Serialize HealthKit import transactions across suspension points

- **Date:** August 30, 2026
- **Status:** Implemented
- **Decision:** Use one cancellation-aware FIFO import permit per HealthKit repository, shared by
  manual and observer-triggered refreshes. Hold it from anchor read through all query pages and
  persistence/anchor advancement. Keep history reads outside this permit. Claim observer startup
  atomically before awaiting delivery registration; publish source-selection changes on `MainActor`.
- **Rationale:** Actor isolation alone does not serialize an entire asynchronous transaction.
  Synthetic tests reproduced overlapping queries with stale anchors, duplicate observer startup,
  and off-main notifications. The import permit also removes the concurrent HealthKit activation
  pattern present in a simulator startup crash, without clearing stores or serializing all UI work.
- **Limit:** The precise cause of the framework's predicate-formatting crash remains unproven.
  See `HEALTHKIT_STABILITY.md`; passing retries alone are not proof of a framework fix.
- **Reference:** [Apple actor reentrancy guidance](https://developer.apple.com/videos/play/wwdc2021/10133/).

## ADR-020: Record as prescribed by assertion; snapshot quantities; never backfill

- **Date:** August 30, 2026
- **Status:** Implemented
- **Decision:** A one-tap docket completion is the user's assertion that the prescribed sets,
  repetitions, and hold duration were met, so those prescribed quantities are copied into the
  stored actual and snapshotted at the moment of completion — editing the protocol afterward
  cannot rewrite what was already logged. Pain stays absent until a chip is tapped and is stored
  as nil, never defaulted to zero. Existing completions recorded before this change have no
  actual at all; they keep their original tap-only meaning and are never backfilled with
  invented quantities. The new fields are six additive optional columns on the existing
  `DocketCompletionRecord` rather than a new entity, so the combined store's tracked-model count
  is unchanged.
- **Rationale:** ADR-008 already draws the line that completion records must not overwrite
  planned values; copying an asserted prescription into an actual is the same discipline applied
  to the docket, not the fabrication phase 2 refused. ADR-013's ownership rules mean the docket's
  undo/adjust actions must correct or delete a completion the user owns rather than silently
  rewriting history, which is why a deviation always creates or overwrites one row per
  (day, kind, source) rather than layering entries.

## ADR-021: Apply the journal design without rewriting health or workout history

- **Date:** August 30, 2026
- **Status:** Implemented; accepted on Robert's phone September 1, 2026
- **Decision:** Implement the supplied journal mockups in the production SwiftUI screens using
  shared vector components, locally bundled open-licensed fonts, three navigation zones, and a
  Settings sheet. Retain all existing editing/analysis paths through focused disclosures and
  detail links. Use the specified light palette for this release; do not invent a dark design.
- **Rationale:** Redesign phases 1–3 delivered features but left the old dashboard shell visible.
  A dedicated visual migration closes that gap without changing the 19-model store or deterministic
  calculations. Mockup surgery dates, healing claims, countdowns, and adherence percentages must
  not become fabricated user records. Only persisted facts and established calculations appear.
- **Phone-feedback amendment August 31, 2026:** Reserve actual layout space for journal
  navigation rather than overlaying scroll content. Extend the shared paper/link/input styles
  to all secondary forms; keep platform date, keyboard, and accessibility behavior. Readiness
  uses separate color-coded rows with non-color status cues. Clean only the exact obsolete
  seeded restriction rationale, preserving custom notes and timestamps. Complete this daily-use
  dependability pass and obtain Robert's approval before the remaining low-friction logging
  features; no additional analytics are authorized by this pass.
- **Discoverability amendment September 1, 2026:** Present Restrictions as a labeled first-class
  Settings route. Name the Body record selector “Choose restriction” so it cannot be mistaken for
  the anatomical affected-area catalog.

## ADR-022: Store explicit affected areas; use semantic zoom without anatomical inference

- **Date:** August 31, 2026
- **Status:** Implemented; accepted on Robert's phone September 1, 2026
- **Decision:** Keep the full-body figure coarse and use it to open a focused front/back selector.
  Persist only stable catalog IDs that the user explicitly selects. Support multi-select, an
  entire-limb option, a complete list fallback, and removal/clear actions. Keep the existing
  free-text body-region and side fields independently editable; never derive IDs from those
  strings, the restriction name, or its rationale.
- **Anatomy boundary:** Treat the posterior upper arm as the triceps area and the posterior elbow
  as a separate area. The map is descriptive localization, not diagnosis, medical advice, or
  movement clearance. Restriction-demand rules remain the safety authority already defined by
  the deterministic engine.
- **Persistence:** Add one optional JSON column to the existing injury entity. Empty or legacy
  records decode as no mapped areas, unknown IDs are ignored, and no store reset or backfill is
  permitted.
- **Accessibility:** Use 44-point targets, ordinary taps, a persistent full-width confirmation,
  a text-list alternative, front/back controls, and Reduce Motion-aware transitions so the flow
  remains practical one-handed.
- **Selection invariant:** Coarse focus is navigation only. A focus region is highlighted only when
  its stable whole-region ID is explicitly selected. Every visible selected state and count derives
  from the same validated ID set.
- **Catalog scope:** Cover practical external musculoskeletal regions across the entire body, with
  large non-overlapping figure targets and finer list choices. Keep hip/groin/glute localization in
  one canonical focus. Do not claim exhaustive clinical anatomy or infer diagnoses, organs,
  muscles, or bones from free text. Regional terms follow OpenStax and FIPAT references linked in
  `DESIGN.md`.

## ADR-023: Keep outside-app docket actions narrow and app-reconciled

- **Date:** September 1, 2026
- **Status:** Phase 4 in progress
- **Decision:** Keep the 19-model SwiftData store app-owned. Share only a versioned snapshot of
  today's user-visible docket and durable file-per-action completion requests through the App
  Group. Widgets and App Intents may optimistically overlay a pending request, but only the app
  reconciles it through `DocketRepository`, republishes the snapshot, and acknowledges the file.
- **Completion boundary:** Protocol and wind-down items may be completed as prescribed without
  opening the app. Workouts must open their existing completion flow because session RPE, pain,
  and actual work cannot be inferred from a one-tap action. Notification actions and App Shortcut
  phrases must reuse the same bridge.
- **Rationale:** Moving or opening SwiftData from an extension would enlarge the data and migration
  boundary and create competing writers. File-per-action requests survive process termination;
  the existing local-day/kind/source upsert makes replay idempotent, and publishing before
  acknowledgment avoids a lost-action window. The shared container excludes health history, raw
  provider payloads, credentials, and backend state.
- **Scope:** Reminders are local and opt-in. No backend push service, analytics expansion, or
  outside-app workout fabrication is authorized by this decision.

## Remaining open decisions

The unresolved implementation questions in `PROJECT_PLAN.md` remain open, including the final
bundle identifier, Apple signing team, production domains, PostgreSQL provider, credential
encryption mechanism. The workout parsing provider is resolved by ADR-017; any future narration or
historical-query provider remains a separate decision.
