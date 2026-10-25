/**
 * External subrequests (APNs, IBU API) one invocation may make: the Workers Free plan
 * allows 50, D1 queries aside (https://developers.cloudflare.com/workers/platform/limits/).
 */
export const SUBREQUESTS_PER_RUN = 50;

/**
 * The signal that aborts a subrequest still unanswered at `deadline`, if there is one: a
 * subrequest has no time limit of its own (https://developers.cloudflare.com/workers/platform/limits/).
 */
export function deadlineSignal(deadline: number | undefined): AbortSignal | undefined {
  return deadline === undefined ? undefined : AbortSignal.timeout(Math.max(0, deadline - Date.now()));
}

/**
 * The subrequests one cron run has left, shared by its phases in order of priority, and the
 * time by which they must be answered, if any.
 */
export class SubrequestBudget {
  constructor(
    private remaining = SUBREQUESTS_PER_RUN,
    readonly deadline?: number,
  ) {}

  /** The signal of a subrequest, aborted at the deadline. */
  signal(): AbortSignal | undefined {
    return deadlineSignal(this.deadline);
  }

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
