export type WhoopResourceType = "cycle" | "recovery" | "sleep" | "workout";

export interface OAuthTransaction {
  installationId: string;
  expiresAt: Date;
}

export interface ExchangeCode {
  installationId: string;
  expiresAt: Date;
}

export interface StoredWhoopCredential {
  installationId: string;
  whoopUserId: string;
  encryptedAccessToken: string;
  encryptedRefreshToken: string;
  accessExpiresAt: Date;
  scope: string;
  tokenVersion: number;
  updatedAt: Date;
}

export interface SyncCheckpointRecord {
  installationId: string;
  resourceType: WhoopResourceType;
  lastSuccessfulSyncAt: Date;
  lastSourceUpdatedAt: Date | null;
}

export interface AuthStore {
  ensureInstallation(installationId: string): Promise<void>;
  sessionGeneration(installationId: string): Promise<number | null>;
  incrementSessionGeneration(installationId: string): Promise<void>;
  createOAuthTransaction(stateHash: string, transaction: OAuthTransaction): Promise<void>;
  consumeOAuthTransaction(stateHash: string, now: Date): Promise<OAuthTransaction | null>;
  createExchangeCode(codeHash: string, code: ExchangeCode): Promise<void>;
  consumeExchangeCode(codeHash: string, now: Date): Promise<ExchangeCode | null>;
  getCredential(installationId: string): Promise<StoredWhoopCredential | null>;
  saveCredential(credential: StoredWhoopCredential): Promise<void>;
  deleteCredential(installationId: string): Promise<void>;
  getCheckpoint(
    installationId: string,
    resourceType: WhoopResourceType,
  ): Promise<SyncCheckpointRecord | null>;
  saveCheckpoint(checkpoint: SyncCheckpointRecord): Promise<void>;
  withInstallationLock<T>(
    installationId: string,
    operation: (store: AuthStore) => Promise<T>,
  ): Promise<T>;
}
