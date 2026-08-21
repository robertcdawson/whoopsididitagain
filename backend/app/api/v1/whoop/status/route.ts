import { failure, requestId, success } from "@/src/http/route";
import { services } from "@/src/service-container";

export async function GET(request: Request): Promise<Response> {
  const id = requestId(request);
  try {
    const container = services();
    const installationId = await container.oauth.authenticate(request);
    return success(await container.tokens.connectionStatus(installationId), id);
  } catch (error) {
    return failure(error, id);
  }
}
