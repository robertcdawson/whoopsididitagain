import { createHash, randomBytes } from "node:crypto";

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function randomOAuthState(): string {
  return randomBytes(6).toString("base64url");
}

export function hashOpaqueValue(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("base64url");
}
