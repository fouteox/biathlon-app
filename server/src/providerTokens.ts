import { makeProviderToken, PROVIDER_TOKEN_LIFETIME_S } from "./apns";
import { accessToken } from "./google";
import type { PushService } from "./pushSender";
import type { SubrequestBudget } from "./subrequests";

/** A request left for the next run. */
export type Deferred = { kind: "deferred" };
export const DEFERRED: Deferred = { kind: "deferred" };

/** The provider tokens, per push service, a cron run hands to the Durable Objects it calls. */
export type ProviderTokenSet = Partial<Record<PushService, string>>;

/**
 * The provider tokens of one cron run: APNs's, one per environment, as Apple recommends for
 * team-scoped keys, and FCM's, a Google access token. A token is reused from D1 while it is
 * valid, or taken from the cron run that `given` them. Each request spends one subrequest of the
 * budget, and so does fetching a new Google access token.
 */
export class ProviderTokens {
  private readonly tokens = new Map<PushService, string>();
  private readonly refreshed = new Set<PushService>();

  constructor(
    private readonly env: Env,
    private readonly now: number,
    readonly budget: SubrequestBudget,
    private readonly given?: ProviderTokenSet,
  ) {}

  /**
   * Runs `request` with the service's token and the budget's signal. When the service rejects the token, signs
   * a new one and retries, at most once per run: APNs rejects updates more frequent
   * than every 20 minutes. "deferred" once the run has no subrequest left.
   */
  async send<Outcome extends { kind: string }>(
    service: PushService,
    request: (token: string, signal?: AbortSignal) => Promise<Outcome>,
  ): Promise<Outcome | Deferred> {
    if (!this.budget.take()) return DEFERRED;
    const outcome = await request(await this.token(service), this.budget.signal());
    if (outcome.kind !== "expiredProviderToken") return outcome;
    const token = await this.renew(service);
    if (!token) return outcome;
    if (!this.budget.take()) return DEFERRED;
    return request(token, this.budget.signal());
  }

  /**
   * Signs and caches a new token after the service rejected the current one, at most once per run;
   * `undefined` once renewed. Cached before the retry, which may wait for the next run.
   */
  async renew(service: PushService): Promise<string | undefined> {
    if (this.refreshed.has(service)) return undefined;
    this.refreshed.add(service);
    return this.token(service, true);
  }

  /** The service's token, given, or signed or read from D1 at the first request of the run. */
  async token(service: PushService, forceRefresh = false): Promise<string> {
    const current = this.tokens.get(service) ?? this.given?.[service];
    if (current && !forceRefresh) return current;
    const token = await this.load(service, forceRefresh);
    this.tokens.set(service, token);
    return token;
  }

  private async load(service: PushService, forceRefresh: boolean): Promise<string> {
    const { env, now, budget } = this;
    if (service === "fcm") return accessToken(env, now, { refresh: forceRefresh, budget });
    const cacheKey = `apns_token_${service}`;
    if (!forceRefresh) {
      const cached = await env.DB.prepare("SELECT value, updated_at FROM settings WHERE key = ?1")
        .bind(cacheKey)
        .first<{ value: string; updated_at: number }>();
      if (cached && now - cached.updated_at < PROVIDER_TOKEN_LIFETIME_S * 1000) return cached.value;
    }
    const key =
      service === "sandbox"
        ? { pem: env.APNS_SANDBOX_KEY, keyId: env.APNS_SANDBOX_KEY_ID, teamId: env.APNS_TEAM_ID }
        : { pem: env.APNS_PRODUCTION_KEY, keyId: env.APNS_PRODUCTION_KEY_ID, teamId: env.APNS_TEAM_ID };
    const token = await makeProviderToken(key, Math.floor(now / 1000));
    await env.DB.prepare(
      `INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
    )
      .bind(cacheKey, token, now)
      .run();
    return token;
  }
}
