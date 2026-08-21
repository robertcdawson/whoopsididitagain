import { describe, expect, it } from "vitest";

import { buildHealthResponse } from "@/src/health/health-service";

describe("buildHealthResponse", () => {
  it("returns the stable versioned health contract", () => {
    const now = new Date("2026-08-15T12:00:00.000Z");

    expect(buildHealthResponse("request-123", now)).toEqual({
      data: {
        status: "ok",
        service: "whoops-backend",
        version: "0.1.0",
        timestamp: "2026-08-15T12:00:00.000Z",
      },
      meta: { requestId: "request-123" },
    });
  });
});
