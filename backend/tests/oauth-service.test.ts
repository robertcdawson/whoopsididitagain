import { describe, expect, it } from "vitest";

import { OAuthService } from "@/src/auth/oauth-service";
import { InMemoryAuthStore } from "@/src/db/in-memory-auth-store";
import { testConfig } from "@/tests/helpers/test-config";
import { FakeWhoopClient } from "@/tests/helpers/fake-whoop-client";

const installationId = "123e4567-e89b-42d3-a456-426614174000";

describe("OAuthService", () => {
  it("uses one-time state and exchange codes before issuing an app session", async () => {
    const store = new InMemoryAuthStore();
    const whoop = new FakeWhoopClient();
    const service = new OAuthService(store, whoop, testConfig());
    const now = new Date("2026-08-15T12:00:00.000Z");

    const started = await service.start(installationId, now);
    const authorizationUrl = new URL(started.authorizationUrl);
    const state = authorizationUrl.searchParams.get("state");
    expect(state).toHaveLength(8);
    expect(authorizationUrl.searchParams.get("scope")).toContain("offline");

    const deepLink = new URL(await service.callback(state!, "whoop-code", now));
    const exchangeCode = deepLink.searchParams.get("code");
    expect(exchangeCode).toBeTruthy();

    const session = await service.exchange(exchangeCode!, now);
    expect(session.accessToken).not.toContain(installationId);
    expect(session.accessExpiresIn).toBe(900);
    await expect(service.exchange(exchangeCode!, now)).rejects.toThrow(/already used/i);

    const request = new Request("http://localhost/api", {
      headers: { authorization: `Bearer ${session.accessToken}` },
    });
    await expect(service.authenticate(request, now)).resolves.toBe(installationId);
  });
});
