import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { TV_COVERAGE } from "../src/tvCoverage";

// `Events?SeasonId=2627&Level=1`, fetched 2026-10-24. An event ends on its Sunday at 12:00 UTC,
// before that day's last races: coverage must run to the end of that day.
const EVENTS_2627 = [
  ["Kontiolahti", "2026-11-23", "2026-11-29"],
  ["Hochfilzen", "2026-11-30", "2026-12-06"],
  ["Le Grand Bornand", "2026-12-07", "2026-12-13"],
  ["Pokljuka", "2026-12-31", "2027-01-03"],
  ["Ruhpolding", "2027-01-04", "2027-01-10"],
  ["Antholz-Anterselva", "2027-01-11", "2027-01-17"],
  ["Nove Mesto na Morave", "2027-01-18", "2027-01-24"],
  ["Otepaa", "2027-02-07", "2027-02-21"],
  ["Oberhof", "2027-03-01", "2027-03-07"],
  ["Oestersund", "2027-03-08", "2027-03-14"],
  ["Oslo Holmenkollen", "2027-03-15", "2027-03-21"],
] as const;

const DAY = 86_400_000;
const COUNTRIES = ["FR", "GB", "DE"];

const broadcastersOn = (country: string, time: number) =>
  TV_COVERAGE.filter((entry) => entry.country === country && Date.parse(entry.from) <= time && time < Date.parse(entry.until)).map(
    (entry) => entry.broadcaster,
  );

describe("TV coverage", () => {
  for (const entry of TV_COVERAGE) {
    it(`describes ${entry.broadcaster} in ${entry.country} from ${entry.from}`, () => {
      expect(COUNTRIES).toContain(entry.country);
      expect(new URL(entry.url).protocol).toBe("https:");
      // Whole UTC days, so a period never cuts a race day in two.
      for (const bound of [entry.from, entry.until]) expect(bound).toMatch(/^\d{4}-\d{2}-\d{2}T00:00:00Z$/);
      expect(Date.parse(entry.from)).toBeLessThan(Date.parse(entry.until));
    });
  }

  for (const [name, first, last] of EVENTS_2627) {
    it(`names a broadcaster in every country on every day of ${name}`, () => {
      for (let time = Date.parse(`${first}T00:00:00Z`); time <= Date.parse(`${last}T23:59:59Z`); time += DAY / 2) {
        for (const country of COUNTRIES) expect(broadcastersOn(country, time), `${country} ${new Date(time).toISOString()}`).not.toEqual([]);
      }
    });
  }

  it("follows ZDF's announced weeks in Germany, ARD's in between", () => {
    expect(broadcastersOn("DE", Date.parse("2026-11-26T15:15:00Z"))).toEqual(["ARD"]);
    expect(broadcastersOn("DE", Date.parse("2026-12-04T13:15:00Z"))).toEqual(["ZDF"]);
    expect(broadcastersOn("DE", Date.parse("2027-02-14T13:15:00Z"))).toEqual(["ARD"]);
    expect(broadcastersOn("DE", Date.parse("2027-02-17T13:15:00Z"))).toEqual(["ZDF"]);
  });
});

describe("GET /v1/tv-coverage", () => {
  it("serves the coverage to the app, cacheable for an hour", async () => {
    const response = await worker.fetch(new Request("https://server.test/v1/tv-coverage"), {} as Env, {} as ExecutionContext);
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=3600");
    expect(await response.json()).toEqual({ coverage: TV_COVERAGE });
  });
});
