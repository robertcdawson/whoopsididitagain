import type { AuthStore, WhoopResourceType } from "@/src/db/auth-store";
import { AppError } from "@/src/http/app-error";
import type { WhoopClient } from "@/src/whoop/whoop-client";
import type { WhoopTokenService } from "@/src/whoop/token-service";

const resourceTypes: WhoopResourceType[] = ["cycle", "recovery", "sleep", "workout"];
const initialWindowMilliseconds = 180 * 24 * 60 * 60 * 1_000;
const incrementalOverlapMilliseconds = 48 * 60 * 60 * 1_000;

export interface SyncResourceResult {
  resourceType: WhoopResourceType;
  records: Record<string, unknown>[];
  pageCount: number;
  windowStart: string;
}

export interface WhoopSyncResult {
  mode: "initial" | "incremental";
  startedAt: string;
  completedAt: string;
  resources: SyncResourceResult[];
}

export class WhoopSyncService {
  constructor(
    private readonly store: AuthStore,
    private readonly whoop: WhoopClient,
    private readonly tokenService: WhoopTokenService,
  ) {}

  async synchronize(installationId: string, now = new Date()): Promise<WhoopSyncResult> {
    const accessToken = await this.tokenService.accessToken(installationId, now);
    const checkpoints = await Promise.all(
      resourceTypes.map((resourceType) => this.store.getCheckpoint(installationId, resourceType)),
    );
    const mode = checkpoints.every((checkpoint) => checkpoint === null) ? "initial" : "incremental";

    const fetched = await Promise.all(
      resourceTypes.map(async (resourceType, index) => {
        const checkpoint = checkpoints[index];
        const start = checkpoint
          ? new Date(checkpoint.lastSuccessfulSyncAt.getTime() - incrementalOverlapMilliseconds)
          : new Date(now.getTime() - initialWindowMilliseconds);
        const result = await this.allPages(resourceType, accessToken, start, now);
        const updatedDates = result.records
          .map((record) => record.updated_at)
          .filter((value): value is string => typeof value === "string")
          .map((value) => new Date(value))
          .filter((value) => !Number.isNaN(value.getTime()));
        const lastSourceUpdatedAt = updatedDates.length
          ? new Date(Math.max(...updatedDates.map((value) => value.getTime())))
          : checkpoint?.lastSourceUpdatedAt ?? null;
        return {
          resource: {
            resourceType,
            records: result.records,
            pageCount: result.pageCount,
            windowStart: start.toISOString(),
          },
          checkpoint: {
            installationId,
            resourceType,
            lastSuccessfulSyncAt: now,
            lastSourceUpdatedAt,
          },
        };
      }),
    );

    // A partial upstream failure must not advance any checkpoint: the app only persists
    // records after it receives the complete response.
    await Promise.all(fetched.map(({ checkpoint }) => this.store.saveCheckpoint(checkpoint)));
    const resources = fetched.map(({ resource }) => resource);

    return {
      mode,
      startedAt: now.toISOString(),
      completedAt: new Date().toISOString(),
      resources,
    };
  }

  private async allPages(
    resourceType: WhoopResourceType,
    accessToken: string,
    start: Date,
    end: Date,
  ): Promise<{ records: Record<string, unknown>[]; pageCount: number }> {
    const records: Record<string, unknown>[] = [];
    const seenTokens = new Set<string>();
    let nextToken: string | undefined;
    let pageCount = 0;

    do {
      const page = await this.whoop.collectionPage(
        resourceType,
        accessToken,
        start,
        end,
        nextToken,
      );
      if (!Array.isArray(page.records)) {
        throw new AppError("invalid_whoop_response", "WHOOP returned an invalid collection.", 502, true);
      }
      records.push(...page.records);
      pageCount += 1;
      const candidate = page.next_token || undefined;
      if (candidate && seenTokens.has(candidate)) {
        throw new AppError("whoop_pagination_loop", "WHOOP returned a repeated page token.", 502, true);
      }
      if (candidate) seenTokens.add(candidate);
      nextToken = candidate;
      if (pageCount > 1_000) {
        throw new AppError("whoop_pagination_limit", "WHOOP pagination exceeded the safety limit.", 502, true);
      }
    } while (nextToken);

    return { records, pageCount };
  }
}
