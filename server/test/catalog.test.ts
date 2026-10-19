import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { LOC_KEYS } from "../src/payload";

// APNs resolves loc-keys from the app's Localizable table, so every key the
// server sends must exist there in every app language.
describe("app String Catalog", () => {
  const catalog = JSON.parse(readFileSync(new URL("../../Shared/Localizable.xcstrings", import.meta.url), "utf8"));

  for (const key of Object.values(LOC_KEYS).flatMap((pair) => Object.values(pair))) {
    it(`translates ${key}`, () => {
      const localizations = catalog.strings[key]?.localizations;
      expect(localizations?.en?.stringUnit?.value).toBeTruthy();
      expect(localizations?.fr?.stringUnit?.value).toBeTruthy();
    });
  }
});
