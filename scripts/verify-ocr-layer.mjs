import fs from 'node:fs';
import assert from 'node:assert/strict';
const root = process.cwd();
const output = process.argv[2];
const { createCanvas, DOMMatrix, ImageData, Path2D } = await import(`${root}/node_modules/@napi-rs/canvas/index.js`);
Object.assign(globalThis, {DOMMatrix, ImageData, Path2D});
const { getDocument } = await import(`${root}/node_modules/pdfjs-dist/legacy/build/pdf.mjs`);
async function load(path) {
  return getDocument({data: new Uint8Array(fs.readFileSync(path)), standardFontDataUrl: `${root}/node_modules/pdfjs-dist/standard_fonts/`}).promise;
}
async function pixels(doc) {
  const page = await doc.getPage(1);
  const viewport = page.getViewport({scale: 1});
  const canvas = createCanvas(viewport.width, viewport.height);
  const ctx = canvas.getContext('2d');
  await page.render({canvasContext: ctx, viewport}).promise;
  return ctx.getImageData(0,0,canvas.width,canvas.height).data;
}
const original = await load(`${output}/original.pdf`);
const originalPixels = await pixels(original);
for (const rotation of [0,90,180,270,'cropped-90']) {
  const doc = await load(`${output}/ocr-${rotation}.pdf`);
  const page = await doc.getPage(1);
  const content = await page.getTextContent();
  const text = content.items.map(x=>x.str).join(' ');
  assert(text.includes('Selectable OCR text'), `Missing OCR text for rotation ${rotation}: ${text}`);
  assert(text.includes('Second line'), 'Missing second line');
  // PDF.js extracts glyph CMap text (including CJK compatibility radicals).
  // Exact recognized Unicode is also preserved in the PDF's ActualText tags.
  assert(text.normalize('NFKC').replace(/\s/g, '').includes('日本語'), `Unicode OCR glyphs were lost: ${text}`);
  const exactUnicode = Buffer.concat([Buffer.from([0xfe, 0xff]), Buffer.from('日本語', 'utf16le').swap16()]);
  assert(fs.readFileSync(`${output}/ocr-${rotation}.pdf`).includes(exactUnicode), 'Original Unicode missing from ActualText tags');
  const resultPixels = await pixels(doc);
  assert.deepEqual(resultPixels, originalPixels, `OCR changed page appearance at rotation ${rotation}`);
  const item = content.items.find(x=>x.str.includes('Selectable'));
  const origin = item.transform.slice(4);
  assert(origin.every(Number.isFinite), 'Invalid OCR geometry');
  console.log(`PASS: ${rotation}° text extracts correctly; page pixels unchanged; origin ${origin.map(x=>x.toFixed(1))}`);
  await doc.destroy();
}
await original.destroy();
