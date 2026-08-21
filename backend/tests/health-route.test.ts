import { describe, expect, it } from "vitest";

import { GET } from "@/app/api/v1/health/route";

describe("GET /api/v1/health", () => {
  it("echoes a request correlation identifier and disables caching", async () => {
    const request = new Request("http://localhost/api/v1/health", {
      headers: { "x-request-id": "correlation-456" },
    });

    const response = GET(request);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-request-id")).toBe("correlation-456");
    expect(body.meta.requestId).toBe("correlation-456");
    expect(body.data.status).toBe("ok");
  });
});
