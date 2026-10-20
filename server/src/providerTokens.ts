import { makeProviderToken, PROVIDER_TOKEN_LIFETIME_S, type APNsEnvironment } from "./apns";
import type { SubrequestBudget } from "./subrequests";

/** A request left for the next run. */
export type Deferred = { kind: "deferred" };
export const DEFERRED: Deferred = { kind: "deferred" };

/**
 * The APNs provider tokens of one cron run, one per environment, as Apple
 * recommends for team-scoped keys. A token is reused from D1 while it is younger
 * than its lifetime. Each request spends one subrequest of the run's budget.
 */
export class ProviderTokens {
  private readonly tokens = new Map<APNsEnvironment, string>();
  private readonly refreshed = new Set<APNsEnvironment>();

  constructor(
    private readonly env: Env,
    private readonly now: number,
    private readonly budget: SubrequestBudget,
  ) {}

  /**
   * Runs `request` with the environment's token. When APNs rejects the token, signs
   * a new one and retries, at most once per run: APNs rejects updates more frequent
   * than every 20 minutes. "deferred" once the run has no subrequest left.
   */
  async send<Outcome extends { kind: string }>(
    environment: APNsEnvironment,
    request: (token: string) => Promise<Outcome>,
  ): Promise<Outcome | Deferred> {
    if (!this.budget.take()) return DEFERRED;
    const outcome = await request(await this.token(environment));
    if (outcome.kind !== "expiredProviderToken") return outcome;
    const token = await this.renew(environment);
    if (!token) return outcome;
    if (!this.budget.take()) return DEFERRED;
    return request(token);
  }

  /**
   * Signs and caches a new token after APNs rejected the current one, at most once per run;
   * `undefined` once renewed. Cached before the retry, which may wait for the next run.
   */
  async renew(environment: APNsEnvironment): Promise<string | undefined> {
    if (this.refreshed.has(environment)) return undefined;
    this.refreshed.add(environment);
    return this.token(environment, true);
  }

  /** The environment's token, signed or read from D1 at the first request of the run. */
  async token(environment: APNsEnvironment, forceRefresh = false): Promise<string> {
    const current = this.tokens.get(environment);
    if (current && !forceRefresh) return current;
    const token = await this.load(environment, forceRefresh);
    this.tokens.set(environment, token);
    return token;
  }

  private async load(environment: APNsEnvironment, forceRefresh: boolean): Promise<string> {
    const { env, now } = this;
    const cacheKey = `apns_token_${environment}`;
    if (!forceRefresh) {
      const cached = await env.DB.prepare("SELECT value, updated_at FROM settings WHERE key = ?1")
        .bind(cacheKey)
        .first<{ value: string; updated_at: number }>();
      if (cached && now - cached.updated_at < PROVIDER_TOKEN_LIFETIME_S * 1000) return cached.value;
    }
    const key =
      environment === "sandbox"
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
