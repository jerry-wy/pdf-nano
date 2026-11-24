import { cp, mkdir } from 'node:fs/promises';
// Serve PDF.js font/CMap/WASM assets locally instead of fetching document resources from a CDN.
await mkdir('public/pdfjs', { recursive: true });
for (const directory of ['cmaps', 'standard_fonts', 'wasm']) {
  await cp(`node_modules/pdfjs-dist/${directory}`, `public/pdfjs/${directory}`, { recursive: true });
}
