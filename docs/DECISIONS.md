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
- **Decision:** `deterministic-1.4.0` is the default parser. It preserves raw text, applies Unicode
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

## Open decisions

The unresolved implementation questions in `PROJECT_PLAN.md` remain open, including the final
bundle identifier, Apple signing team, production domains, PostgreSQL provider, credential
encryption mechanism. The workout parsing provider is resolved by ADR-017; any future narration or
historical-query provider remains a separate decision.
