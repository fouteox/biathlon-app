import { applyD1Migrations, reset } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterAll, afterEach, beforeAll, beforeEach } from "vite-plus/test";
import { network } from "./network";

// Storage is isolated per test file: each test starts from an empty, migrated database.
beforeEach(async () => {
  await reset();
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
});

beforeAll(() => network.enable());
afterEach(() => network.resetHandlers());
afterAll(() => network.disable());
