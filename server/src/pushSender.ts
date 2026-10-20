import { DurableObject } from "cloudflare:workers";
import { sendPush, type PushOutcome, type PushRequest } from "./apns";
import { buildPayload, type AlertInput } from "./payload";

/**
 * A device push of a lot: its payload, or the alert to build it from on the device's
 * language and time zone, which `Intl` makes too costly for the cron's CPU time.
 */
export type LotPush = Omit<PushRequest, "payload"> & ({ payload: unknown } | { alert: AlertInput });

/**
 * Sends the device pushes of one lot. Each invocation of a Durable Object has its own
 * budget of external subrequests, 50 on the Workers Free plan
 * (https://developers.cloudflare.com/workers/platform/limits/#subrequests): the cron
 * hands its pushes out in lots, and spends none of its own budget on them.
 */
export class PushSender extends DurableObject<Env> {
  async send(pushes: LotPush[], providerToken: string): Promise<PushOutcome[]> {
    return sendLot(pushes, providerToken);
  }
}

/** Sends the pushes one after another, the outcome of each at its index. */
export async function sendLot(pushes: LotPush[], providerToken: string): Promise<PushOutcome[]> {
  const outcomes: PushOutcome[] = [];
  for (const push of pushes) {
    const payload = "alert" in push ? buildPayload(push.alert) : push.payload;
    outcomes.push(await sendPush({ ...push, payload }, providerToken));
  }
  return outcomes;
}
