import { DurableObject } from "cloudflare:workers";
import { sendPush, type PushOutcome, type PushRequest } from "./apns";
import { buildPayload, type AlertInput } from "./payload";
import { deadlineSignal } from "./subrequests";

/**
 * A device push of a lot: its payload, or the alert to build it from on the device's
 * language and time zone, which `Intl` makes too costly for the cron's CPU time.
 */
export type LotPush = Omit<PushRequest, "payload"> & ({ payload: unknown } | { alert: AlertInput });

/**
 * The requests one Durable Object request may wait on at once: more are queued until one
 * gets its response headers (https://developers.cloudflare.com/durable-objects/platform/limits/).
 */
const SIMULTANEOUS_CONNECTIONS = 6;

/**
 * Sends the device pushes of one lot. Each invocation of a Durable Object has its own
 * budget of external subrequests, 50 on the Workers Free plan
 * (https://developers.cloudflare.com/workers/platform/limits/#subrequests): the cron
 * hands its pushes out in lots, and spends none of its own budget on them.
 */
export class PushSender extends DurableObject<Env> {
  /**
   * Sends the pushes, `SIMULTANEOUS_CONNECTIONS` at a time, the outcome of each at its index;
   * those still unanswered at `deadline`, if any, are retries.
   */
  async send(pushes: LotPush[], providerToken: string, deadline?: number): Promise<PushOutcome[]> {
    const outcomes: PushOutcome[] = [];
    let next = 0;
    const connection = async () => {
      for (let index = next++; index < pushes.length; index = next++) {
        const push = pushes[index]!;
        const payload = "alert" in push ? buildPayload(push.alert) : push.payload;
        outcomes[index] = await sendPush({ ...push, payload }, providerToken, deadlineSignal(deadline));
      }
    };
    await Promise.all(Array.from({ length: Math.min(SIMULTANEOUS_CONNECTIONS, pushes.length) }, connection));
    return outcomes;
  }
}
