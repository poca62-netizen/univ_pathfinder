import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(root, '../../build/web');
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://local').pathname);
    const file = path.resolve(web, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!file.startsWith(web + path.sep)) { res.writeHead(403); return res.end(); }
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
    res.setHeader('Content-Type', types[path.extname(file)] ?? 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(base);
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
  await page.locator('flt-semantics-placeholder').evaluate((el) => el.click());
  await page.getByText('상담 자료', { exact: true }).click({ timeout: 30000 });
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(root, 'test-output/flutter-navigation.png') });
  await page.getByRole('button', { name: /^내신 성적표/ }).click({ timeout: 5000 });
  await page.getByRole('button', { name: '가상 PDF로 인식 시험 · 저장 안 됨', exact: true }).click();
  await page.getByRole('button', { name: '성적 추출 → 확인·수정', exact: true }).click();
  await page.getByText('가상 예시 파일입니다. DB 저장은 차단됩니다.', { exact: true }).waitFor({ timeout: 60000 });
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(root, 'test-output/flutter-import-preview.png'), fullPage: true });
  // Flutter's semantic textbox is a proxy; the native input gets its value on focus.
  await page.getByRole('textbox', { name: '과목명', exact: true }).first().click();
  await page.waitForFunction(() => document.activeElement?.value === '국어');
  await page.getByRole('textbox', { name: '원점수 0~100', exact: true }).first().click();
  await page.waitForFunction(() => /^88(?:\.0)?$/.test(document.activeElement?.value ?? ''));
  assert.ok(await page.getByRole('button', { name: '확인 후 저장', exact: true }).isDisabled());
  await page.screenshot({ path: path.join(root, 'test-output/flutter-import-preview.png'), fullPage: true });
  await writeFile(path.join(root, 'test-output/flutter-errors.json'), JSON.stringify(errors));
  assert.deepEqual(errors, []);
  console.log('PASS: built Flutter app → bundled PDF → real JS bridge → two grade drafts → demo DB save blocked; no page errors.');
} finally {
  await browser?.close();
  await new Promise((r) => server.close(r));
}
