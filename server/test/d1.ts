import { readdirSync, readFileSync } from "node:fs";
import { DatabaseSync, type SQLInputValue } from "node:sqlite";

/** In-memory stand-in for the slice of the D1 API the Worker uses, with the real migrations. */
export function makeD1(): D1Database {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("PRAGMA foreign_keys = ON");
  const dir = new URL("../migrations/", import.meta.url);
  for (const file of readdirSync(dir).sort()) sqlite.exec(readFileSync(new URL(file, dir), "utf8"));

  const statement = (sql: string, params: SQLInputValue[] = []) => ({
    bind: (...values: unknown[]) => statement(sql, values as SQLInputValue[]),
    run: async () => ({ meta: { changes: Number(sqlite.prepare(sql).run(...params).changes) } }),
    first: async () => sqlite.prepare(sql).get(...params) ?? null,
    all: async () => ({ results: sqlite.prepare(sql).all(...params) }),
  });
  return {
    prepare: (sql: string) => statement(sql),
    batch: async (statements: { run: () => Promise<unknown> }[]) => {
      sqlite.exec("BEGIN");
      try {
        const results = [];
        for (const item of statements) results.push(await item.run());
        sqlite.exec("COMMIT");
        return results;
      } catch (error) {
        sqlite.exec("ROLLBACK");
        throw error;
      }
    },
  } as unknown as D1Database;
}
