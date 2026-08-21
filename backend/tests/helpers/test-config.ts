import type { AppConfig } from "@/src/config/config";

export function testConfig(): AppConfig {
  return {
    whoopClientId: "synthetic-client",
    whoopClientSecret: "synthetic-secret",
    whoopRedirectUri: "http://localhost:3000/api/v1/auth/whoop/callback",
    appDeepLink: "whoops://oauth/callback",
    oauthEncryptionKey: Buffer.alloc(32, 7),
    appSessionSigningKey: Buffer.alloc(32, 9),
  };
}
