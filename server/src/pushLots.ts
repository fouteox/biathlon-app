import type { APNsEnvironment, PushOutcome } from "./apns";
import { DEFERRED, type Deferred, type ProviderTokens } from "./providerTokens";
import type { LotPush } from "./pushSender";
import { SUBREQUESTS_PER_RUN } from "./subrequests";

/** The pushes one Durable Object invocation sends: its whole budget of external subrequests. */
export const LOT_SIZE = SUBREQUESTS_PER_RUN;

/**
 * The pushes a run sends at most: 15,000 recipients of one alert in the 30 minutes it stays
 * useful (`OUTBOX_MAX_AGE_MS`). Each lot is one Durable Object request (100,000 a day on the
 * Free plan) and one of the run's 1,000 subrequests to Cloudflare services. The run's D1
 * queries, 50 at most on that plan, a batch counting as one, don't grow with its pushes: they
 * are claimed and settled with a few batches of set-based statements.
 */
export const MAX_PUSHES_PER_RUN = 500;

/** The sends of a push that may fail before it is given up, so that an APNs outage doesn't retry it every minute. */
export const MAX_SEND_ATTEMPTS = 5;

interface Pending {
  push: LotPush;
  resolve: (outcome: PushOutcome) => void;
}

/**
 * The device pushes of one cron run, queued then sent in lots, each by a Durable Object
 * (`PushSender`), all at once. Every outcome a lot can't give is a retry.
 */
export class PushLots {
  private pending: Pending[] = [];
  private remaining: number;

  constructor(
    private readonly env: Env,
    private readonly tokens: ProviderTokens,
    capacity = MAX_PUSHES_PER_RUN,
  ) {
    this.remaining = capacity;
  }

  /** The pushes the run can still queue. */
  get room(): number {
    return this.remaining;
  }

  /** Queues a push, which `flush` sends; "deferred" once the run is full. */
  send(push: LotPush): Promise<PushOutcome | Deferred> {
    if (this.remaining === 0) return Promise.resolve(DEFERRED);
    this.remaining -= 1;
    return new Promise((resolve) => this.pending.push({ push, resolve }));
  }

  /** Sends the queued pushes, then settles their promises. */
  async flush(): Promise<void> {
    const pending = this.pending;
    this.pending = [];
    const environments = Map.groupBy(pending, ({ push }) => push.environment);
    await Promise.all([...environments].map(([environment, items]) => this.sendAll(environment, items)));
  }

  /**
   * Sends one environment's pushes. Those APNs answers with an expired provider token go
   * again once, with a new one, as `ProviderTokens.send` does for a single request. Without a
   * provider token, none is sent: each is a retry, or stays expired.
   */
  private async sendAll(environment: APNsEnvironment, items: Pending[]): Promise<void> {
    const pushes = items.map(({ push }) => push);
    const outcomes = await this.tokens.token(environment).then(
      (providerToken) => this.lots(providerToken, pushes),
      (error: unknown) => pushes.map(() => retry(error)),
    );
    const expired = outcomes.flatMap((outcome, index) => (outcome.kind === "expiredProviderToken" ? [index] : []));
    const renewed = expired.length > 0 ? await this.tokens.renew(environment).catch(() => undefined) : undefined;
    if (renewed) {
      const retried = await this.lots(
        renewed,
        expired.map((index) => items[index]!.push),
      );
      expired.forEach((index, position) => (outcomes[index] = retried[position]!));
    }
    items.forEach(({ resolve }, index) => resolve(outcomes[index]!));
  }

  private async lots(providerToken: string, pushes: LotPush[]): Promise<PushOutcome[]> {
    const lots = Array.from({ length: Math.ceil(pushes.length / LOT_SIZE) }, (_, index) =>
      pushes.slice(index * LOT_SIZE, (index + 1) * LOT_SIZE),
    );
    const outcomes = await Promise.all(
      lots.map((lot) =>
        // A new object for each lot: concurrent requests to one object share its subrequests,
        // and Cloudflare sometimes fires the cron twice at once (measured on 2026-10-25).
        this.env.PUSH_SENDER.get(this.env.PUSH_SENDER.newUniqueId())
          .send(lot, providerToken)
          .catch((error: unknown) => lot.map(() => retry(error))),
      ),
    );
    return outcomes.flat();
  }
}

/** The outcome of a push a lot couldn't send. */
function retry(error: unknown): PushOutcome {
  return { kind: "retry", reason: String(error) };
}
