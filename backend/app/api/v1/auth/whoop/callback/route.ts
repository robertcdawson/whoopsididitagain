import { AppError } from "@/src/http/app-error";
import { services } from "@/src/service-container";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  const oauthError = url.searchParams.get("error");

  if (oauthError) {
    return new Response("WHOOP authorization was cancelled.", { status: 400 });
  }
  if (!state || !code) {
    return new Response("The WHOOP callback is missing required values.", { status: 400 });
  }

  try {
    const redirect = await services().oauth.callback(state, code);
    return Response.redirect(redirect, 302);
  } catch (error) {
    const status = error instanceof AppError ? error.status : 500;
    return new Response("WHOOP authorization could not be completed.", { status });
  }
}
