export interface AppConfig {
  whoopClientId: string;
  whoopClientSecret: string;
  whoopRedirectUri: string;
  appDeepLink: string;
  oauthEncryptionKey: Buffer;
  appSessionSigningKey: Buffer;
}

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function decodeKey(name: string, minimumBytes: number): Buffer {
  const encoded = required(name);
  const key = Buffer.from(encoded, "base64");
  if (key.length < minimumBytes) {
    throw new Error(`${name} must be base64-encoded and at least ${minimumBytes} bytes`);
  }
  return key;
}

export function loadAppConfig(): AppConfig {
  const encryptionKey = decodeKey("OAUTH_ENCRYPTION_KEY", 32);
  if (encryptionKey.length !== 32) {
    throw new Error("OAUTH_ENCRYPTION_KEY must decode to exactly 32 bytes");
  }

  return {
    whoopClientId: required("WHOOP_CLIENT_ID"),
    whoopClientSecret: required("WHOOP_CLIENT_SECRET"),
    whoopRedirectUri: required("WHOOP_REDIRECT_URI"),
    appDeepLink: required("APP_DEEP_LINK"),
    oauthEncryptionKey: encryptionKey,
    appSessionSigningKey: decodeKey("APP_SESSION_SIGNING_KEY", 32),
  };
}
