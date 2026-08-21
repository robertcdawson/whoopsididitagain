import type { AppConfig } from "@/src/config/config";
import type { AuthStore } from "@/src/db/auth-store";
import { AppError } from "@/src/http/app-error";
import { encryptSecret } from "@/src/security/encryption";
import { hashOpaqueValue, randomOAuthState, randomToken } from "@/src/security/opaque-values";
import { signSessionToken, verifySessionToken } from "@/src/security/session-token";
import type { WhoopClient } from "@/src/whoop/whoop-client";

const scopes = [
  "offline",
  "read:profile",
  "read:cycles",
  "read:recovery",
  "read:sleep",
  "read:workout",
];

export interface AppSessionPair {
  accessToken: string;
  refreshToken: string;
  accessExpiresIn: number;
}

export class OAuthService {
  constructor(
    private readonly store: AuthStore,
    private readonly whoop: WhoopClient,
    private readonly config: AppConfig,
  ) {}

  async start(installationId: string, now = new Date()): Promise<{ authorizationUrl: string }> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(installationId)) {
      throw new AppError("invalid_installation_id", "The app installation identifier is invalid.", 400);
    }
    await this.store.ensureInstallation(installationId);
    const state = randomOAuthState();
    await this.store.createOAuthTransaction(hashOpaqueValue(state), {
      installationId,
      expiresAt: new Date(now.getTime() + 10 * 60 * 1_000),
    });

    const url = new URL("https://api.prod.whoop.com/oauth/oauth2/auth");
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", this.config.whoopClientId);
    url.searchParams.set("redirect_uri", this.config.whoopRedirectUri);
    url.searchParams.set("scope", scopes.join(" "));
    url.searchParams.set("state", state);
    return { authorizationUrl: url.toString() };
  }

  async callback(state: string, authorizationCode: string, now = new Date()): Promise<string> {
    const transaction = await this.store.consumeOAuthTransaction(hashOpaqueValue(state), now);
    if (!transaction) {
      throw new AppError("invalid_oauth_state", "The WHOOP authorization request expired or was already used.", 400);
    }

    const token = await this.whoop.exchangeAuthorizationCode(authorizationCode);
    const profile = await this.whoop.profile(token.access_token);
    await this.store.saveCredential({
      installationId: transaction.installationId,
      whoopUserId: String(profile.user_id),
      encryptedAccessToken: encryptSecret(token.access_token, this.config.oauthEncryptionKey),
      encryptedRefreshToken: encryptSecret(token.refresh_token, this.config.oauthEncryptionKey),
      accessExpiresAt: new Date(now.getTime() + token.expires_in * 1_000),
      scope: token.scope,
      tokenVersion: 1,
      updatedAt: now,
    });

    const code = randomToken();
    await this.store.createExchangeCode(hashOpaqueValue(code), {
      installationId: transaction.installationId,
      expiresAt: new Date(now.getTime() + 2 * 60 * 1_000),
    });
    const redirect = new URL(this.config.appDeepLink);
    redirect.searchParams.set("code", code);
    return redirect.toString();
  }

  async exchange(oneTimeCode: string, now = new Date()): Promise<AppSessionPair> {
    const code = await this.store.consumeExchangeCode(hashOpaqueValue(oneTimeCode), now);
    if (!code) {
      throw new AppError("invalid_exchange_code", "The authorization code expired or was already used.", 400);
    }
    return this.issueSession(code.installationId, now);
  }

  async refresh(refreshToken: string, now = new Date()): Promise<AppSessionPair> {
    const claims = verifySessionToken(
      refreshToken,
      "refresh",
      this.config.appSessionSigningKey,
      now,
    );
    await this.assertGeneration(claims.sub, claims.gen);
    return this.issueSession(claims.sub, now);
  }

  async authenticate(request: Request, now = new Date()): Promise<string> {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      throw new AppError("missing_session", "An app session is required.", 401);
    }
    const claims = verifySessionToken(
      authorization.slice("Bearer ".length),
      "access",
      this.config.appSessionSigningKey,
      now,
    );
    await this.assertGeneration(claims.sub, claims.gen);
    return claims.sub;
  }

  private async issueSession(installationId: string, now: Date): Promise<AppSessionPair> {
    const generation = await this.store.sessionGeneration(installationId);
    if (generation === null) {
      throw new AppError("unknown_installation", "The app installation is not registered.", 401);
    }
    return {
      accessToken: signSessionToken(
        installationId,
        "access",
        generation,
        this.config.appSessionSigningKey,
        now,
      ),
      refreshToken: signSessionToken(
        installationId,
        "refresh",
        generation,
        this.config.appSessionSigningKey,
        now,
      ),
      accessExpiresIn: 15 * 60,
    };
  }

  private async assertGeneration(installationId: string, expected: number): Promise<void> {
    const generation = await this.store.sessionGeneration(installationId);
    if (generation === null || generation !== expected) {
      throw new AppError("revoked_session", "The app session has been revoked.", 401);
    }
  }
}
