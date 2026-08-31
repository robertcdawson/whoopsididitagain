# Design

**Status:** Design exploration complete; phases 1–3 of the implementation priority (camera/OCR
intake + tap-chip review; protocol recurrence + docket generation; one-tap as-prescribed
recording with editable deviations) implemented — see `ARCHITECTURE.md` and `TASKS.md`
**Last updated:** August 31, 2026

This document specifies the app redesign produced in the design exploration session. It is the
implementation reference for restructuring the app around a three-zone information architecture,
a serif "field journal" visual system, and one-handed, low-typing entry flows for post-surgery
rehab (tricep tendon repair, physical therapy incoming).

Static mockups for every screen described here live in [`design/mockups`](design/mockups) as
self-contained HTML files with exact colors, sizes, and copy. Read them alongside this document;
where prose and mockup disagree, the mockup wins for visual values and this document wins for
behavior.

## Purpose and positioning

The app exists so one recovering body can **decide today wisely, log honestly, and believe the
slow game is working**. It deliberately does not duplicate WHOOP: WHOOP owns sensor data and
charts; this app owns the plan, the restrictions, and the one decision per day. Its unique loop:

readiness → what am I cleared for → do it and log it → pain/RPE feeds back into tomorrow's
readiness and the long-term story.

Differentiators over WHOOP / Apple Health, which every screen must serve:

1. **Tissue-aware readiness** — restrictions are first-class; every planned movement is checked
   against them (existing restriction-demand tags in the movement catalog).
2. **Commitments, not just measurements** — planned vs. actual stored separately with RPE,
   modifications, and pain response (already implemented in the Train feature).
3. **PT protocols as first-class training** — new: recurring prescribed work with phases and
   unlock milestones, sharing the movement library and restriction checks.
4. **Pain with an address** — pain-by-movement over time (exists in Trends; gets a quick-entry
   path).
5. **One deterministic, explainable, overridable call** — no LLM required; honest sample sizes;
   association-not-causal language (existing readiness engine and weekly review).

## Information architecture

Replace the current four tabs (Today / Train / Trends / Settings) with **three zones plus a
settings gear** (gear opens the existing Settings content as a sheet or pushed screen):

| Zone | Replaces | Contents |
| --- | --- | --- |
| **Today** | Today tab | One verdict + one compressed metrics line + **the docket** (all of today's committed items — PT exercises, workouts, wind-down — as a single checklist). Morning check-in and record-actual launch from here. No metric grids: WHOOP has the graphs. |
| **Work** | Train tab | Everything committed. The **PT protocol card** (phase x of y, day n of m, per-item cadence, adherence, next unlock) above the existing workout planning/parsing. Protocols and workouts share the movement library and restriction checks. "Your Movements" lives here. |
| **Body** | Trends tab | The long story organized **by body part, then systemically**: per-part timeline (surgery → milestones → today → next unlock), pain-by-movement trends, then compressed systemic trends with sample sizes, and the weekly review behind one link. |

Mockups: `TodayZone`, `WorkZone`, `BodyZone`.

### New domain concepts

- **Protocol** — a plan that *recurs*. Fields: source (photo/paste/dictation), phase list with
  unlock milestones (e.g. "full extension"), items with per-item cadence (daily, 3×/wk, custom),
  active date range. Parsed by the existing deterministic parser; ambiguities surface as
  candidate choices, never guesses (existing parser behavior — keep it).
- **Docket** — the generated daily checklist: today's due protocol items + planned workouts +
  sleep wind-down. Each item completes with one tap and records "as prescribed" unless edited.
- **Pain event** — ad-hoc: body part, 0–10, optional dictated note, timestamp; feeds
  pain-by-movement and the part's timeline. Amend/delete by swiping the event in the part story.
- **Adherence** — per protocol item per period ("5 of 7 days"); shown on Work and in the weekly
  review; exportable for the PT ("bring to PT" summary).

## Entry flows (one-handed, minimal typing)

Design constraint: the user has one working hand (non-dominant) for weeks post-surgery. Rules,
in force everywhere:

- Bottom sheets with primary actions in the thumb zone; ≥44pt targets.
- **Tap chips instead of sliders and keyboards**: 0–10 pain scales and 1–5 energy/motivation are
  discrete chip rows; symptoms are multi-select pills. (The current check-in's `Slider`s and the
  completion view's number-pad `TextField`s are replaced by chips and steppers.)
- **Dictation-first** on every free-text field; typing is the fallback.
- **"As prescribed" default**: recording a protocol item is one tap; steppers appear only for
  deviations.
- **Undo everywhere** frequent actions occur (transient undo after completions); confirmation
  only for destructive deletes. Never shake-to-undo.
- A **handedness setting** mirrors control alignment.
- Pinch is never the only path to anything.

Flow specs (mockups in parentheses):

1. **Morning check-in** (`CheckIn`) — chips + pills + mic note + one done button.
2. **PT protocol intake** (`Capture`) — three equal paths into the same parser: camera (on-device
   Vision OCR → text → existing parser; nothing leaves the phone), paste/share-sheet, dictation.
3. **Parse review** (`ParseReview`) — parsed items as cards; ambiguity = tap-to-choose candidate
   chips; unknown movement = one-tap "add to your movements"; cadence = preset chips; restriction
   check shown before save; swipe-left drops a row; save generates docket entries.
4. **Record actual** (`RecordActual`) — giant "as prescribed" button; steppers for sets/reps;
   pain chip row; undo note; used for both protocol items and workout movements.
5. **Ad-hoc pain** (`PainLog`) — entry via Home Screen quick action (long-press app icon) or
   long-press a part in Body: part chip → 0–10 chip → optional dictated note.
6. **Outside the app** (`OutsideApp`) — interactive Home/Lock Screen widget with tap-to-complete;
   notification actions (Done / Later); App Intents for voice logging ("band work done" →
   logged as prescribed → optional pain follow-up). All complete docket items without opening
   the app.

Implementation priority: camera/OCR intake + tap-chip review → protocol recurrence + docket
generation → one-tap "as prescribed" logging → widget/notification completion → quick-action
pain logging → "bring to PT" export summary.

## Visual system — "field journal"

A printed field journal: paper, a red margin rule, and hand-drawn marks carry the notebook
character; the type is a readable serif. Wry copy is part of the design system (short, casual,
self-deprecating; e.g. "Arm's still curing. Legs are fair game.", "association, not causation.
as always.").

### Type

- **Body/UI serif: Literata** (Google Fonts, OFL — bundle it), weights 400/500/600/700 plus
  italics. SwiftUI fallback: system serif (`.fontDesign(.serif)` / New York) preserves the
  intent if bundling is deferred. Support Dynamic Type; the px sizes below are the reference
  scale at default size.
- **Accent handwriting: Caveat 700** — *only* for the Today verdict ("Send it.") and its ghost in
  the check-in background. Nothing else is handwritten.
- Voice/aside lines are Literata *italic*; primary buttons are Literata 600 at ~20px equivalent.

### Color tokens (light mode; from the mockups, oklch)

| Token | Value | Use |
| --- | --- | --- |
| paper | `oklch(0.97 0.014 85)` | screen background |
| dot grid | `oklch(0.5 0.03 80 / 0.16)` on 18px grid | paper texture |
| ink | `oklch(0.32 0.07 255)` | primary text, drawn strokes, filled buttons/chips |
| red pen | `oklch(0.55 0.16 25)` | margin rule (35% alpha), voice lines, selected pain chips, PT tags, alerts |
| green check | `oklch(0.55 0.13 150)` | drawn check strokes, positive trends |
| amber (curing) | `oklch(0.7 0.13 80)` / text `oklch(0.6 0.12 70)` | tissue/healing state |
| tape | `oklch(0.88 0.06 95 / 0.75)` | taped-card and sticky-note accents |

Dark mode is not yet designed; derive by keeping hue/chroma and inverting lightness roles, or
defer behind a light-only v1.

### Component language

- **Chip scale** — bordered squares (~26×34–40px, 1.5px ink border at 40% alpha); selected chip
  fills (ink for neutral scales, red pen for pain) with paper-colored text.
- **Pill chip** — rounded-full bordered; selected fills ink.
- **Drawn checkbox** — slightly irregular square stroke; completion draws a green check stroke
  and strikes the label at 55% alpha ink.
- **Squiggle divider** — a shallow hand-drawn wave stroke at 25% ink, replacing hairlines.
- **Drawn active-tab box** — the nav marks the active zone with a hand-drawn rounded box stroke;
  inactive labels at 55% ink; a small gear icon at the trailing edge.
- **Taped card** — paper card with a tape rectangle; reserved for the protocol ("the sheet from
  your PT") and sticky-note tips. Physical objects may tilt 1.5–2°; text never tilts.
- **Bottom sheet** — paper with dot grid, 2px ink top border, 22px top radius, grabber, dimmed
  ink-tinted scrim (12%).

### Motion (from the metaphor exploration; apply sparingly)

- Sheet presentations and zone transitions use standard iOS transitions; no lateral push between
  time states — the mental model is one place, three views.
- Completion: haptic + drawn-check stroke animation + transient undo.
- Optional signature detail (from the Atlas exploration): any ambient "breathing" element pulses
  at the user's measured respiratory rate.

## Mapping to existing code

- `AppTabView` → three zones + gear (Settings content unchanged).
- `TodayView` → TodayZone: keep readiness/check-in/override logic; replace metric cards with the
  docket; move sync/backend status into Settings or a compact status line.
- `TrainingView`/`WorkoutPlanEditorView` → Work: add the protocol entity + recurrence + docket
  generation; keep parser, review semantics, movement library, restriction evaluation.
- `MorningCheckInView` → chip-based sheet (same fields: pain at rest / with movement, stiffness,
  swelling, weakness, illness, energy, motivation, notes).
- `WorkoutCompletionView` → RecordActual pattern: "as prescribed" default; replace number-pad
  text fields with steppers/chips.
- `TrendsView` → Body: reorganize existing trend/weekly-review data by part; add part timelines
  and the pain-event stream.
- New targets: widget extension (interactive), notification actions, App Intents, Home Screen
  quick action, Vision OCR intake, share extension.

## Design artifacts

- Mockup sources: [`design/mockups`](design/mockups) — one self-contained HTML file per screen
  (light DOM + inline styles; open in any browser at 390×844).
- Live canvas (all exploration pages, editable): the "whoops Design Lab" artifact in the
  design session — ask the design owner for the link, or export PNGs from it.
- Earlier explorations (metaphors, alternate directions) are retained on the canvas only and are
  not part of this specification.
