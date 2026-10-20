/** The part of `cloudflare:workers` the Worker imports, for the tests run in Node. */
export class DurableObject<Env = unknown> {
  constructor(
    protected readonly ctx: DurableObjectState,
    protected readonly env: Env,
  ) {}
}
