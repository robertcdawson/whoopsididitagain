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

🚧 **Early scaffolding.** The repository currently contains project
documentation and licensing only. Implementation, and therefore the tech stack,
is still to be decided — this README will grow a real setup section once there
is something to set up.

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
- **Redirect URI(s)** — at least one is required (e.g. `http://localhost:8080/callback`
  during development)

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
WHOOP_REDIRECT_URI=http://localhost:8080/callback
```

## Documents

- [Privacy Policy](PRIVACY.md) — required by the WHOOP Developer Dashboard
- [License](LICENSE.md) — MIT

## Disclaimer

Independent personal project. Not created, endorsed, or supported by WHOOP,
Inc. "WHOOP" is a trademark of its respective owner. Use of the API is subject
to the [WHOOP API Terms of Use](https://developer.whoop.com/api-terms-of-use/).

Nothing here is medical advice. It's a chart of how badly I slept.

## License

[MIT](LICENSE.md) © 2026 Robert Dawson
