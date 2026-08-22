# Architecture

**Status:** Milestone 5 trends and weekly review implemented
**Last updated:** August 21, 2026

`PROJECT_PLAN.md` is the product source of truth. This document records the architecture that is
currently implemented.

## System boundary

```mermaid
flowchart LR
    W["WHOOP API v2"] --> B["Next.js backend"]
    B --> I["SwiftUI iPhone app"]
    B --> P[("Encrypted OAuth credentials and sync checkpoints")]
    I --> K["Keychain app session"]
    I --> L[("Local SwiftData health records")]
    H["Apple Health / HealthKit"] --> I
```

The backend is the only component that receives the WHOOP client secret, access token, or refresh
token. The app receives a separate signed app session and stores it in Keychain. WHOOP health
payloads pass through the backend response but are persisted only on the phone.

HealthKit access is read-only and never passes through the backend. The app requests each selected
sample type independently, so categories the user denies behave as empty sources while allowed
categories continue synchronizing.

## WHOOP connection

1. The app creates a stable installation UUID in Keychain.
2. The backend creates an eight-character WHOOP OAuth state and stores only its hash.
3. `ASWebAuthenticationSession` opens the WHOOP authorization page.
4. The backend callback consumes the state, exchanges the WHOOP code, encrypts the rotating token
   pair with AES-256-GCM, and redirects to `whoops://oauth/callback` with a one-time code.
5. The app exchanges that code for a 15-minute access session and a 30-day refresh session.
6. WHOOP refresh-token rotation runs under a per-installation lock and persists both replacement
   tokens atomically.

Production uses PostgreSQL and the migration in `backend/migrations`. Non-production runs without
`DATABASE_URL` by using an intentionally ephemeral in-memory store.

## Synchronization and storage

Initial synchronization fetches the previous 180 days of cycles, recoveries, sleeps (including
naps), and workouts. Each collection is paginated until WHOOP omits `next_token`. Later runs begin
48 hours before each resource checkpoint to tolerate late updates and clock skew. No checkpoint is
advanced if any resource fetch fails.

The app stores each raw source record using the stable key `<resourceType>:<sourceIdentifier>` and
updates it idempotently. Basic recovery and sleep projections are derived locally for Today and
Trends. The backend stores only credentials, WHOOP user ID, app installation/session metadata, and
per-resource checkpoints.

HealthKit synchronization uses one archived `HKQueryAnchor` per sample type. New samples are
upserted by HealthKit UUID and deleted-object callbacks remove only the matching local source
record. Observer queries trigger the same anchored path; background delivery is opportunistic.
Every sample stores its source, source bundle, source-time-zone identifier, UTC offset, and local
calendar day. This keeps historical day grouping stable when the phone later travels or crosses a
DST boundary.

WHOOP and HealthKit workout records remain independent. A separate link records likely duplicates
when start time and duration are close. WHOOP HRV RMSSD and Apple Health HRV SDNN are also separate
metrics rather than a blended series.

## Daily assessment

The app owns the complete assessment path locally. SwiftData stores one morning check-in per local
day, editable injury and movement restrictions, sleep-schedule settings, and the calculated
assessment. A calculation record retains its ruleset version, component scores, confidence, reason
codes, and strongest signals. A user override and annotation are stored alongside, rather than
replacing, the calculated recommendation.

`readiness-1.0.0` uses robust 28-day medians and median absolute deviations for source-specific
physiology trends. WHOOP HRV RMSSD and Apple Health HRV SDNN never share a baseline. Fewer than 14
observations suppress strong baseline claims and reduce confidence. Missing current physiology,
sleep, check-in, or restriction context likewise reduces confidence and produces an explicit reason
code.

The engine calculates systemic, sleep, and tissue components before selecting a recommendation.
An active `avoid` restriction is a hard constraint and forces `Modify` even when recovery is high.
The Today screen presents the strongest reasons and the effective recommendation. Sleep deadlines
are derived locally from wake time, sleep target, expected latency, and wind-down duration.

## Workout planning and completion

Workout processing is local and deterministic in `deterministic-1.2.0`. The parser preserves the
raw text, normalizes known aliases through a canonical movement catalog, extracts only quantities it
can identify, and creates an explicit ambiguity for anything unknown or incomplete. The complete
payload boundary is defined by `contracts/workout-parser.schema.json`; the same domain validator
rejects invalid confidence, nonpositive quantities, empty segments, and unknown canonical IDs. A
future LLM may propose this payload, but cannot bypass validation or the manual-entry fallback.

Compatibility Unicode is normalized before classification, so mathematical-bold programming parses
like ordinary text. A standalone heading becomes the plan title. Repeated one-movement efforts with
a common explicit rest are represented as one interval segment with `restSeconds`; heart-rate and
intended-RPE targets remain editable context rather than becoming movement rows.

For a non-rest segment, `restSeconds` means one uniform recovery between repeated rounds or efforts.
A dedicated `rest` segment instead stores its required recovery length in `durationSeconds` and has
no movements, rounds, or secondary `restSeconds`. This makes variable recovery an explicit sequence
of work and rest segments and prevents either representation from silently overriding the other.

`workout-scaling-1.0.0` intersects movement-demand tags with active restriction demands. An `Avoid`
match is a hard conflict and returns `Modify`; softer matches return `Proceed with limits`. Candidate
substitutions come only from the approved catalog and are filtered so they do not retain the matched
restricted demand. Explanations state the intended stimulus being preserved and the movement
specificity that may be lost.

SwiftData stores workout plans, segments, and prescriptions independently from completed workouts
and completed movements. Completion starts as an editable copy of the plan, then saves actual
repetitions, distance, load, duration, modifications, movement pain, session RPE, and post-session
pain without rewriting the planned values.

The Train screen treats saved cards as navigable records. A planned-workout detail view reads the
stored overview, stimulus, restriction evaluation, segment structure, prescriptions, and original
source without mutating them. Recent completed-workout rows similarly open the actual session values;
editing and completion remain separate explicit actions.

The effective movement catalog is a deterministic merge of bundled definitions and local personal
records. Plans and completions reference stable movement identifiers, while repetitions, load,
distance, duration, tempo, modifications, and pain remain workout-specific. Search recency and
frequency are derived from saved workout history rather than stored as counters.

Parser matching, schema validation, and restriction evaluation receive the same merged catalog
snapshot. Personal movements without reviewed demand tags remain usable for planning, but generate
a manual-review caution when an active restriction exists instead of receiving an affirmative safe
result.

WOD Lab migration is local-only and idempotent. The version 1 adapter reads `stores.movements`,
validates records, maps supported stable fields, previews additions and matches, and commits only
after confirmation. It does not import workout history, prescriptions, technique notes, or coaching
metadata in this increment.

## Repository

- `ios/WhoopsApp`: SwiftUI app, Keychain session store, SwiftData persistence, tests
- `backend`: Next.js App Router OAuth/sync service, PostgreSQL adapter, Vitest tests
- `contracts`: v1 JSON Schema contracts mirrored by Swift `Codable` models
- `fixtures`: synthetic-only test inputs
- `docs`: product, architecture, decisions, and execution status

## Trends, weekly review, and export

Milestone 5 reads normalized local projections through repository protocols; the analytics engine
does not query SwiftData or external services directly. It builds source-specific recovery and sleep
observations, session-RPE load, unit-preserving strength volume, current injury records, and
descriptive pain-by-movement summaries. Seven-day results compare with the preceding seven days,
while robust baselines use at most 28 observations.

The structured weekly report is deterministic and versioned. Every claim includes its observation
count or states that the available data is insufficient, uses association language, and includes one
action plus one caveat. Optional narration is a presentation adapter over that report and is never a
calculation or safety authority.

Local export serializes only normalized app-facing records and derived summaries. JSON preserves
structure; CSV uses one record-type column and stable flattened fields. Raw WHOOP payloads, OAuth
credentials, app sessions, Keychain contents, backend environment values, and encryption material
are outside the export boundary.

Experiments, predictive dose-response modeling, free-form historical questions, and generated
explanations remain outside Milestone 5. Parsing, scaling, readiness, trends, weekly review, and
export do not depend on an LLM.
