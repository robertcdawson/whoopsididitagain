<p align="center">
  <img src="logo.jpg" alt="whoopsididitagain" width="320">
</p>

<h1 align="center">whoopsididitagain</h1>

<p align="center">
  A personal, single-user app built on the <a href="https://developer.whoop.com/">WHOOP API</a>.
  <br>
  <sub>Oops, I did it again — I pulled my own recovery score at 6am and let it ruin my morning.</sub>
</p>

<p align="center">
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="PRIVACY.md"><img src="https://img.shields.io/badge/privacy-policy-green.svg" alt="Privacy Policy"></a>
</p>

---

## What this is

A hobby project that talks to the WHOOP API on behalf of exactly one WHOOP
member — me. It is not a product, it has no users to sign up, and it is not
affiliated with WHOOP, Inc.

It exists so I can pull my own sleep, recovery, strain, and workout data and do
something more interesting with it than scroll the official app.

## Status

✅ **Milestone 6 Personal Experiment Laboratory.** The Train tab accepts raw
CrossFit, weightlifting, and conditioning text; produces a schema-validated,
editable plan; reports unresolved ambiguity instead of inventing details; and
checks canonical movement demands against active restrictions. Candidate
substitutions explain the stimulus they preserve and the specificity they trade
away. Planned work and actual completion are stored separately, including
session RPE, movement modifications, and pain response. The deterministic
parser works locally without an LLM.

The current phone build uses the improved built-in workout parser. Apple-model research is retained
in the repository but cannot be enabled in normal app runs while its accuracy gate remains unmet.
See [parser evaluation and rollout status](docs/APPLE_WORKOUT_PARSER.md).

The app now merges its bundled catalog with a personal, on-device movement
library. Stable facts such as names, aliases, category, equipment, supported
measurements, and restriction-demand tags are reusable; reps, load, distance,
tempo, and other prescriptions remain specific to each workout.

The Trends tab now combines normalized local history into source-specific
recovery and sleep trends, session-RPE training load, strength volume, injury
history, and descriptive pain-by-movement summaries. Its versioned weekly
review always reports sample size or insufficient data, uses association—not
causal—language, and works without an LLM. JSON and CSV sharing excludes
credentials and raw API payloads.

An off-by-default experimental feature now adds a local Personal Experiment
Laboratory. It records intervention and comparison days, resolves supported
outcomes from existing WHOOP, Apple Health, workout, and morning check-in
history, and withholds the difference until both conditions meet the configured
minimum. One daily check-in can update every active experiment. Conditions are
explicitly described as what actually happened, and each experiment visibly
uses either the same-day or following-day outcome. Excluded days remain
auditable, and every result is labeled as a descriptive association rather than
a causal or medical conclusion. Logged experiment days and whole experiments
can be permanently deleted with confirmation.

Redesign phases 1–2 are integrated with that foundation: Train also accepts PT
protocols through photo, paste, or on-device dictation and offers tap-chip review;
Today generates a daily docket from protocol recurrence, planned workouts, and
sleep wind-down. The four-tab navigation and existing experiment and workout
editing flows remain available. See [branch integration and safe Xcode update](docs/BRANCH_INTEGRATION.md).

## Architecture

- `ios/WhoopsApp` — native SwiftUI app with Today, Train, Trends, and Settings
- `backend` — TypeScript/Next.js service; the first endpoint is
  `GET /api/v1/health`
- `contracts` — versioned app/backend JSON Schema contracts
- `fixtures` — synthetic-only test data
- `docs` — product plan, architecture, decisions, and tasks

Health and training history will be stored locally on the iPhone. WHOOP OAuth
credentials will remain encrypted on the backend. Deterministic calculations
will continue to work without an LLM.

## Development setup

Requirements:

- Xcode 26 or a compatible toolchain with an iOS 18+ simulator
- Native ARM64 Node.js 24 (selected automatically by `.nvmrc` when using `nvm`)
- npm 11+

Install and run the backend:

```sh
cd backend
cp .env.example .env.local
nvm use
npm install
npm run dev
```

The health endpoint does not require credentials. WHOOP connection routes do.
Open
`ios/WhoopsApp/WhoopsApp.xcodeproj` in Xcode and run the `WhoopsApp` scheme.
Installed builds call `https://whoopsididitagain-backend.vercel.app`. Local development can
override that endpoint with the `WHOOPS_BACKEND_URL` scheme environment variable.

On the iPhone, open Settings in the app and choose **Allow Apple Health read
access**. Every requested category is optional; importing continues for any
categories you allow. After the system permission sheet is completed, the app
shows **Connected**; that means the read-only connection was set up, not that
Apple disclosed permission for every category. The integration never writes to
Apple Health. The initial import covers the latest 180 days and commits anchored
results in bounded pages so a large Apple Health store is never materialized in
one in-memory result set.

For daily planning, review the seeded restrictions and sleep schedule in the
app's Settings tab, then complete the morning check-in on Today. The resulting
recommendation is deterministic and works without an LLM. You can override and
annotate it without erasing the calculated recommendation.

In Train, paste a workout and choose **Parse and review**. Parser notes remain
visible for context rather than becoming a second checklist. Review the workout
details, edit only the movements that need changes, check restriction conflicts,
then confirm the review once when saving the plan. After training, choose
**Record actual** and change the copied values to what you performed before
recording session RPE and pain. Use **Enter manually** whenever the parser cannot
interpret the source text.

Tap a saved planned-workout card to inspect its complete structure, prescriptions, recovery,
restriction evaluation, and original source. Edit and Record actual remain separate actions. Recent
completed-workout rows open the recorded session and movement values.

The deterministic parser accepts ordinary or stylized Unicode programming. Standalone headings
become workout titles, repeated explicit rests become interval structure, and heart-rate or RPE
targets remain editable context instead of appearing as manual movements.
Uniform recovery between repeated rounds or efforts stays on the work segment. Use a dedicated Rest
segment—with one required duration and no movements—when recovery differs within the workout.

Open **Your Movements** in Train to search recent and bundled movements, add or
edit personal movements, and archive entries without changing past workouts.
The library can preview and import the movement store from a WOD Lab version 1
JSON export. Reimporting the same export matches existing movements instead of
creating duplicates; WOD Lab workout prescriptions and coaching notes are not
imported.

Run all repository checks after installing backend dependencies:

```sh
./scripts/check.sh
```

## WHOOP API access

The App uses WHOOP's OAuth 2.0 authorization code flow. Credentials come from
the [WHOOP Developer Dashboard](https://developer.whoop.com/), which is free to
use.

### Scopes

| Scope | Grants |
| --- | --- |
| `read:profile` | Name, WHOOP user ID, account email |
| `read:body_measurement` | Height, weight, max heart rate |
| `read:cycles` | Physiological cycles, day strain, average heart rate |
| `read:recovery` | Recovery score, resting heart rate, HRV |
| `read:sleep` | Sleep sessions, stages, performance, respiratory rate |
| `read:workout` | Workouts, sport, strain, HR zones, calories |
| `offline` | Refresh token, for syncing without re-authorizing |

> **Note:** WHOOP's scope names are inconsistently pluralized — `read:cycles`
> is plural, `read:workout` and `read:sleep` are singular. Copy them exactly.

All access is read-only. The App never writes to a WHOOP account.

### Registering the app

In the WHOOP Developer Dashboard you'll need:

- **App Name** — `whoopsididitagain`
- **Contact Email** — your email
- **Privacy Policy URL** — see below
- **Redirect URI(s)** — for Simulator development, use
  `http://localhost:3000/api/v1/auth/whoop/callback`; for a physical iPhone,
  use the same path on your reachable HTTPS backend

Apps in development are capped at **10 WHOOP members**, which is nine more than
this one needs — so no approval submission is required here.

### Privacy Policy URL

Paste this into the dashboard's Privacy Policy field:

```
https://robertcdawson.github.io/whoopsididitagain/privacy/
```

That page is published by GitHub Pages from [`PRIVACY.md`](PRIVACY.md) in this
repo, so the file is the single source of truth — edit it, push, and the
published page updates. The raw file view at
`https://github.com/robertcdawson/whoopsididitagain/blob/main/PRIVACY.md` also
remains valid if you ever need it.

### Credentials

The Client ID and Client Secret from the dashboard belong in a local `.env`
file, which is gitignored and must never be committed:

```sh
WHOOP_CLIENT_ID=your_client_id
WHOOP_CLIENT_SECRET=your_client_secret
WHOOP_REDIRECT_URI=http://localhost:3000/api/v1/auth/whoop/callback
# Optional in development; omit to use the ephemeral in-memory store
DATABASE_URL=postgresql://user:password@localhost:5432/whoops
OAUTH_ENCRYPTION_KEY=<output of: openssl rand -base64 32>
APP_SESSION_SIGNING_KEY=<output of: openssl rand -base64 32>
APP_DEEP_LINK=whoops://oauth/callback
```

Run `npm run db:migrate` before production or any persistent local-backend
testing. Without `DATABASE_URL`, non-production mode intentionally uses an
in-memory credential store that is cleared whenever the backend restarts.

## Documents

- [Privacy Policy](PRIVACY.md) — required by the WHOOP Developer Dashboard
- [License](LICENSE.md) — MIT
- [Product plan](docs/PROJECT_PLAN.md) — product source of truth
- [Architecture](docs/ARCHITECTURE.md) — implemented system boundaries
- [Decisions](docs/DECISIONS.md) — architecture decision log
- [Tasks](docs/TASKS.md) — milestone execution status

## Disclaimer

Independent personal project. Not created, endorsed, or supported by WHOOP,
Inc. "WHOOP" is a trademark of its respective owner. Use of the API is subject
to the [WHOOP API Terms of Use](https://developer.whoop.com/api-terms-of-use/).

Nothing here is medical advice. It's a chart of how badly I slept.

## License

[MIT](LICENSE.md) © 2026 Robert Dawson
