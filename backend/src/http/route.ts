import type { ApiFailure, ApiSuccess } from "@/src/contracts/api";
import { AppError, asAppError } from "@/src/http/app-error";

export function requestId(request: Request): string {
  return request.headers.get("x-request-id") ?? crypto.randomUUID();
}

export function success<T>(data: T, id: string, status = 200): Response {
  const body: ApiSuccess<T> = { data, meta: { requestId: id } };
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store", "x-request-id": id },
  });
}

export function failure(error: unknown, id: string): Response {
  const appError = asAppError(error);
  const body: ApiFailure = {
    error: {
      code: appError.code,
      message: appError.message,
      retryable: appError.retryable,
      details: appError.details,
    },
    meta: { requestId: id },
  };
  return Response.json(body, {
    status: appError.status,
    headers: { "cache-control": "no-store", "x-request-id": id },
  });
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new AppError("invalid_json", "The request body must be valid JSON.", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new AppError("invalid_json", "The request body must be a JSON object.", 400);
  }
  return body as Record<string, unknown>;
}

export function requiredString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new AppError(`invalid_${key}`, `${key} must be a non-empty string.`, 400);
  }
  return value.trim();
}
