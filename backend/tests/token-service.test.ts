import { describe, expect, it } from "vitest";

import { InMemoryAuthStore } from "@/src/db/in-memory-auth-store";
import { encryptSecret } from "@/src/security/encryption";
import { WhoopTokenService } from "@/src/whoop/token-service";
import { FakeWhoopClient } from "@/tests/helpers/fake-whoop-client";
import { testConfig } from "@/tests/helpers/test-config";

const installationId = "123e4567-e89b-42d3-a456-426614174000";

describe("WhoopTokenService", () => {
  it("serializes concurrent rotating refreshes", async () => {
    const store = new InMemoryAuthStore();
    const whoop = new FakeWhoopClient();
    const config = testConfig();
    await store.ensureInstallation(installationId);
    await store.saveCredential({
      installationId,
      whoopUserId: "10129",
      encryptedAccessToken: encryptSecret("expired", config.oauthEncryptionKey),
      encryptedRefreshToken: encryptSecret("refresh-old", config.oauthEncryptionKey),
      accessExpiresAt: new Date("2026-08-15T11:00:00.000Z"),
      scope: "offline",
      tokenVersion: 1,
      updatedAt: new Date("2026-08-15T11:00:00.000Z"),
    });
    const service = new WhoopTokenService(store, whoop, config);
    const now = new Date("2026-08-15T12:00:00.000Z");

    const values = await Promise.all([
      service.accessToken(installationId, now),
      service.accessToken(installationId, now),
      service.accessToken(installationId, now),
    ]);

    expect(values).toEqual(["access-refreshed", "access-refreshed", "access-refreshed"]);
    expect(whoop.refreshCalls).toBe(1);
    expect((await store.getCredential(installationId))?.tokenVersion).toBe(2);
  });

  it("deletes credentials and revokes app sessions even if WHOOP revocation fails", async () => {
    const store = new InMemoryAuthStore();
    const whoop = new FakeWhoopClient();
    const config = testConfig();
    await store.ensureInstallation(installationId);
    await store.saveCredential({
      installationId,
      whoopUserId: "10129",
      encryptedAccessToken: encryptSecret("valid-access", config.oauthEncryptionKey),
      encryptedRefreshToken: encryptSecret("valid-refresh", config.oauthEncryptionKey),
      accessExpiresAt: new Date("2026-08-15T14:00:00.000Z"),
      scope: "offline",
      tokenVersion: 1,
      updatedAt: new Date("2026-08-15T12:00:00.000Z"),
    });
    whoop.revokeError = new Error("synthetic revoke failure");

    await new WhoopTokenService(store, whoop, config).disconnect(installationId);

    expect(await store.getCredential(installationId)).toBeNull();
    expect(await store.sessionGeneration(installationId)).toBe(1);
  });
});
