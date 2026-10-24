/**
 * Who shows World Cup races on TV in France, the United Kingdom and Germany, by period.
 * No API carries it: the list is kept by hand from the broadcasters' and the IBU's own
 * announcements, and a fix ships with a deploy, without a new version of the app.
 *
 * A period runs from `from` (included) to `until` (excluded), in whole UTC days. `country`
 * is an ISO 3166 code, which the app names in its own language. `url` is where the
 * broadcaster streams live: the IBU's "Where to watch" pages link the same ones.
 */
export interface TVCoverage {
  country: string;
  broadcaster: string;
  url: string;
  from: string;
  until: string;
}

const SEASON_2627 = { from: "2026-11-23T00:00:00Z", until: "2027-03-22T00:00:00Z" };

/** The weeks of the 2026-27 events, from Monday to the Monday after (Pokljuka starts on a Thursday). */
const WEEKS_2627 = {
  kontiolahti: { from: "2026-11-23T00:00:00Z", until: "2026-11-30T00:00:00Z" },
  hochfilzen: { from: "2026-11-30T00:00:00Z", until: "2026-12-07T00:00:00Z" },
  leGrandBornand: { from: "2026-12-07T00:00:00Z", until: "2026-12-14T00:00:00Z" },
  pokljuka: { from: "2026-12-31T00:00:00Z", until: "2027-01-04T00:00:00Z" },
  ruhpolding: { from: "2027-01-04T00:00:00Z", until: "2027-01-11T00:00:00Z" },
  antholz: { from: "2027-01-11T00:00:00Z", until: "2027-01-18T00:00:00Z" },
  noveMesto: { from: "2027-01-18T00:00:00Z", until: "2027-01-25T00:00:00Z" },
  // ZDF announces the Championships' second part from February 17.
  otepaaFirstPart: { from: "2027-02-07T00:00:00Z", until: "2027-02-17T00:00:00Z" },
  otepaaSecondPart: { from: "2027-02-17T00:00:00Z", until: "2027-02-22T00:00:00Z" },
  oberhof: { from: "2027-03-01T00:00:00Z", until: "2027-03-08T00:00:00Z" },
  ostersund: { from: "2027-03-08T00:00:00Z", until: "2027-03-15T00:00:00Z" },
  oslo: { from: "2027-03-15T00:00:00Z", until: "2027-03-22T00:00:00Z" },
};

const ARD = { country: "DE", broadcaster: "ARD", url: "https://www.ardmediathek.de/live" };
const ZDF = {
  country: "DE",
  broadcaster: "ZDF",
  url: "https://www.zdf.de/wintersport-biathlon-ski-alpin-skispringen-highlights-livestream-100",
};

export const TV_COVERAGE: readonly TVCoverage[] = [
  // Every World Cup and Championships race, free-to-air, until 2030:
  // https://www.cbnews.fr/node/89555 (December 2024).
  { country: "FR", broadcaster: "La Chaîne L'Équipe", url: "https://www.lequipe.fr/tv/", ...SEASON_2627 },
  // "TNT Sports is the broadcaster in the UK and Ireland", Kontiolahti included:
  // https://media.wbdsports.com/post/winter-sports-season-begins-with-enhanced-coverage-in-europe-on- (October 22, 2026).
  { country: "GB", broadcaster: "TNT Sports", url: "https://www.tntsports.co.uk/biathlon/", ...SEASON_2627 },
  // ZDF's weeks, "im Wechsel mit der ARD":
  // https://presseportal.zdf.de/pressemappe/zdfsportstudio-live-wintersport-saison-20262027 (2026-27 press kit).
  // ARD hasn't published its own weeks yet: the others, until it does.
  { ...ARD, ...WEEKS_2627.kontiolahti },
  { ...ZDF, ...WEEKS_2627.hochfilzen },
  { ...ARD, ...WEEKS_2627.leGrandBornand },
  { ...ZDF, ...WEEKS_2627.pokljuka },
  { ...ARD, ...WEEKS_2627.ruhpolding },
  { ...ZDF, ...WEEKS_2627.antholz },
  { ...ARD, ...WEEKS_2627.noveMesto },
  { ...ARD, ...WEEKS_2627.otepaaFirstPart },
  { ...ZDF, ...WEEKS_2627.otepaaSecondPart },
  { ...ZDF, ...WEEKS_2627.oberhof },
  { ...ARD, ...WEEKS_2627.ostersund },
  { ...ZDF, ...WEEKS_2627.oslo },
];
