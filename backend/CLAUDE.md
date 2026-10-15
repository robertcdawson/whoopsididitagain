@AGENTS.md

# Project knowledge — backend

Append here when a task fails and is then fixed, phrased so a future session does not repeat the
mistake. The root `CLAUDE.md` covers the repo as a whole and the iOS app.

## Deployment: main auto-deploys, migrations do not

The Vercel project `whoopsididitagain-backend` is linked to this GitHub repo with Root Directory
`backend` and production branch `main`. Every merge to `main` that touches `backend/` builds and
promotes to production on its own. Vercel skips the build when nothing under `backend/` changed,
so iOS-only merges do not redeploy the service.

Migrations are **not** automated. They live in `backend/migrations/` and run by hand with
`npm run db:migrate` against the Neon PostgreSQL database linked to the Vercel project. Any PR
that adds a migration must have it applied to production **before the PR merges**; otherwise the
auto-deployed code runs ahead of the schema. Never put a database URL or key in a PR, comment, or
this file.

Preview deployments build on every PR but cannot complete WHOOP OAuth: the callback URI is
registered only for the production domain. A green preview proves the service builds and starts,
nothing more.
