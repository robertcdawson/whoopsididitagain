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

## ADR-007: Keep workout parsing local-first and schema-gated

- **Date:** August 16, 2026
- **Status:** Accepted
- **Decision:** `deterministic-1.2.0` is the default parser. It preserves raw text, applies Unicode
  compatibility normalization, maps only approved
  aliases, and reports unknown or incomplete prescriptions as explicit ambiguities. Parsed payloads
  must pass the versioned workout JSON Schema and domain validation, including mutually exclusive
  work-segment recovery and dedicated Rest segments. Manual entry remains available.
- **Rationale:** Core workout planning must work offline, missing quantities must never be invented,
  and a future LLM should be an optional structured-input producer rather than an authority.

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

## Open decisions

The unresolved implementation questions in `PROJECT_PLAN.md` remain open, including the final
bundle identifier, Apple signing team, production domains, PostgreSQL provider, credential
encryption mechanism, and LLM provider.
