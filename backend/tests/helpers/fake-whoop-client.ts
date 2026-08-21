import type { WhoopResourceType } from "@/src/db/auth-store";
import type {
  WhoopClient,
  WhoopCollectionPage,
  WhoopProfile,
  WhoopTokenResponse,
} from "@/src/whoop/whoop-client";

export class FakeWhoopClient implements WhoopClient {
  exchangeResponse: WhoopTokenResponse = {
    access_token: "access-initial",
    refresh_token: "refresh-initial",
    expires_in: 3_600,
    scope: "offline read:profile read:cycles read:recovery read:sleep read:workout",
    token_type: "bearer",
  };
  refreshResponse: WhoopTokenResponse = {
    access_token: "access-refreshed",
    refresh_token: "refresh-refreshed",
    expires_in: 3_600,
    scope: "offline read:profile read:cycles read:recovery read:sleep read:workout",
    token_type: "bearer",
  };
  profileResponse: WhoopProfile = {
    user_id: 10129,
    email: "synthetic@example.invalid",
    first_name: "Synthetic",
    last_name: "Athlete",
  };
  refreshCalls = 0;
  revokedTokens: string[] = [];
  revokeError: Error | null = null;
  collectionRequests: Array<{
    resourceType: WhoopResourceType;
    nextToken?: string;
    start: Date;
    end: Date;
  }> = [];
  collectionImplementation: (
    resourceType: WhoopResourceType,
    nextToken?: string,
  ) => WhoopCollectionPage = (resourceType, nextToken) => ({
    records: nextToken
      ? [{ id: `${resourceType}-2`, updated_at: "2026-08-15T02:00:00.000Z" }]
      : [{ id: `${resourceType}-1`, updated_at: "2026-08-15T01:00:00.000Z" }],
    next_token: nextToken ? null : "page-2",
  });

  async exchangeAuthorizationCode(): Promise<WhoopTokenResponse> {
    return this.exchangeResponse;
  }

  async refreshAccessToken(): Promise<WhoopTokenResponse> {
    this.refreshCalls += 1;
    await new Promise((resolve) => setTimeout(resolve, 5));
    return this.refreshResponse;
  }

  async profile(): Promise<WhoopProfile> {
    return this.profileResponse;
  }

  async collectionPage(
    resourceType: WhoopResourceType,
    _accessToken: string,
    start: Date,
    end: Date,
    nextToken?: string,
  ): Promise<WhoopCollectionPage> {
    this.collectionRequests.push({ resourceType, nextToken, start, end });
    return this.collectionImplementation(resourceType, nextToken);
  }

  async revoke(accessToken: string): Promise<void> {
    if (this.revokeError) throw this.revokeError;
    this.revokedTokens.push(accessToken);
  }
}
