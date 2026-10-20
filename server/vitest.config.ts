import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    alias: {
      // Workers runtime module, absent from Node: the tests call the Durable Objects' code directly.
      "cloudflare:workers": new URL("./test/cloudflareWorkers.ts", import.meta.url).pathname,
    },
  },
});
