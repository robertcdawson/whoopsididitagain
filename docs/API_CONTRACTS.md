# API Contracts

All app-facing routes are versioned below `/api/v1`, disable caching, accept or generate an
`x-request-id`, and use the shared success/error envelopes in `contracts`.

## Milestone 1 routes

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/v1/health` | Unauthenticated backend health |
| `POST` | `/api/v1/auth/whoop/start` | Create an OAuth transaction for an installation UUID |
| `GET` | `/api/v1/auth/whoop/callback` | Verify state, exchange the WHOOP code, redirect to app |
| `POST` | `/api/v1/auth/session/exchange` | Consume the one-time deep-link code |
| `POST` | `/api/v1/auth/session/refresh` | Issue a replacement app session |
| `GET` | `/api/v1/whoop/status` | Return connection state; app-session bearer required |
| `GET` | `/api/v1/whoop/sync` | Return paginated initial or incremental WHOOP records |
| `POST` | `/api/v1/auth/whoop/disconnect` | Revoke WHOOP access and invalidate the app session |

WHOOP tokens are never included in any app-facing response. `AppSessionPair.accessToken` and
`refreshToken` authenticate only this app to this backend; they are not WHOOP credentials.

See `contracts/whoop-auth.schema.json`, `contracts/sync-response.schema.json`, and the Swift models
in `ios/WhoopsApp/WhoopsApp/Domain/Models` for the mirrored v1 shapes.
