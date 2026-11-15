// Explicit local reproduction; no DB writes, uploads, or raw text in stdout.
import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(root, '../../web');
const file = process.argv[2];
if (!file) throw new Error('Provide a local image path.');
const server = createServer(async (req, res) => {
  try {
    const route = new URL(req.url, 'http://local').pathname;
    if (route === '/') { res.setHeader('Content-Type', 'text/html'); return res.end('<script type="module" src="/grade_ocr.js"></script>'); }
    const target = path.resolve(web, '.' + route);
    if (!target.startsWith(web + path.sep)) { res.writeHead(403); return res.end(); }
    res.setHeader('Content-Type', ({ '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm' })[path.extname(target)] ?? 'application/octet-stream');
    res.end(await readFile(target));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
let browser;
try {
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage();
  const base = `http://127.0.0.1:${server.address().port}`;
  await page.route('**/*', (route) => route.request().url().startsWith(base) ? route.continue() : route.abort());
  await page.goto(base);
  await page.waitForFunction(() => typeof univGradeOcrExtract === 'function');
  const data = [...await readFile(file)];
  await page.evaluate(() => {
    window.univGradeOcrGridDiagnostics = (headers) => { window.ocrHeaderDiagnostics = headers; };
    window.univGradeOcrCellPreview = (url) => { window.ocrCellPreview ??= url; };
  });
  if (process.env.OCR_GRID_DEBUG) {
    const grids = await page.evaluate(async (data) => {
      const bitmap = await createImageBitmap(new Blob([Uint8Array.from(data)], { type: 'image/jpeg' }));
      const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height;
      canvas.getContext('2d').drawImage(bitmap, 0, 0);
      const { detectGrids } = await import('/grade_ocr.js');
      return detectGrids(canvas);
    }, data);
    console.log(JSON.stringify({ grids }));
  }
  const result = await page.evaluate(async (data) => JSON.parse(await univGradeOcrExtract(Uint8Array.from(data), 'image/jpeg', false, () => {}, true)), data);
  if (process.env.OCR_GRID_DEBUG) console.log(JSON.stringify({ headers: await page.evaluate(() => window.ocrHeaderDiagnostics) }));
  const preview = await page.evaluate(() => window.ocrCellPreview);
  if (preview) await writeFile(path.join(root, 'test-output/private-header.png'), Buffer.from(preview.split(',')[1], 'base64'));
  await mkdir(path.join(root, 'test-output'), { recursive: true });
  await writeFile(path.join(root, 'test-output/private-reproduction.json'), JSON.stringify(result));
  console.log(JSON.stringify(result.pages.map((p) => ({ method: p.method, quality: p.quality, rotation: p.rotation, lines: p.lines.length, characters: p.text.length }))));
} finally { await browser?.close(); await new Promise((r) => server.close(r)); }
