import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const root = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(root, '../../web');
const output = path.join(root, 'test-output');
let browser, server, base, image, pdf, scanned, rotated, largePdf;
const external = [];
before(async () => {
  await mkdir(output, { recursive: true });
  server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://local');
      if (url.pathname === '/large-test.pdf') { res.setHeader('Content-Type','application/pdf'); return res.end(largePdf); }
      if (url.pathname === '/test') {
        res.setHeader('Content-Type', 'text/html');
        return res.end('<!doctype html><meta charset="UTF-8"><script type="module" src="/grade_ocr.js"></script><body>OCR test</body>');
      }
      const file = path.resolve(web, '.' + decodeURIComponent(url.pathname));
      if (!file.startsWith(web + path.sep)) { res.writeHead(403); return res.end(); }
      const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.bcmap': 'application/octet-stream' };
      res.setHeader('Content-Type', types[path.extname(file)] ?? 'application/octet-stream');
      res.end(await readFile(file));
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 2 });
  await page.setContent(`<!doctype html><meta charset="UTF-8"><style>
    body { font: 22px 'Malgun Gothic', sans-serif; padding: 20px; background: white; }
    table {border-collapse:collapse;width:1050px;table-layout:fixed;font-size:22px;}
    th,td { border:1px solid #777; padding:18px 8px;text-align:center; }
    th:first-child {width:230px;}
    h1{font-size:26px;}</style>
    <h1>가상 성적표 · 실제 학생 자료 아님</h1><p>2학년 1학기 · 5등급제</p>
    <table><thead><tr><th>과목</th><th>학점</th><th>원점수</th><th>과목평균</th><th>성취도</th><th>석차등급</th></tr></thead>
    <tbody><tr><td>국어</td><td>3</td><td>88</td><td>75.5</td><td>A</td><td>2</td></tr>
    <tr><td>수학</td><td>4</td><td>92</td><td>78.2</td><td>A</td><td>1</td></tr></tbody></table>`);
  await page.evaluate(() => document.fonts.ready);
  image = await page.screenshot({ fullPage: true });
  rotated = Buffer.from(await page.evaluate(async (bytes) => {
    const bitmap = await createImageBitmap(new Blob([Uint8Array.from(bytes)], { type: 'image/png' }));
    const canvas = document.createElement('canvas');
    canvas.width = bitmap.height; canvas.height = bitmap.width;
    const ctx = canvas.getContext('2d');
    ctx.translate(canvas.width / 2, canvas.height / 2); ctx.rotate(Math.PI / 2);
    ctx.drawImage(bitmap, -bitmap.width / 2, -bitmap.height / 2);
    const blob = await new Promise((r) => canvas.toBlob(r, 'image/png'));
    bitmap.close();
    return [...new Uint8Array(await blob.arrayBuffer())];
  }, [...image]));
  pdf = await page.pdf({ width: '1200px', height: '800px', printBackground: true });
  const startXref=pdf.lastIndexOf(Buffer.from('startxref'));
  assert.ok(startXref>0);
  largePdf=Buffer.concat([pdf.subarray(0,startXref),Buffer.from('%'+ 'x'.repeat(8*1024*1024)+'\n'),pdf.subarray(startXref)]);
  await page.setContent(`<img style="width:1100px" src="data:image/png;base64,${image.toString('base64')}">`);
  await page.locator('img').waitFor();
  await page.evaluate(async () => { await document.querySelector('img').decode(); });
  scanned = await page.pdf({ width: '1200px', height: '850px', printBackground: true });
  for (const [name, bytes] of [['sample.pdf', pdf], ['sample.png', image], ['sample-scanned.pdf', scanned]]) {
    await writeFile(path.join(output, name), bytes);
  }
  await mkdir(path.join(web, 'samples'), { recursive: true });
  await writeFile(path.join(web, 'samples/sample_grades.pdf'), pdf);
  await page.close();
}, { timeout: 60000 });

after(async () => { await browser?.close(); if (server) await new Promise((r) => server.close(r)); });

async function recognize(bytes, mime, force = false, enhanced = false) {
  const page = await browser.newPage();
  await page.route('**/*', async (route) => {
    if (!route.request().url().startsWith(base)) { external.push(route.request().url()); return route.abort(); }
    return route.continue();
  });
  try {
    await page.goto(base + '/test');
    await page.waitForFunction(() => typeof window.univGradeOcrExtract === 'function');
    const result = await page.evaluate(async ({ data, mime, force, enhanced }) => {
      return JSON.parse(await window.univGradeOcrExtract(Uint8Array.from(data), mime, force, () => {}, enhanced));
    }, { data: [...bytes], mime, force, enhanced });
    return result;
  } finally { await page.close(); }
}

test('PDF.js extracts Korean table text and positional words locally', { timeout: 60000 }, async () => {
  const result = await recognize(pdf, 'application/pdf');
  assert.equal(result.pages[0].method, 'pdf-text');
  assert.match(result.pages[0].text, /국어/);
  assert.match(result.pages[0].text, /88/);
  assert.ok(result.pages[0].lines.length >= 3);
  await writeFile(path.join(output, 'pdf-extraction.json'), JSON.stringify(result));
});
test('Tesseract recognizes Korean image table using local workers/models', { timeout: 120000 }, async () => {
  const result = await recognize(image, 'image/png');
  assert.equal(result.pages[0].method, 'ocr');
  assert.match(result.pages[0].text, /국어|수학/);
  assert.ok(result.pages[0].lines.some((l) => /과목/.test(l.text)), 'table header must be recognized');
  assert.match(result.pages[0].text, /88|92/);
  assert.ok(result.pages[0].lines.some((l) => l.words.length >= 3));
  await writeFile(path.join(output, 'image-extraction.json'), JSON.stringify(result));
});
test('scanned PDF falls back to OCR page by page', { timeout: 120000 }, async () => {
  const result = await recognize(scanned, 'application/pdf');
  assert.equal(result.pages[0].method, 'ocr');
  assert.match(result.pages[0].text, /88|92/);
  await writeFile(path.join(output, 'scanned-extraction.json'), JSON.stringify(result));
});
test('file signature mismatch fails before processing', async () => {
  await assert.rejects(recognize(Buffer.from('not a pdf'), 'application/pdf'), /INVALID_FILE/);
});
test('enhanced OCR recovers a sideways photo without uploading it', { timeout: 120000 }, async () => {
  const result = await recognize(rotated, 'image/png', false, true);
  assert.equal(result.pages[0].quality.tableFound, true);
  assert.match(result.pages[0].text, /국어|수학/);
  assert.match(result.pages[0].text, /88|92/);
  assert.ok([90, 270].includes(result.pages[0].rotation));
});
test('8MB PDF is read locally while oversized images and PDFs are rejected', {timeout:60000}, async()=>{
  const page=await browser.newPage();
  await page.route('**/*',route=>{if(!route.request().url().startsWith(base)){external.push(route.request().url());return route.abort();}return route.continue();});
  try {
    await page.goto(base+'/test');await page.waitForFunction(()=>typeof univGradeOcrExtract==='function');
    const result=await page.evaluate(async()=>{
      const bytes=new Uint8Array(await (await fetch('/large-test.pdf')).arrayBuffer());
      return JSON.parse(await univGradeOcrExtract(bytes,'application/pdf',false,()=>{},false));
    });
    assert.equal(result.pages[0].method,'pdf-text');assert.match(result.pages[0].text,/국어/);
    for(const [mime,length] of [['image/jpeg',5*1024*1024+1],['application/pdf',20*1024*1024+1]]){
      const error=await page.evaluate(async({mime,length})=>{try{await univGradeOcrExtract(new Uint8Array(length),mime,false,()=>{},false);return null;}catch(e){return e.message;}},{mime,length});
      assert.equal(error,'INVALID_SIZE');
    }
  }finally{await page.close();}
});
test('recognition makes no request to external hosts', () => assert.deepEqual(external, []));
