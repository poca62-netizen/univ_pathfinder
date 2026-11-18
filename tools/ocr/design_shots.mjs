// 디자인 점검용 스크린샷(체험 모드 빌드 build/web, DB·외부 호출 없음).
// 사용: node tools/ocr/design_shots.mjs <출력 폴더> [이름표]
import { chromium } from 'playwright-core';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(root, '../../build/web');
const out = path.resolve(process.argv[2] ?? path.join(root, 'test-output/design'));
const tag = process.argv[3] ?? 'now';
await mkdir(out, { recursive: true });
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
const screens = ['상담 자료', '대학 탐색', '진학 컨설팅 리포트', '자료 출처'];
let browser;
try {
  browser = await chromium.launch({ executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true });
  for (const [label, viewport] of [['desktop', { width: 1280, height: 900 }], ['mobile', { width: 390, height: 844 }]]) {
    const page = await browser.newPage({ viewport, deviceScaleFactor: label === 'mobile' ? 2 : 1 });
    await page.goto(base);
    await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
    await page.locator('flt-semantics-placeholder').evaluate((el) => el.click());
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(out, `${tag}-${label}-home.png`) });
    for (const name of screens) {
      try {
        await page.getByText(name, { exact: true }).first().click({ timeout: 8000 });
        await page.waitForTimeout(1500);
        await page.screenshot({ path: path.join(out, `${tag}-${label}-${name.replace(/\s/g, '')}.png`) });
        await page.goBack().catch(() => {});
        await page.keyboard.press('Escape').catch(() => {});
        const back = page.getByRole('button', { name: /Back|뒤로/ });
        if (await back.count()) await back.first().click().catch(() => {});
        await page.waitForTimeout(800);
      } catch (e) { console.log(`skip ${label} ${name}: ${e.message.split('\n')[0]}`); }
    }
    await page.close();
  }
  console.log(`saved to ${out}`);
} finally {
  await browser?.close();
  await new Promise((r) => server.close(r));
}
