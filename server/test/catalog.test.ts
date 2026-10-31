import JSON5 from "json5";
import { describe, expect, it } from "vite-plus/test";
import projectText from "../../Biathlon.xcodeproj/project.xcproj?raw";
import raceKinds from "../../Packages/BiathlonKit/Tests/BiathlonKitTests/Fixtures/race-kinds.json";
import catalogText from "../../Shared/Localizable.xcstrings?raw";
import { LOC_KEYS, RACE_KINDS, raceTitleKey } from "../src/payload";

type StringUnit = { state?: string; value?: string };
type Localization = { stringUnit?: StringUnit; variations?: { plural?: Record<string, { stringUnit?: StringUnit }> } };
type Entry = { extractionState?: string; shouldTranslate?: boolean; localizations?: Record<string, Localization> };

const catalog: { sourceLanguage: string; strings: Record<string, Entry> } = JSON.parse(catalogText);

// The Xcode project file is JSON5 (apple/xcode-project-format).
const project: { localizations: { development: string; supported?: string[] } } = JSON5.parse(projectText);

// The languages the app ships: the project's development and supported languages,
// as Xcode lists them once a language is added under Project > Info > Localizations.
const languages = [project.localizations.development, ...(project.localizations.supported ?? [])].filter(
  (language) => language !== "Base",
);

const isTranslated = (localization: Localization | undefined) => {
  const units = localization?.variations?.plural
    ? Object.values(localization.variations.plural).map((variation) => variation.stringUnit)
    : [localization?.stringUnit];
  return units.every((unit) => unit?.state === "translated" && !!unit.value);
};

describe("app String Catalog", () => {
  it("is registered in the Xcode project with every app language", () => {
    expect(languages).toEqual(expect.arrayContaining([catalog.sourceLanguage, "fr", "de"]));
  });

  // A string extracted from code reads as its own key in the source language;
  // a manual key needs a value there too.
  for (const [key, entry] of Object.entries(catalog.strings).filter(([, entry]) => entry.shouldTranslate !== false)) {
    const required =
      entry.extractionState === "manual"
        ? languages
        : languages.filter((language) => language !== catalog.sourceLanguage);
    it(`translates "${key}" in ${required.join(", ")}`, () => {
      expect(required.filter((language) => !isTranslated(entry.localizations?.[language]))).toEqual([]);
    });
  }

  // APNs resolves loc-keys from the app's Localizable table.
  for (const key of [...Object.values(LOC_KEYS), ...RACE_KINDS.map((kind) => raceTitleKey(`BT2627SWRLCP01${kind}`))]) {
    it(`holds the push key ${key}`, () => {
      expect(catalog.strings[key!]?.extractionState).toBe("manual");
    });
  }

  // The app's BiathlonKit tests check its RaceKind against the same list.
  it("names every race kind the app knows", () => {
    expect([...RACE_KINDS].sort()).toEqual(raceKinds);
    expect(
      Object.keys(catalog.strings)
        .filter((key) => key.startsWith("race."))
        .sort(),
    ).toEqual(raceKinds.map((kind) => `race.${kind}`));
  });
});
