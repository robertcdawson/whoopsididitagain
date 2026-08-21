import postgres, { type Sql } from "postgres";

import type {
  AuthStore,
  ExchangeCode,
  OAuthTransaction,
  StoredWhoopCredential,
  SyncCheckpointRecord,
  WhoopResourceType,
} from "@/src/db/auth-store";

interface CredentialRow {
  installation_id: string;
  whoop_user_id: string;
  encrypted_access_token: string;
  encrypted_refresh_token: string;
  access_expires_at: Date;
  scope: string;
  token_version: number;
  updated_at: Date;
}

interface CheckpointRow {
  installation_id: string;
  resource_type: WhoopResourceType;
  last_successful_sync_at: Date;
  last_source_updated_at: Date | null;
}

export function createPostgresClient(databaseUrl: string): Sql {
  return postgres(databaseUrl, {
    max: 4,
    idle_timeout: 20,
    connect_timeout: 10,
    transform: { undefined: null },
  });
}

export class PostgresAuthStore implements AuthStore {
  constructor(private readonly sql: Sql) {}

  async ensureInstallation(installationId: string): Promise<void> {
    await this.sql`
      insert into app_installations (id)
      values (${installationId}::uuid)
      on conflict (id) do nothing
    `;
  }

  async sessionGeneration(installationId: string): Promise<number | null> {
    const rows = await this.sql<{ session_generation: number }[]>`
      select session_generation
      from app_installations
      where id = ${installationId}::uuid
    `;
    return rows[0]?.session_generation ?? null;
  }

  async incrementSessionGeneration(installationId: string): Promise<void> {
    await this.sql`
      update app_installations
      set session_generation = session_generation + 1
      where id = ${installationId}::uuid
    `;
  }

  async createOAuthTransaction(stateHash: string, transaction: OAuthTransaction): Promise<void> {
    await this.sql`
      insert into oauth_transactions (state_hash, installation_id, expires_at)
      values (${stateHash}, ${transaction.installationId}::uuid, ${transaction.expiresAt})
    `;
  }

  async consumeOAuthTransaction(
    stateHash: string,
    now: Date,
  ): Promise<OAuthTransaction | null> {
    const rows = await this.sql<{ installation_id: string; expires_at: Date }[]>`
      delete from oauth_transactions
      where state_hash = ${stateHash}
      returning installation_id::text, expires_at
    `;
    const row = rows[0];
    return row && row.expires_at > now
      ? { installationId: row.installation_id, expiresAt: row.expires_at }
      : null;
  }

  async createExchangeCode(codeHash: string, code: ExchangeCode): Promise<void> {
    await this.sql`
      insert into oauth_exchange_codes (code_hash, installation_id, expires_at)
      values (${codeHash}, ${code.installationId}::uuid, ${code.expiresAt})
    `;
  }

  async consumeExchangeCode(codeHash: string, now: Date): Promise<ExchangeCode | null> {
    const rows = await this.sql<{ installation_id: string; expires_at: Date }[]>`
      delete from oauth_exchange_codes
      where code_hash = ${codeHash}
      returning installation_id::text, expires_at
    `;
    const row = rows[0];
    return row && row.expires_at > now
      ? { installationId: row.installation_id, expiresAt: row.expires_at }
      : null;
  }

  async getCredential(installationId: string): Promise<StoredWhoopCredential | null> {
    const rows = await this.sql<CredentialRow[]>`
      select
        installation_id::text,
        whoop_user_id,
        encrypted_access_token,
        encrypted_refresh_token,
        access_expires_at,
        scope,
        token_version,
        updated_at
      from whoop_credentials
      where installation_id = ${installationId}::uuid
    `;
    const row = rows[0];
    return row ? this.mapCredential(row) : null;
  }

  async saveCredential(credential: StoredWhoopCredential): Promise<void> {
    await this.sql`
      insert into whoop_credentials (
        installation_id,
        whoop_user_id,
        encrypted_access_token,
        encrypted_refresh_token,
        access_expires_at,
        scope,
        token_version,
        updated_at
      ) values (
        ${credential.installationId}::uuid,
        ${credential.whoopUserId},
        ${credential.encryptedAccessToken},
        ${credential.encryptedRefreshToken},
        ${credential.accessExpiresAt},
        ${credential.scope},
        ${credential.tokenVersion},
        ${credential.updatedAt}
      )
      on conflict (installation_id) do update set
        whoop_user_id = excluded.whoop_user_id,
        encrypted_access_token = excluded.encrypted_access_token,
        encrypted_refresh_token = excluded.encrypted_refresh_token,
        access_expires_at = excluded.access_expires_at,
        scope = excluded.scope,
        token_version = excluded.token_version,
        updated_at = excluded.updated_at
    `;
  }

  async deleteCredential(installationId: string): Promise<void> {
    await this.sql.begin(async (transaction) => {
      await transaction`
        delete from sync_checkpoints where installation_id = ${installationId}::uuid
      `;
      await transaction`
        delete from whoop_credentials where installation_id = ${installationId}::uuid
      `;
    });
  }

  async getCheckpoint(
    installationId: string,
    resourceType: WhoopResourceType,
  ): Promise<SyncCheckpointRecord | null> {
    const rows = await this.sql<CheckpointRow[]>`
      select
        installation_id::text,
        resource_type,
        last_successful_sync_at,
        last_source_updated_at
      from sync_checkpoints
      where installation_id = ${installationId}::uuid
        and resource_type = ${resourceType}
    `;
    const row = rows[0];
    return row
      ? {
          installationId: row.installation_id,
          resourceType: row.resource_type,
          lastSuccessfulSyncAt: row.last_successful_sync_at,
          lastSourceUpdatedAt: row.last_source_updated_at,
        }
      : null;
  }

  async saveCheckpoint(checkpoint: SyncCheckpointRecord): Promise<void> {
    await this.sql`
      insert into sync_checkpoints (
        installation_id,
        resource_type,
        last_successful_sync_at,
        last_source_updated_at
      ) values (
        ${checkpoint.installationId}::uuid,
        ${checkpoint.resourceType},
        ${checkpoint.lastSuccessfulSyncAt},
        ${checkpoint.lastSourceUpdatedAt}
      )
      on conflict (installation_id, resource_type) do update set
        last_successful_sync_at = excluded.last_successful_sync_at,
        last_source_updated_at = excluded.last_source_updated_at
    `;
  }

  async withInstallationLock<T>(
    installationId: string,
    operation: (store: AuthStore) => Promise<T>,
  ): Promise<T> {
    return this.sql.begin(async (transaction) => {
      await transaction`select pg_advisory_xact_lock(hashtextextended(${installationId}, 0))`;
      return operation(new PostgresAuthStore(transaction as unknown as Sql));
    }) as Promise<T>;
  }

  private mapCredential(row: CredentialRow): StoredWhoopCredential {
    return {
      installationId: row.installation_id,
      whoopUserId: row.whoop_user_id,
      encryptedAccessToken: row.encrypted_access_token,
      encryptedRefreshToken: row.encrypted_refresh_token,
      accessExpiresAt: row.access_expires_at,
      scope: row.scope,
      tokenVersion: row.token_version,
      updatedAt: row.updated_at,
    };
  }
}
