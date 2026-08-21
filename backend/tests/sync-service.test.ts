import { describe, expect, it } from "vitest";

import { InMemoryAuthStore } from "@/src/db/in-memory-auth-store";
import { encryptSecret } from "@/src/security/encryption";
import { WhoopSyncService } from "@/src/whoop/sync-service";
import { WhoopTokenService } from "@/src/whoop/token-service";
import { FakeWhoopClient } from "@/tests/helpers/fake-whoop-client";
import { testConfig } from "@/tests/helpers/test-config";

const installationId = "123e4567-e89b-42d3-a456-426614174000";

describe("WhoopSyncService", () => {
  it("imports 180 days and follows every continuation token", async () => {
    const store = new InMemoryAuthStore();
    const whoop = new FakeWhoopClient();
    const config = testConfig();
    const now = new Date("2026-08-15T12:00:00.000Z");
    await store.ensureInstallation(installationId);
    await store.saveCredential({
      installationId,
      whoopUserId: "10129",
      encryptedAccessToken: encryptSecret("valid-access", config.oauthEncryptionKey),
      encryptedRefreshToken: encryptSecret("valid-refresh", config.oauthEncryptionKey),
      accessExpiresAt: new Date("2026-08-15T14:00:00.000Z"),
      scope: "offline",
      tokenVersion: 1,
      updatedAt: now,
    });
    const tokenService = new WhoopTokenService(store, whoop, config);
    const service = new WhoopSyncService(store, whoop, tokenService);

    const result = await service.synchronize(installationId, now);

    expect(result.mode).toBe("initial");
    expect(result.resources).toHaveLength(4);
    expect(result.resources.every((resource) => resource.records.length === 2)).toBe(true);
    expect(result.resources.every((resource) => resource.pageCount === 2)).toBe(true);
    expect(whoop.collectionRequests).toHaveLength(8);
    const firstWindowDays =
      (now.getTime() - whoop.collectionRequests[0]!.start.getTime()) / 86_400_000;
    expect(firstWindowDays).toBe(180);

    const incremental = await service.synchronize(
      installationId,
      new Date("2026-08-16T12:00:00.000Z"),
    );
    expect(incremental.mode).toBe("incremental");
  });

  it("does not advance any checkpoint when one resource fails", async () => {
    const store = new InMemoryAuthStore();
    const whoop = new FakeWhoopClient();
    const config = testConfig();
    const now = new Date("2026-08-15T12:00:00.000Z");
    await store.ensureInstallation(installationId);
    await store.saveCredential({
      installationId,
      whoopUserId: "10129",
      encryptedAccessToken: encryptSecret("valid-access", config.oauthEncryptionKey),
      encryptedRefreshToken: encryptSecret("valid-refresh", config.oauthEncryptionKey),
      accessExpiresAt: new Date("2026-08-15T14:00:00.000Z"),
      scope: "offline",
      tokenVersion: 1,
      updatedAt: now,
    });
    whoop.collectionImplementation = (resourceType) => {
      if (resourceType === "sleep") throw new Error("synthetic upstream failure");
      return { records: [], next_token: null };
    };
    const service = new WhoopSyncService(
      store,
      whoop,
      new WhoopTokenService(store, whoop, config),
    );

    await expect(service.synchronize(installationId, now)).rejects.toThrow(
      "synthetic upstream failure",
    );
    await Promise.all(
      (["cycle", "recovery", "sleep", "workout"] as const).map(async (resourceType) => {
        expect(await store.getCheckpoint(installationId, resourceType)).toBeNull();
      }),
    );
  });
});
