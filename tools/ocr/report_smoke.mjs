// Browser QA for the consulting report preview build (synthetic student; no DB, no network besides localhost).
// Build first: flutter build web --no-pub -t tools/preview_report_web.dart -o build/report-preview
// Run: node tools/ocr/report_smoke.mjs   (from the project root)
import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve('build/report-preview');
const out = 'tools/ocr/test-output/design';
await mkdir(out, {recursive: true});
const types = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.otf': 'font/otf', '.ttf': 'font/ttf'};
const server = createServer(async (req, res) => {
  try {
    const file = path.resolve(root, '.' + new URL(req.url, 'http://local').pathname.replace(/\/$/, '/index.html'));
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
    res.setHeader('Content-Type', types[path.extname(file)] ?? 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true});
  for (const [name, width, height] of [['desktop', 1440, 1100], ['mobile', 390, 844]]) {
    const context = await browser.newContext({viewport: {width, height}});
    await context.grantPermissions(['clipboard-read', 'clipboard-write'], {origin: url});
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => { if (m.type() === 'error' && /overflowed|Exception|assertion|Unable to load asset/i.test(m.text())) errors.push(m.text()); });
    const dump = async () => console.log((await page.locator('body').innerText()).slice(0, 4000));
    async function reveal(locator) {
      for (let i = 0; i < 60; i++) {
        const box = await locator.boundingBox({timeout: 500}).catch(() => null);
        // 화면보다 큰 노드(카드 전체가 한 노드)는 위쪽이 보이면 된다.
        if (box && box.y > 65 && (box.y + box.height < height - 20 || (box.height > height - 120 && box.y < height / 2))) return;
        await page.mouse.move(width / 2, height / 2);
        await page.mouse.wheel(0, box && box.y < 65 ? -350 : 350);
        await page.waitForTimeout(120);
      }
      await dump();
      throw Error('Cannot reveal ' + locator);
    }
    async function click(locator) { await reveal(locator); await locator.click(); await page.waitForTimeout(300); }

    await page.goto(url);
    await page.locator('flt-semantics-placeholder').waitFor({state: 'attached', timeout: 60000});
    await page.locator('flt-semantics-placeholder').evaluate((e) => e.click());

    const input = page.getByRole('textbox', {name: '관심 학과·분야', exact: true});
    await input.waitFor({timeout: 30000}).catch(async (e) => { await dump(); throw e; });
    await input.click();
    await page.waitForFunction(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName));
    await page.keyboard.insertText('컴퓨터');
    await page.keyboard.press('Tab');
    // ChoiceChip은 텍스트가 아니라 선택 가능한 컨트롤로 노출된다.
    const chip = (n) => page.getByRole('button', {name: n, exact: true})
      .or(page.getByRole('checkbox', {name: n, exact: true}))
      .or(page.getByRole('radio', {name: n, exact: true})).first();
    await click(chip('자연'));
    const started = Date.now();
    await click(page.getByRole('button', {name: '리포트 만들기'}));
    await page.getByText(/^내 성적 기준/).waitFor({timeout: 30000}).catch(async (e) => { await dump(); throw e; });
    const elapsed = Date.now() - started;
    const text = await page.locator('body').innerText();
    assert.match(text, /내신: .*학기 종합/);
    assert.match(text, /모의고사: 2026년 2학년 9월/);
    assert.match(text, /연결된 생기부 근거 2건/);
    // 목록은 화면에 들어올 때 그려진다. 카드 전체가 한 노드라 위치 대신 텍스트가 나타날 때까지 스크롤한다.
    async function scrollUntil(re) {
      for (let i = 0; i < 80; i++) {
        const t = await page.locator('body').innerText();
        if (re.test(t)) return t;
        await page.mouse.move(width / 2, height / 2);
        await page.mouse.wheel(0, 250);
        await page.waitForTimeout(150);
      }
      await dump();
      throw Error('Not found while scrolling: ' + re);
    }
    const portfolio = await scrollUntil(/지원 조합 예시[\s\S]*수시 6장[\s\S]*(상향|적정|안정) /);
    assert.match(portfolio, /정시 가·나·다군/);
    // 맨 위부터 화면 높이의 80%씩 내려가며 세 장을 찍는다(성적 기준 → 지원 조합 → 전형별 목록).
    await page.mouse.move(width / 2, height / 2);
    await page.mouse.wheel(0, -100000);
    await page.waitForTimeout(300);
    for (let i = 1; i <= 3; i++) {
      await page.screenshot({path: `${out}/report-${name}-${i}.png`});
      await page.mouse.wheel(0, Math.round(height * 0.8));
      await page.waitForTimeout(300);
    }

    // 인쇄: 새 창에 인쇄용 문서가 열린다(헤드리스에서는 인쇄 창 자체는 뜨지 않음).
    await page.mouse.wheel(0, -100000);
    await page.waitForTimeout(300);
    const [popup] = await Promise.all([
      context.waitForEvent('page', {timeout: 10000}),
      page.getByRole('button', {name: '인쇄·PDF 저장'}).click(),
    ]);
    await popup.waitForLoadState();
    assert.equal(await popup.locator('h1').innerText().then((t) => t.startsWith('진학 컨설팅 리포트')), true);
    assert.ok((await popup.locator('h2').allInnerTexts()).some((t) => t.startsWith('[지원 조합 예시')));
    if (name === 'desktop') {
      await popup.pdf({path: `${out}/report-print.pdf`, format: 'A4'});
      await popup.setViewportSize({width: 900, height: 1200});
      await popup.screenshot({path: `${out}/report-print.png`});
    }
    await popup.close();

    // 복사: 생기부 원문은 들어가지 않는다.
    await page.getByRole('button', {name: '리포트 복사'}).click();
    await page.getByText(/리포트를 복사했습니다/).last().waitFor({timeout: 5000});
    const copied = await page.evaluate(() => navigator.clipboard.readText());
    assert.match(copied, /\[학생부교과 \d+건\]/);
    assert.ok(!copied.includes('정렬 알고리즘'), 'copied text must not include record text');

    assert.deepEqual(errors, []);
    console.log(`PASS ${name}: report in ${elapsed}ms, portfolio/sections shown, print window opened, copy excludes record text, no errors`);
    await context.close();
  }
} finally {
  await browser?.close();
  await new Promise((r) => server.close(r));
}
