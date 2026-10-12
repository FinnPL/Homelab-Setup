export const IDENTITY = {
  name: "Finn Paul Lippok",
  shortName: "Finn Lippok",
  headline: "Computer science student at RWTH Aachen",
  email: "contact@lippok.eu",
  privacyEmail: "dsgvo@lippok.eu",
  site: "https://lippok.dev",
  photo: "/portrait.jpg",
};

export const PROFILES: { label: string; text: string; href: string }[] = [
  { label: "GitHub", text: "FinnPL", href: "https://github.com/FinnPL" },
  { label: "LinkedIn", text: "finn-paul-lippok", href: "https://www.linkedin.com/in/finn-paul-lippok" },
];

const IDENTITY_PAGES: string[] = [
  "https://www.badische-zeitung.de/person/Finn+Lippok",
  "https://www.inaturalist.org/people/finnpl",
];

export const AWARDS: { name: string; body: string }[] = [
  { name: "GI-Abiturpreis", body: "Gesellschaft für Informatik" },
  { name: "DPG-Abiturpreis", body: "Deutsche Physikalische Gesellschaft" },
  { name: "VfS-Abiturpreis", body: "Verein für Socialpolitik und Dr. Hans Riegel-Stiftung" },
  { name: "Vector-Stiftung-Preis", body: "Best performance in the technical computer science profile" },
];

export function personJsonLd() {
  return {
    "@context": "https://schema.org",
    "@type": "Person",
    "@id": `${IDENTITY.site}/#person`,
    name: IDENTITY.name,
    alternateName: IDENTITY.shortName,
    url: IDENTITY.site,
    image: new URL(IDENTITY.photo, IDENTITY.site).href,
    sameAs: [...PROFILES.map((p) => p.href), ...IDENTITY_PAGES],
  };
}
