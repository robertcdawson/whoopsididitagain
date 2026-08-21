import { buildHealthResponse } from "@/src/health/health-service";

export const dynamic = "force-dynamic";

export function GET(request: Request): Response {
  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();

  return Response.json(buildHealthResponse(requestId), {
    headers: {
      "cache-control": "no-store",
      "x-request-id": requestId,
    },
  });
}
