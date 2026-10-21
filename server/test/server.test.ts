import { describe, expect, it } from "vitest";
import { classify, makeProviderToken } from "../src/apns";
import { detectChange } from "../src/changes";
import { parseRegistration } from "../src/devices";
import { activeEvents, seasonId, snapshot, type RaceSnapshot } from "../src/ibu";
import { buildPayload, formatStart } from "../src/payload";

// Shape of a real `Competitions?EventId=BT2627SWRLCP01` row, fetched 2026-10-19.
const scheduled = {
  RaceId: "BT2627SWRLCP01SMIN",
  catId: "SM",
  ShortDescription: "Men's 20km Individual",
  StartTime: "2026-11-26T15:15:00Z",
  StatusId: 1,
  StatusText: "Scheduled",
  ScheduleStatus: "SCHEDULED",
};

describe("IBU parsing", () => {
  it("normalizes a scheduled race", () => {
    expect(snapshot(scheduled)).toEqual({
      id: "BT2627SWRLCP01SMIN",
      category: "SM",
      name: "Men's 20km Individual",
      startTime: "2026-11-26T15:15:00.000Z",
      status: "scheduled",
    });
  });

  it("treats a finished race and a cancelled one", () => {
    expect(snapshot({ ...scheduled, StatusId: 11, StatusText: "Final", ScheduleStatus: "FINISHED" }).status).toBe("finished");
    expect(snapshot({ ...scheduled, StatusText: "Cancelled", ScheduleStatus: "CANCELLED" }).status).toBe("cancelled");
  });

  it("computes the season id with a July 1st switch", () => {
    expect(seasonId(new Date("2026-10-19T00:00:00Z"))).toBe("2627");
    expect(seasonId(new Date("2027-03-01T00:00:00Z"))).toBe("2627");
    expect(seasonId(new Date("2027-07-01T00:00:00Z"))).toBe("2728");
  });

  it("watches an event from two days before to one day after", () => {
    const event = { EventId: "BT2627SWRLCP01", StartDate: "2026-11-23T12:00:00Z", EndDate: "2026-11-29T12:00:00Z" };
    expect(activeEvents([event], Date.parse("2026-11-20T12:00:00Z"))).toEqual([]);
    expect(activeEvents([event], Date.parse("2026-11-21T12:00:00Z"))).toEqual([event]);
    expect(activeEvents([event], Date.parse("2026-11-30T13:00:00Z"))).toEqual([]);
  });
});

describe("change detection", () => {
  const base: RaceSnapshot = snapshot(scheduled);

  it("never alerts on a race seen for the first time", () => {
    expect(detectChange(undefined, { ...base, status: "cancelled" })).toBeUndefined();
  });

  it("alerts once on cancellation", () => {
    const cancelled = { ...base, status: "cancelled" as const };
    expect(detectChange(base, cancelled)?.kind).toBe("cancelled");
    expect(detectChange(cancelled, cancelled)).toBeUndefined();
  });

  it("alerts on a start time shift of one minute or more", () => {
    expect(detectChange(base, { ...base, startTime: "2026-11-26T15:45:00.000Z" })?.kind).toBe("rescheduled");
    expect(detectChange(base, { ...base, startTime: "2026-11-26T15:15:30.000Z" })).toBeUndefined();
    expect(detectChange(base, { ...base, status: "finished", startTime: "2026-11-26T16:00:00.000Z" })).toBeUndefined();
  });
});

describe("device registration", () => {
  const token = "a".repeat(64);
  const body = { environment: "production", categories: ["SM", "SW"], cancellation: true, rescheduling: false, locale: "fr-FR", timeZone: "Europe/Paris" };

  it("accepts a valid registration", () => {
    expect(parseRegistration(token.toUpperCase(), body)).toMatchObject({ token, categories: ["SM", "SW"] });
  });

  it("rejects bad input", () => {
    expect(parseRegistration("xyz", body)).toBe("invalid device token");
    expect(parseRegistration(token, { ...body, environment: "dev" })).toBe("invalid environment");
    expect(parseRegistration(token, { ...body, categories: ["XX"] })).toBe("invalid categories");
  });
});

describe("APNs", () => {
  it("builds a localized payload resolved on the device", () => {
    const payload = buildPayload({
      kind: "rescheduled",
      raceId: "BT2627SWRLCP01SMIN",
      raceName: "Men's 20km Individual",
      startTime: "2026-11-26T15:45:00.000Z",
      locale: "fr-FR",
      timeZone: "Europe/Paris",
    });
    expect(payload.aps.alert).toEqual({
      "title-loc-key": "race.SMIN",
      "loc-key": "push.rescheduled",
      "loc-args": ["jeudi", "16:45"],
    });
    // A whole event cancelled stacks as one group of alerts.
    expect(payload.aps["thread-id"]).toBe("BT2627SWRLCP01");
    expect(new TextEncoder().encode(JSON.stringify(payload)).length).toBeLessThan(4096);
  });

  it("names a race of a kind the app doesn't know with the IBU's name", () => {
    const payload = buildPayload({
      kind: "cancelled",
      raceId: "BT2627SWRLCP01SMXX",
      raceName: "Men's Super Sprint",
      startTime: "2026-11-26T15:45:00.000Z",
      locale: "fr-FR",
      timeZone: "Europe/Paris",
    });
    expect(payload.aps.alert).toEqual({ title: "Men's Super Sprint", "loc-key": "push.cancelled" });
  });

  it("falls back to UTC on an unknown time zone", () => {
    expect(formatStart({ startTime: "2026-11-26T15:45:00.000Z", locale: "en", timeZone: "Nowhere/City" })).toEqual({
      day: "Thursday",
      time: "3:45 PM UTC",
    });
  });

  it("names the day in the device's time zone", () => {
    expect(formatStart({ startTime: "2026-11-26T23:30:00.000Z", locale: "en", timeZone: "Europe/Paris" })).toEqual({
      day: "Friday",
      time: "12:30 AM",
    });
  });

  it("signs a verifiable ES256 token", async () => {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`;
    const jwt = await makeProviderToken({ pem, keyId: "ABC123DEFG", teamId: "DEF123GHIJ" }, 1437179036);
    const [header, claims, signature] = jwt.split(".") as [string, string, string];
    const decode = (part: string) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({ alg: "ES256", kid: "ABC123DEFG" });
    expect(JSON.parse(new TextDecoder().decode(decode(claims)))).toEqual({ iss: "DEF123GHIJ", iat: 1437179036 });
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });

  it("classifies APNs responses", () => {
    expect(classify(410, "Unregistered").kind).toBe("unregistered");
    expect(classify(400, "BadDeviceToken").kind).toBe("unregistered");
    expect(classify(403, "ExpiredProviderToken").kind).toBe("expiredProviderToken");
    expect(classify(403, "InvalidProviderToken").kind).toBe("expiredProviderToken");
    expect(classify(429, "TooManyRequests").kind).toBe("retry");
    expect(classify(400, "BadTopic").kind).toBe("failed");
  });
});
