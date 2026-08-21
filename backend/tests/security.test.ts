import { describe, expect, it } from "vitest";

import { decryptSecret, encryptSecret } from "@/src/security/encryption";
import { signSessionToken, verifySessionToken } from "@/src/security/session-token";

describe("credential encryption", () => {
  it("round trips without embedding plaintext", () => {
    const key = Buffer.alloc(32, 4);
    const encrypted = encryptSecret("sensitive-token", key);

    expect(encrypted).not.toContain("sensitive-token");
    expect(decryptSecret(encrypted, key)).toBe("sensitive-token");
  });

  it("rejects an altered authentication tag", () => {
    const key = Buffer.alloc(32, 4);
    const encrypted = encryptSecret("sensitive-token", key);
    const pieces = encrypted.split(".");
    pieces[2] = Buffer.alloc(16, 2).toString("base64url");

    expect(() => decryptSecret(pieces.join("."), key)).toThrow();
  });
});

describe("app session tokens", () => {
  it("verifies type, generation, and expiry", () => {
    const key = Buffer.alloc(32, 3);
    const now = new Date("2026-08-15T12:00:00.000Z");
    const token = signSessionToken("installation", "access", 2, key, now);

    expect(verifySessionToken(token, "access", key, now)).toMatchObject({
      sub: "installation",
      typ: "access",
      gen: 2,
    });
    expect(() =>
      verifySessionToken(token, "access", key, new Date("2026-08-15T12:16:00.000Z")),
    ).toThrow(/expired/i);
  });
});
