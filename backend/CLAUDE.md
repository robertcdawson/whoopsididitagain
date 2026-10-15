@AGENTS.md

# Project knowledge — backend

A cumulative log for the Next.js service, in the same spirit as the root `CLAUDE.md`, which
covers the repo as a whole and the iOS app. Append to it when a task fails and is then fixed.

## Deploys: Vercel builds `backend/` from `main`

The Vercel project `whoopsididitagain-backend` is linked to this GitHub repo with Root Directory
`backend` and production branch `main`. Every merge to `main` that touches `backend/` deploys to
production on its own. Vercel skips the build when nothing under `backend/` changed, so an
iOS-only merge does not redeploy the service.

**Migrations are not automated.** They live in `backend/migrations/`, and `npm run db:migrate`
(`scripts/migrate.ts`) applies them by hand against the Neon PostgreSQL database linked to the
Vercel project. A PR that adds a file under `backend/migrations/` must have that migration applied
to production **before the PR merges**. Otherwise the auto-deployed code runs ahead of the schema.

Preview deployments are built for pull requests, but they cannot complete WHOOP OAuth: the
callback URI is registered only for the production domain. A green preview proves the service
builds and starts, nothing more.
