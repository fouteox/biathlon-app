import { sendLot, type LotPush } from "../src/pushSender";

/**
 * In-process stand-in for the `PUSH_SENDER` Durable Object namespace: each `send` runs the
 * lot like the object would, and records its size in `lots` and the object it went to in
 * `objects`, or throws when `failing`.
 */
export function pushSenders(lots: number[] = [], options: { failing?: boolean; objects?: string[] } = {}) {
  let created = 0;
  return {
    newUniqueId: () => `object-${(created += 1)}`,
    get: (id: string) => ({
      send: async (pushes: LotPush[], providerToken: string) => {
        lots.push(pushes.length);
        options.objects?.push(id);
        if (options.failing) throw new Error("Durable Object unavailable");
        return sendLot(pushes, providerToken);
      },
    }),
  } as unknown as Env["PUSH_SENDER"];
}
