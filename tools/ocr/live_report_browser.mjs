// Live login-path check for the consulting report with a throwaway virtual account.
// Writes to the remote dev DB (virtual student only). Run only with the user's approval.
// Credentials, tokens and upstream responses are never printed. The account is deleted at the end.
// Build first: flutter build web --no-pub --dart-define-from-file=.env.dev.json -o build/dev-check
import {execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {chromium} from 'playwright-core';

const config = JSON.parse(fs.readFileSync('.env.dev.json', 'utf8').replace(/^\uFEFF/, ''));
const base = config.SUPABASE_URL;
const project = new URL(base).hostname.split('.')[0];
if (!/^[a-z]{20}$/.test(project)) throw Error('Invalid project');
const keys = JSON.parse(execFileSync('cmd.exe', ['/d', '/s', '/c', `npx supabase projects api-keys --remote=${project} --output json`], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}));
const key = keys.find((k) => k.name === 'service_role').api_key;
const admin = {apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json'};
const headers = {apikey: config.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json'};
const nickname = `test_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`;
const pin = String(1000 + Math.floor(Math.random() * 9000));
const uids = new Set();
const out = 'tools/ocr/test-output/design';
let stage = 'register virtual account';

function counts(uid) {
  if (!/^[0-9a-f-]{36}$/.test(uid) || !/^test_[0-9a-f]{12}$/.test(nickname)) throw Error('unsafe id');
  const sql = `select (select count(*) from auth.users where id='${uid}')::int as auth_user,` +
    `(select count(*) from public.grade_records where user_id='${uid}')::int as grade,` +
    `(select count(*) from public.mock_exam_records where user_id='${uid}')::int as mock_exam,` +
    `(select count(*) from public.school_record_evidence where user_id='${uid}')::int as evidence,` +
    `(select count(*) from public.nickname_accounts where nickname_key='${nickname}')::int as credential`;
  const file = `tools/ocr/test-output/live_report_${process.pid}.sql`;
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, sql);
  try {
    const res = execFileSync('cmd.exe', ['/d', '/s', '/c', `npx supabase db query --remote=${project} --read-only --output json --file ${file}`], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
    return JSON.parse(res).rows[0];
  } finally { fs.rmSync(file, {force: true}); }
}

// Static server for the dev build (localhost only).
const root = path.resolve('build/dev-check');
const types = {'.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.otf': 'font/otf', '.ttf': 'font/ttf'};
const server = createServer(async (req, res) => {
  try {
    const file = path.resolve(root, '.' + new URL(req.url, 'http://local').pathname.replace(/\/$/, '/index.html'));
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); return res.end(); }
    res.setHeader('Content-Type', types[path.extname(file)] ?? 'application/octet-stream');
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end(); }
});

let browser, page;
try {
  const r = await fetch(`${base}/functions/v1/nickname-auth`, {method: 'POST', headers, body: JSON.stringify({action: 'register', nickname, pin})});
  assert.equal(r.status, 200);
  const refresh = (await r.json()).refresh_token;
  const t = await fetch(`${base}/auth/v1/token?grant_type=refresh_token`, {method: 'POST', headers, body: JSON.stringify({refresh_token: refresh})});
  assert.equal(t.status, 200);
  const s = await t.json();
  const uid = s.user.id; uids.add(uid);
  const user = {...headers, Authorization: `Bearer ${s.access_token}`, Prefer: 'return=minimal'};
  const insert = async (table, rows) => {
    const res = await fetch(`${base}/rest/v1/${table}`, {method: 'POST', headers: user, body: JSON.stringify(rows)});
    assert.equal(res.status, 201, `${table} insert`);
  };

  stage = 'seed virtual grades, mock exam, school record';
  const confirmed = new Date('2026-11-15T00:00:00Z').toISOString();
  const subjects = {'공통국어1': 2, '공통수학1': 2, '공통영어1': 1, '한국사1': 2, '통합사회1': 3, '통합과학1': 2};
  await insert('grade_records', [[2025, 1, 1], [2025, 1, 2], [2026, 2, 1]].flatMap(([year, sy, sem]) =>
    Object.entries(subjects).map(([name, rank]) => ({user_id: uid, calendar_year: year, school_year: sy, semester: sem,
      subject_name: name, credit: 3, grade_rank: rank, exam_kind: 'semesterSummary', source_confirmed_at: confirmed, source_location: '가상 성적표'}))));
  await insert('mock_exam_records', Object.entries({'국어': [88, 2], '수학': [84, 3], '영어': [null, 2], '통합사회': [82, 3], '통합과학': [90, 2], '한국사': [null, 3]})
    .map(([subject, [percentile, grade]]) => ({user_id: uid, calendar_year: 2026, school_year: 2, exam_month: 9, institution: '교육청', subject, percentile, grade_rank: grade})));
  await insert('school_record_evidence', [
    {user_id: uid, calendar_year: 2026, school_year: 2, category: '세특', evidence: '가상 활동: 정보 시간에 정렬 알고리즘을 비교·구현함.', source_location: '가상 자료 1쪽', career_interest: '컴퓨터공학', source_confirmed_at: confirmed},
    {user_id: uid, calendar_year: 2025, school_year: 1, category: '동아리', evidence: '가상 활동: 컴퓨터 동아리에서 웹 페이지를 만듦.', source_location: '가상 자료 2쪽', career_interest: null, source_confirmed_at: confirmed},
  ]);
  const seeded = counts(uid);
  assert.deepEqual({g: seeded.grade, m: seeded.mock_exam, e: seeded.evidence}, {g: 18, m: 6, e: 2});

  stage = 'log in through the app and open the report';
  await new Promise((done) => server.listen(0, '127.0.0.1', done));
  const url = `http://127.0.0.1:${server.address().port}`;
  await mkdir(out, {recursive: true});
  browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true});
  page = await browser.newPage({viewport: {width: 1280, height: 1000}});
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  page.on('console', (m) => { if (m.type() === 'error' && /overflowed|Exception|assertion|Unable to load asset/i.test(m.text())) errors.push(m.text().slice(0, 200)); });
  await page.goto(url);
  await page.locator('flt-semantics-placeholder').waitFor({state: 'attached', timeout: 60000});
  await page.locator('flt-semantics-placeholder').evaluate((e) => e.click());
  const type = async (name, value) => {
    // Flutter 웹 입력란은 aria-label이 붙은 실제 <input>이다. 비밀번호 칸(type=password)은
    // 접근성 역할이 textbox가 아니므로 라벨로 요소를 직접 찾아 채운다.
    // 포커스를 옮기면 Flutter가 입력 요소를 다시 붙이기도 해서, 값이 들어갔는지 확인하고 다시 시도한다.
    const box = page.locator(`input[aria-label="${name}"], textarea[aria-label="${name}"]`).first();
    for (let attempt = 0; attempt < 4; attempt++) {
      await box.waitFor({timeout: 30000});
      await box.click();
      await page.waitForTimeout(300);
      await box.fill(value);
      await page.waitForTimeout(300);
      if ((await box.inputValue().catch(() => '')) === value) return;
    }
    throw Error(`could not type into ${name}`);
  };
  await type('닉네임', nickname);
  await type('비밀번호 (숫자 4자리)', pin);
  await page.getByRole('button', {name: '로그인', exact: true}).click();
  await page.getByText('진학 컨설팅 리포트', {exact: true}).first().waitFor({timeout: 30000});
  await page.getByText('진학 컨설팅 리포트', {exact: true}).first().click();
  // 리포트 화면의 입력란은 포커스를 받아야 편집 가능한 <input>이 붙는다.
  await page.getByRole('button', {name: '리포트 만들기'}).waitFor({timeout: 30000});
  const field = page.locator('[aria-label="관심 학과·분야"]').or(page.getByRole('textbox', {name: '관심 학과·분야'})).first();
  await field.waitFor({state: 'attached', timeout: 30000});
  await field.click({force: true});
  await page.waitForFunction(() => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName));
  await page.keyboard.insertText('컴퓨터');
  await page.keyboard.press('Tab');
  await page.getByRole('button', {name: '자연', exact: true}).or(page.getByRole('checkbox', {name: '자연', exact: true})).or(page.getByRole('radio', {name: '자연', exact: true})).first().click();
  const started = Date.now();
  await page.getByRole('button', {name: '리포트 만들기'}).click();
  await page.getByText(/^내 성적 기준/).waitFor({timeout: 30000});
  const elapsed = Date.now() - started;
  let text = await page.locator('body').innerText();
  assert.match(text, /학기 종합 성적 18과목 학점가중 5등급 평균 2\.00/);
  assert.match(text, /모의고사: 2026년 2학년 9월 · 교육청 · 국·수·탐 평균 백분위 86\.0 · 영어 2등급/);
  assert.match(text, /연결된 생기부 근거 2건/);
  for (let i = 0; i < 40 && !/지원 조합 예시[\s\S]*수시 6장/.test(text); i++) {
    await page.mouse.move(640, 500); await page.mouse.wheel(0, 250); await page.waitForTimeout(150);
    text = await page.locator('body').innerText();
  }
  assert.match(text, /지원 조합 예시[\s\S]*수시 6장/);
  await page.screenshot({path: `${out}/live-report.png`});
  assert.deepEqual(errors, []);
  console.log(`PASS login path: virtual account seeded (grades 18, mock 6, records 2) → app login → report from DB data in ${elapsed}ms (grade basis, mock, record link, portfolio shown), no errors`);
  await browser.close(); browser = undefined;

  stage = 'delete virtual account through delete-account';
  const del = await fetch(`${base}/functions/v1/delete-account`, {method: 'POST', headers: {...headers, Authorization: `Bearer ${s.access_token}`}, body: JSON.stringify({pin})});
  assert.equal(del.status, 200);
  assert.deepEqual(counts(uid), {auth_user: 0, grade: 0, mock_exam: 0, evidence: 0, credential: 0});
  console.log('PASS cleanup: account, grades, mock exams, school records and nickname credential removed');
} catch (e) {
  if (e instanceof assert.AssertionError) console.error(`assert: ${e.message.split('\n')[0].slice(0, 200)}`);
  console.error(`FAIL: ${stage}. Credentials and upstream responses suppressed.`);
  if (page && browser) {
    await page.screenshot({path: `${out}/live-report-fail.png`}).catch(() => {});
    const t = await page.locator('body').innerText().catch(() => '');
    console.error('screen: ' + t.replaceAll(nickname, '<nickname>').slice(0, 1200));
    const inputs = await page.locator('input, textarea, [role="textbox"]').evaluateAll((els) =>
      els.map((x) => `${x.tagName}|role=${x.getAttribute('role')}|label=${x.getAttribute('aria-label')}|type=${x.getAttribute('type')}`)).catch(() => []);
    console.error('inputs: ' + inputs.join(' ; '));
    if (!(e instanceof assert.AssertionError)) console.error('error: ' + String(e.message).split('\n')[0].slice(0, 200));
  }
  process.exitCode = 1;
} finally {
  await browser?.close();
  if (server.listening) await new Promise((done) => server.close(done));
  // Remove every virtual account this run created, even after an early failure.
  const found = await fetch(`${base}/rest/v1/nickname_accounts?select=user_id&nickname_key=eq.${nickname}`, {headers: admin});
  if (found.ok) for (const row of await found.json()) uids.add(row.user_id);
  for (const id of uids) {
    const r = await fetch(`${base}/auth/v1/admin/users/${id}`, {method: 'DELETE', headers: admin});
    if (!r.ok && r.status !== 404) { console.error('Test Auth cleanup failed.'); process.exitCode = 1; }
  }
  const cleaned = await fetch(`${base}/rest/v1/nickname_login_attempts?nickname_key=eq.${nickname}`, {method: 'DELETE', headers: admin});
  if (!cleaned.ok) { console.error('Test attempt cleanup failed.'); process.exitCode = 1; }
}
