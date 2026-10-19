import { makeProviderToken, PROVIDER_TOKEN_LIFETIME_S, type APNsEnvironment } from "./apns";

/**
 * The APNs provider tokens of one cron run, one per environment, as Apple
 * recommends for team-scoped keys. A token is reused from D1 while it is younger
 * than its lifetime.
 */
export class ProviderTokens {
  private readonly tokens = new Map<APNsEnvironment, string>();
  private readonly refreshed = new Set<APNsEnvironment>();

  constructor(
    private readonly env: Env,
    private readonly now: number,
  ) {}

  /**
   * Runs `request` with the environment's token. When APNs rejects the token, signs
   * a new one and retries, at most once per run: APNs rejects updates more frequent
   * than every 20 minutes.
   */
  async send<Outcome extends { kind: string }>(
    environment: APNsEnvironment,
    request: (token: string) => Promise<Outcome>,
  ): Promise<Outcome> {
    const outcome = await request(await this.token(environment));
    if (outcome.kind !== "expiredProviderToken" || this.refreshed.has(environment)) return outcome;
    this.refreshed.add(environment);
    return request(await this.token(environment, true));
  }

  private async token(environment: APNsEnvironment, forceRefresh = false): Promise<string> {
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
