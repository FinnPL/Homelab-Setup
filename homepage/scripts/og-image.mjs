import sharp from "sharp";
import opentype from "opentype.js";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const out = fileURLToPath(new URL("../public/og.png", import.meta.url));
const portrait = fileURLToPath(new URL("../public/portrait.jpg", import.meta.url));
const font = (f) => opentype.parse(readFileSync(new URL(`./fonts/${f}`, import.meta.url)));

// Text is drawn as paths from bundled fonts: no system font lookup, so macOS and CI render the same.
const sans = font("texgyreheros-regular.otf");
const sansBold = font("texgyreheros-bold.otf");
const mono = font("DejaVuSansMono.ttf");

function text(f, s, x, y, size, spacing, fill) {
  const scale = size / f.unitsPerEm;
  const glyphs = f.stringToGlyphs(s);
  let d = "";
  glyphs.forEach((g, i) => {
    d += g.getPath(x, y, size).toPathData(2);
    x += g.advanceWidth * scale + spacing;
    if (glyphs[i + 1]) x += f.getKerningValue(g, glyphs[i + 1]) * scale;
  });
  return `<path d="${d}" fill="${fill}"/>`;
}

const W = 1200, H = 630, D = 300, X = 760, Y = (H - D) / 2;

const bg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="#fbfaf8"/>
  <rect x="0" y="0" width="${W}" height="10" fill="#2f4f8f"/>
  ${text(sansBold, "Finn Paul Lippok", 90, 292, 72, -2.2, "#17191d")}
  ${text(sans, "Computer science student, RWTH Aachen", 90, 348, 31, 0, "#4a4f57")}
  ${text(mono, "LIPPOK.DEV", 90, 548, 25, 2, "#797f89")}
</svg>`;

const mask = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${D}" height="${D}"><circle cx="${D / 2}" cy="${D / 2}" r="${D / 2}" fill="#fff"/></svg>`,
);

const face = await sharp(portrait)
  .resize(D, D, { fit: "cover", position: "top" })
  .composite([{ input: mask, blend: "dest-in" }])
  .png()
  .toBuffer();

await sharp(Buffer.from(bg))
  .composite([{ input: face, left: X, top: Y }])
  .png()
  .toFile(out);

console.log("rendered og.png");
