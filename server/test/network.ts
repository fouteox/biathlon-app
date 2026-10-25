import { setupNetwork } from "@msw/cloudflare";
import { http, type DefaultBodyType, type StrictRequest } from "msw";

/** The Worker's outbound requests, to APNs and the IBU API: a test answers them all, none reaches the network. */
export const network = setupNetwork();
network.configure({ onUnhandledFrame: "error" });

/**
 * Answers every outbound request with `respond`, ahead of the answers set up earlier in the
 * test: returning nothing hands the request on to them.
 */
export function answer(
  respond: (request: StrictRequest<DefaultBodyType>) => Response | undefined | Promise<Response | undefined>,
): void {
  network.use(http.all("*", ({ request }) => respond(request)));
}
