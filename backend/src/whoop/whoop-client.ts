import { AppError } from "@/src/http/app-error";
import type { WhoopResourceType } from "@/src/db/auth-store";

const whoopOrigin = "https://api.prod.whoop.com";

export interface WhoopTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  scope: string;
  token_type: string;
}

export interface WhoopProfile {
  user_id: number;
  email: string;
  first_name: string;
  last_name: string;
}

export interface WhoopCollectionPage {
  records: Record<string, unknown>[];
  next_token?: string | null;
}

export interface WhoopClient {
  exchangeAuthorizationCode(code: string): Promise<WhoopTokenResponse>;
  refreshAccessToken(refreshToken: string): Promise<WhoopTokenResponse>;
  profile(accessToken: string): Promise<WhoopProfile>;
  collectionPage(
    resourceType: WhoopResourceType,
    accessToken: string,
    start: Date,
    end: Date,
    nextToken?: string,
  ): Promise<WhoopCollectionPage>;
  revoke(accessToken: string): Promise<void>;
}

export interface WhoopClientConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  fetchImplementation?: typeof fetch;
}

export class WhoopHttpClient implements WhoopClient {
  private readonly fetchImplementation: typeof fetch;

  constructor(private readonly config: WhoopClientConfig) {
    this.fetchImplementation = config.fetchImplementation ?? fetch;
  }

  async exchangeAuthorizationCode(code: string): Promise<WhoopTokenResponse> {
    return this.requestToken(
      new URLSearchParams({
        grant_type: "authorization_code",
        code,
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        redirect_uri: this.config.redirectUri,
      }),
    );
  }

  async refreshAccessToken(refreshToken: string): Promise<WhoopTokenResponse> {
    return this.requestToken(
      new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        scope: "offline",
      }),
    );
  }

  async profile(accessToken: string): Promise<WhoopProfile> {
    return this.requestJson<WhoopProfile>("/developer/v2/user/profile/basic", accessToken);
  }

  async collectionPage(
    resourceType: WhoopResourceType,
    accessToken: string,
    start: Date,
    end: Date,
    nextToken?: string,
  ): Promise<WhoopCollectionPage> {
    const paths: Record<WhoopResourceType, string> = {
      cycle: "/developer/v2/cycle",
      recovery: "/developer/v2/recovery",
      sleep: "/developer/v2/activity/sleep",
      workout: "/developer/v2/activity/workout",
    };
    const url = new URL(paths[resourceType], whoopOrigin);
    url.searchParams.set("limit", "25");
    url.searchParams.set("start", start.toISOString());
    url.searchParams.set("end", end.toISOString());
    if (nextToken) {
      url.searchParams.set("nextToken", nextToken);
    }
    return this.requestJson<WhoopCollectionPage>(url, accessToken);
  }

  async revoke(accessToken: string): Promise<void> {
    const response = await this.fetchImplementation(
      new URL("/developer/v2/user/access", whoopOrigin),
      {
        method: "DELETE",
        headers: { authorization: `Bearer ${accessToken}` },
        cache: "no-store",
      },
    );
    if (!response.ok && response.status !== 401) {
      throw await this.responseError(response, "whoop_revoke_failed");
    }
  }

  private async requestToken(body: URLSearchParams): Promise<WhoopTokenResponse> {
    const response = await this.fetchImplementation(
      new URL("/oauth/oauth2/token", whoopOrigin),
      {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body,
        cache: "no-store",
      },
    );
    if (!response.ok) {
      throw await this.responseError(response, "whoop_token_exchange_failed");
    }
    const value = (await response.json()) as Partial<WhoopTokenResponse>;
    if (
      typeof value.access_token !== "string" ||
      typeof value.refresh_token !== "string" ||
      typeof value.expires_in !== "number" ||
      typeof value.scope !== "string"
    ) {
      throw new AppError(
        "invalid_whoop_response",
        "WHOOP returned an invalid token response.",
        502,
        true,
      );
    }
    return value as WhoopTokenResponse;
  }

  private async requestJson<T>(path: string | URL, accessToken: string): Promise<T> {
    const url = typeof path === "string" ? new URL(path, whoopOrigin) : path;
    const response = await this.fetchImplementation(url, {
      headers: { authorization: `Bearer ${accessToken}` },
      cache: "no-store",
    });
    if (!response.ok) {
      throw await this.responseError(response, "whoop_request_failed");
    }
    return (await response.json()) as T;
  }

  private async responseError(response: Response, code: string): Promise<AppError> {
    const body = (await response.text()).slice(0, 500);
    return new AppError(
      code,
      `WHOOP request failed with status ${response.status}.`,
      response.status === 429 ? 503 : 502,
      response.status === 429 || response.status >= 500,
      { upstreamStatus: response.status, upstreamBodyPresent: body.length > 0 },
    );
  }
}
