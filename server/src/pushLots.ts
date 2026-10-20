import type { APNsEnvironment, PushOutcome } from "./apns";
import { DEFERRED, type Deferred, type ProviderTokens } from "./providerTokens";
import type { LotPush } from "./pushSender";
import { SUBREQUESTS_PER_RUN } from "./subrequests";

/** The pushes one Durable Object invocation sends: its whole budget of external subrequests. */
export const LOT_SIZE = SUBREQUESTS_PER_RUN;

/**
 * The pushes a run sends at most: 15,000 recipients of one alert in the 30 minutes it stays
 * useful (`OUTBOX_MAX_AGE_MS`). Each lot is one Durable Object request (100,000 a day on the
 * Free plan) and one of the run's 1,000 subrequests to Cloudflare services, which its D1 calls
 * share: their number doesn't grow with the pushes, claimed and settled in one call each.
 */
export const MAX_PUSHES_PER_RUN = 500;

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
   * again once, with a new one, as `ProviderTokens.send` does for a single request.
   */
  private async sendAll(environment: APNsEnvironment, items: Pending[]): Promise<void> {
    const outcomes = await this.lots(environment, await this.tokens.token(environment), items.map(({ push }) => push));
    const expired = outcomes.flatMap((outcome, index) => (outcome.kind === "expiredProviderToken" ? [index] : []));
    const renewed = expired.length > 0 ? await this.tokens.renew(environment) : undefined;
    if (renewed) {
      const retried = await this.lots(environment, renewed, expired.map((index) => items[index]!.push));
      expired.forEach((index, position) => (outcomes[index] = retried[position]!));
    }
    items.forEach(({ resolve }, index) => resolve(outcomes[index]!));
  }

  private async lots(environment: APNsEnvironment, providerToken: string, pushes: LotPush[]): Promise<PushOutcome[]> {
    const lots = Array.from({ length: Math.ceil(pushes.length / LOT_SIZE) }, (_, index) =>
      pushes.slice(index * LOT_SIZE, (index + 1) * LOT_SIZE),
    );
    const outcomes = await Promise.all(
      lots.map((lot, index) =>
        this.env.PUSH_SENDER.getByName(`${environment}-${index}`)
          .send(lot, providerToken)
          .catch((error: unknown) => lot.map((): PushOutcome => ({ kind: "retry", reason: String(error) }))),
      ),
    );
    return outcomes.flat();
  }
}
