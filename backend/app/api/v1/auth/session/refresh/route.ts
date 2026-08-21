import { failure, readJsonObject, requestId, requiredString, success } from "@/src/http/route";
import { services } from "@/src/service-container";

export async function POST(request: Request): Promise<Response> {
  const id = requestId(request);
  try {
    const body = await readJsonObject(request);
    const session = await services().oauth.refresh(requiredString(body, "refreshToken"));
    return success(session, id);
  } catch (error) {
    return failure(error, id);
  }
}
