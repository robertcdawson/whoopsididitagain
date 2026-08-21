import { failure, readJsonObject, requestId, requiredString, success } from "@/src/http/route";
import { services } from "@/src/service-container";

export async function POST(request: Request): Promise<Response> {
  const id = requestId(request);
  try {
    const body = await readJsonObject(request);
    const result = await services().oauth.start(requiredString(body, "installationId"));
    return success(result, id, 201);
  } catch (error) {
    return failure(error, id);
  }
}
