/**
 * External subrequests (APNs, IBU API) one invocation may make: the Workers Free plan
 * allows 50, D1 queries aside (https://developers.cloudflare.com/workers/platform/limits/).
 */
export const SUBREQUESTS_PER_RUN = 50;

/** The subrequests one cron run has left, shared by its phases in order of priority. */
export class SubrequestBudget {
  constructor(private remaining = SUBREQUESTS_PER_RUN) {}

  /** Whether `count` are left. */
  has(count: number): boolean {
    return this.remaining >= count;
  }

  /** Takes one subrequest; `false` once none is left, for the next run to carry on. */
  take(): boolean {
    if (this.remaining === 0) return false;
    this.remaining -= 1;
    return true;
  }
}
