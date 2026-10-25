declare namespace Cloudflare {
  interface Env {
    /** The D1 migrations, read by vite.config.ts and applied before each test. */
    TEST_MIGRATIONS: import("cloudflare:test").D1Migration[];
  }
}

/** A file's text, imported with Vite's `?raw` suffix. */
declare module "*?raw" {
  const text: string;
  export default text;
}
