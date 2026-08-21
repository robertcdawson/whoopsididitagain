import { createHmac, timingSafeEqual } from "node:crypto";

import { AppError } from "@/src/http/app-error";

export type SessionTokenType = "access" | "refresh";

export interface SessionClaims {
  sub: string;
  typ: SessionTokenType;
  gen: number;
  iat: number;
  exp: number;
}

function signature(value: string, key: Buffer): Buffer {
  return createHmac("sha256", key).update(value).digest();
}

export function signSessionToken(
  subject: string,
  type: SessionTokenType,
  generation: number,
  key: Buffer,
  now = new Date(),
): string {
  const issuedAt = Math.floor(now.getTime() / 1_000);
  const lifetime = type === "access" ? 15 * 60 : 30 * 24 * 60 * 60;
  const claims: SessionClaims = {
    sub: subject,
    typ: type,
    gen: generation,
    iat: issuedAt,
    exp: issuedAt + lifetime,
  };
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  return `${payload}.${signature(payload, key).toString("base64url")}`;
}

export function verifySessionToken(
  token: string,
  expectedType: SessionTokenType,
  key: Buffer,
  now = new Date(),
): SessionClaims {
  const [payload, encodedSignature, ...extra] = token.split(".");
  if (!payload || !encodedSignature || extra.length > 0) {
    throw new AppError("invalid_session", "The app session is invalid.", 401);
  }

  const actualSignature = Buffer.from(encodedSignature, "base64url");
  const expectedSignature = signature(payload, key);
  if (
    actualSignature.length !== expectedSignature.length ||
    !timingSafeEqual(actualSignature, expectedSignature)
  ) {
    throw new AppError("invalid_session", "The app session is invalid.", 401);
  }

  let claims: SessionClaims;
  try {
    claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as SessionClaims;
  } catch {
    throw new AppError("invalid_session", "The app session is invalid.", 401);
  }

  const nowSeconds = Math.floor(now.getTime() / 1_000);
  if (
    claims.typ !== expectedType ||
    typeof claims.sub !== "string" ||
    typeof claims.gen !== "number" ||
    typeof claims.exp !== "number" ||
    claims.exp <= nowSeconds
  ) {
    throw new AppError("expired_session", "The app session has expired.", 401);
  }
  return claims;
}
