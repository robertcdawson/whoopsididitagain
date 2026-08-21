import type {
  AuthStore,
  ExchangeCode,
  OAuthTransaction,
  StoredWhoopCredential,
  SyncCheckpointRecord,
  WhoopResourceType,
} from "@/src/db/auth-store";

export class InMemoryAuthStore implements AuthStore {
  private readonly installations = new Map<string, number>();
  private readonly oauthTransactions = new Map<string, OAuthTransaction>();
  private readonly exchangeCodes = new Map<string, ExchangeCode>();
  private readonly credentials = new Map<string, StoredWhoopCredential>();
  private readonly checkpoints = new Map<string, SyncCheckpointRecord>();
  private readonly lockTails = new Map<string, Promise<void>>();

  async ensureInstallation(installationId: string): Promise<void> {
    if (!this.installations.has(installationId)) {
      this.installations.set(installationId, 0);
    }
  }

  async sessionGeneration(installationId: string): Promise<number | null> {
    return this.installations.get(installationId) ?? null;
  }

  async incrementSessionGeneration(installationId: string): Promise<void> {
    const generation = this.installations.get(installationId);
    if (generation !== undefined) {
      this.installations.set(installationId, generation + 1);
    }
  }

  async createOAuthTransaction(stateHash: string, transaction: OAuthTransaction): Promise<void> {
    this.oauthTransactions.set(stateHash, transaction);
  }

  async consumeOAuthTransaction(
    stateHash: string,
    now: Date,
  ): Promise<OAuthTransaction | null> {
    const transaction = this.oauthTransactions.get(stateHash) ?? null;
    this.oauthTransactions.delete(stateHash);
    return transaction && transaction.expiresAt > now ? transaction : null;
  }

  async createExchangeCode(codeHash: string, code: ExchangeCode): Promise<void> {
    this.exchangeCodes.set(codeHash, code);
  }

  async consumeExchangeCode(codeHash: string, now: Date): Promise<ExchangeCode | null> {
    const code = this.exchangeCodes.get(codeHash) ?? null;
    this.exchangeCodes.delete(codeHash);
    return code && code.expiresAt > now ? code : null;
  }

  async getCredential(installationId: string): Promise<StoredWhoopCredential | null> {
    return this.credentials.get(installationId) ?? null;
  }

  async saveCredential(credential: StoredWhoopCredential): Promise<void> {
    this.credentials.set(credential.installationId, credential);
  }

  async deleteCredential(installationId: string): Promise<void> {
    this.credentials.delete(installationId);
    for (const key of this.checkpoints.keys()) {
      if (key.startsWith(`${installationId}:`)) {
        this.checkpoints.delete(key);
      }
    }
  }

  async getCheckpoint(
    installationId: string,
    resourceType: WhoopResourceType,
  ): Promise<SyncCheckpointRecord | null> {
    return this.checkpoints.get(`${installationId}:${resourceType}`) ?? null;
  }

  async saveCheckpoint(checkpoint: SyncCheckpointRecord): Promise<void> {
    this.checkpoints.set(
      `${checkpoint.installationId}:${checkpoint.resourceType}`,
      checkpoint,
    );
  }

  async withInstallationLock<T>(
    installationId: string,
    operation: (store: AuthStore) => Promise<T>,
  ): Promise<T> {
    const previous = this.lockTails.get(installationId) ?? Promise.resolve();
    let release: () => void = () => undefined;
    const current = new Promise<void>((resolve) => {
      release = resolve;
    });
    const tail = previous.then(() => current);
    this.lockTails.set(installationId, tail);
    await previous;
    try {
      return await operation(this);
    } finally {
      release();
      if (this.lockTails.get(installationId) === tail) {
        this.lockTails.delete(installationId);
      }
    }
  }
}
