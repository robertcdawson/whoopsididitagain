import { OAuthService } from "@/src/auth/oauth-service";
import { loadAppConfig } from "@/src/config/config";
import type { AuthStore } from "@/src/db/auth-store";
import { InMemoryAuthStore } from "@/src/db/in-memory-auth-store";
import { createPostgresClient, PostgresAuthStore } from "@/src/db/postgres-auth-store";
import { WhoopHttpClient } from "@/src/whoop/whoop-client";
import { WhoopSyncService } from "@/src/whoop/sync-service";
import { WhoopTokenService } from "@/src/whoop/token-service";

declare global {
  var whoopsDevelopmentStore: InMemoryAuthStore | undefined;
  var whoopsProductionStore: AuthStore | undefined;
}

function authStore(): AuthStore {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (databaseUrl) {
    globalThis.whoopsProductionStore ??= new PostgresAuthStore(createPostgresClient(databaseUrl));
    return globalThis.whoopsProductionStore;
  }
  if (process.env.NODE_ENV === "production") {
    throw new Error("DATABASE_URL is required in production");
  }
  globalThis.whoopsDevelopmentStore ??= new InMemoryAuthStore();
  return globalThis.whoopsDevelopmentStore;
}

export function services() {
  const config = loadAppConfig();
  const store = authStore();
  const whoop = new WhoopHttpClient({
    clientId: config.whoopClientId,
    clientSecret: config.whoopClientSecret,
    redirectUri: config.whoopRedirectUri,
  });
  const oauth = new OAuthService(store, whoop, config);
  const tokens = new WhoopTokenService(store, whoop, config);
  const sync = new WhoopSyncService(store, whoop, tokens);
  return { oauth, tokens, sync };
}
