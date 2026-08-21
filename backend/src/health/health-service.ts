import type { ApiSuccess } from "@/src/contracts/api";

export const serviceName = "whoops-backend" as const;
export const serviceVersion = "0.1.0" as const;

export interface HealthStatus {
  status: "ok";
  service: typeof serviceName;
  version: typeof serviceVersion;
  timestamp: string;
}

export function buildHealthResponse(
  requestId: string,
  now: Date = new Date(),
): ApiSuccess<HealthStatus> {
  return {
    data: {
      status: "ok",
      service: serviceName,
      version: serviceVersion,
      timestamp: now.toISOString(),
    },
    meta: { requestId },
  };
}
