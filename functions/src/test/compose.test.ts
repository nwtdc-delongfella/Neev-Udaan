import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";
import { brandColorsFromPalette, contrastRatio, extractPalette } from "../lib/colors";
import { composePost, wrap } from "../lib/compose";
import { FORMATS, type Layout } from "../lib/types";

const OUT = path.resolve("test-output");

// A sample logo: transparent background, teal shape with an orange accent.
const logoSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">
  <circle cx="200" cy="200" r="170" fill="#0E7C86"/>
  <path d="M120 270 L200 110 L280 270 Z" fill="#F28C28"/>
  <circle cx="200" cy="225" r="35" fill="#FFFFFF"/></svg>`;

// Stand-in for an AI background: soft gradient "photo".
const bgSvg = (w: number, h: number) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}">
  <defs><radialGradient id="r" cx="0.35" cy="0.35" r="0.9">
  <stop offset="0" stop-color="#E8F6F7"/><stop offset="0.6" stop-color="#9FD3D8"/><stop offset="1" stop-color="#3B8E96"/></radialGradient></defs>
  <rect width="100%" height="100%" fill="url(#r)"/><circle cx="${w * 0.75}" cy="${h * 0.3}" r="${w * 0.15}" fill="#FFFFFF" opacity="0.5"/></svg>`;

test("extracts brand colors from a logo", async () => {
  const logo = await sharp(Buffer.from(logoSvg)).png().toBuffer();
  const palette = await extractPalette(logo);
  assert.ok(palette.length >= 2, "at least two colors");
  const colors = brandColorsFromPalette(palette);
  const near = (hex: string, target: string) => {
    const a = parseInt(hex.slice(1), 16), b = parseInt(target.slice(1), 16);
    return Math.abs((a >> 16) - (b >> 16)) < 25 && Math.abs(((a >> 8) & 255) - ((b >> 8) & 255)) < 25 && Math.abs((a & 255) - (b & 255)) < 25;
  };
  assert.ok(near(colors.primary, "#0E7C86"), `primary ${colors.primary} should be the teal`);
  assert.ok(palette.some((p) => near(p.hex, "#F28C28")), "orange found");
  assert.ok(contrastRatio(colors.primary, colors.onPrimary) >= 4.5, "readable text color");
  console.log("palette", palette, "roles", colors);
});

test("wraps headline text", () => {
  const lines = wrap("Healthy smiles start with small daily habits", 80, 900);
  assert.ok(lines.length >= 2 && lines.length <= 3);
});

test("composes posts in every layout and format", async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const logo = await sharp(Buffer.from(logoSvg)).png().toBuffer();
  const colors = brandColorsFromPalette(await extractPalette(logo));
  const cases: [Layout, keyof typeof FORMATS][] = [["band", "square"], ["top", "portrait"], ["minimal", "landscape"], ["band", "landscape"]];
  for (const [layout, format] of cases) {
    const { width, height } = FORMATS[format];
    const background = await sharp(Buffer.from(bgSvg(1024, 1024))).png().toBuffer();
    const png = await composePost({
      background, logo, width, height, colors, layout,
      headline: "Healthy smiles start with small daily habits",
      subline: "Book your family check-up this month",
      footer: "www.example.com  •  +91 98765 43210",
    });
    const meta = await sharp(png).metadata();
    assert.equal(meta.width, width);
    assert.equal(meta.height, height);
    fs.writeFileSync(path.join(OUT, `${layout}-${format}.png`), png);
  }
});
