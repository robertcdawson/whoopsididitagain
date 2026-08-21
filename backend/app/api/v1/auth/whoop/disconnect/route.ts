import { failure, requestId, success } from "@/src/http/route";
import { services } from "@/src/service-container";

export async function POST(request: Request): Promise<Response> {
  const id = requestId(request);
  try {
    const container = services();
    const installationId = await container.oauth.authenticate(request);
    await container.tokens.disconnect(installationId);
    return success({ disconnected: true }, id);
  } catch (error) {
    return failure(error, id);
  }
}
