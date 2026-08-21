import type { AppConfig } from "@/src/config/config";
import type { AuthStore, StoredWhoopCredential } from "@/src/db/auth-store";
import { AppError } from "@/src/http/app-error";
import { decryptSecret, encryptSecret } from "@/src/security/encryption";
import type { WhoopClient } from "@/src/whoop/whoop-client";

export class WhoopTokenService {
  constructor(
    private readonly store: AuthStore,
    private readonly whoop: WhoopClient,
    private readonly config: AppConfig,
  ) {}

  async connectionStatus(installationId: string): Promise<{
    connected: boolean;
    whoopUserId: string | null;
    tokenExpiresAt: string | null;
  }> {
    const credential = await this.store.getCredential(installationId);
    return {
      connected: credential !== null,
      whoopUserId: credential?.whoopUserId ?? null,
      tokenExpiresAt: credential?.accessExpiresAt.toISOString() ?? null,
    };
  }

  async accessToken(installationId: string, now = new Date()): Promise<string> {
    return this.store.withInstallationLock(installationId, async (lockedStore) => {
      const credential = await lockedStore.getCredential(installationId);
      if (!credential) {
        throw new AppError("whoop_not_connected", "WHOOP is not connected.", 409);
      }

      if (credential.accessExpiresAt.getTime() > now.getTime() + 60_000) {
        return decryptSecret(credential.encryptedAccessToken, this.config.oauthEncryptionKey);
      }

      const refreshed = await this.whoop.refreshAccessToken(
        decryptSecret(credential.encryptedRefreshToken, this.config.oauthEncryptionKey),
      );
      const replacement: StoredWhoopCredential = {
        ...credential,
        encryptedAccessToken: encryptSecret(
          refreshed.access_token,
          this.config.oauthEncryptionKey,
        ),
        encryptedRefreshToken: encryptSecret(
          refreshed.refresh_token,
          this.config.oauthEncryptionKey,
        ),
        accessExpiresAt: new Date(now.getTime() + refreshed.expires_in * 1_000),
        scope: refreshed.scope,
        tokenVersion: credential.tokenVersion + 1,
        updatedAt: now,
      };
      await lockedStore.saveCredential(replacement);
      return refreshed.access_token;
    });
  }

  async disconnect(installationId: string): Promise<void> {
    try {
      const credential = await this.store.getCredential(installationId);
      if (!credential) return;
      try {
        const accessToken = await this.accessToken(installationId);
        await this.whoop.revoke(accessToken);
      } catch {
        // Revocation is best effort. Local credential deletion and app-session invalidation
        // must still complete if WHOOP is unavailable or the upstream token already expired.
      }
    } finally {
      await this.store.deleteCredential(installationId);
      await this.store.incrementSessionGeneration(installationId);
    }
  }
}
