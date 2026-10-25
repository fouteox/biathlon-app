import { describe, expect, it } from "vite-plus/test";
import fixture from "../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures/race-status.json";
import { snapshot, type IBUCompetition } from "../src/ibu";

// Shared with the app's BiathlonKit tests, so alerts and screens agree on a race's status.
const cases: { name: string; status: string; race: IBUCompetition }[] = fixture;

describe("race status shared with the app", () => {
  for (const { name, status, race } of cases) {
    it(name, () => {
      expect(snapshot(race).status).toBe(status);
    });
  }
});
