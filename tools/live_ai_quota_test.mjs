// AI 상담 하루 호출 한도(008 + app-help) 실제 점검. 개발 DB에 가상 닉네임 계정을 만들고 끝에 삭제한다.
// 원격 DB 쓰기와 Groq 호출 1회가 일어나므로 사용자 승인 후에만 실행한다. 키·토큰은 출력하지 않는다.
// 한도까지 채우는 부분은 Groq를 부르지 않도록 한도 함수(consume_ai_quota)를 사용자 세션으로 직접 부른다.
// 실행: node tools/live_ai_quota_test.mjs   (Supabase CLI 경로를 바꾸려면 SUPABASE_CLI 환경변수)
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const config = JSON.parse(fs.readFileSync('.env.dev.json', 'utf8').replace(/^﻿/, ''));
const base = config.SUPABASE_URL;
const project = new URL(base).hostname.split('.')[0];
if (!/^[a-z]{20}$/.test(project)) throw Error('Invalid project');
const cli = process.env.SUPABASE_CLI ?? 'npx supabase';
const headers = { apikey: config.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' };
const nickname = `test_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`;
const pin = '0786';
const uids = new Set();
let stage = 'register virtual account';

const run = (args) => execFileSync('cmd.exe', ['/d', '/s', '/c', `${cli} ${args}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
// 계정 삭제 뒤 남은 사용량 행 수(읽기 전용 SQL, service_role은 사용자 테이블 권한이 없음).
function usageRowsOf(uid) {
  if (!/^[0-9a-f-]{36}$/.test(uid)) throw Error('unsafe id');
  const file = `tools/ocr/test-output/ai_quota_${process.pid}.sql`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `select count(*)::int as n from public.ai_usage_daily where user_id='${uid}'`);
  try {
    return JSON.parse(run(`db query --remote=${project} --read-only --output json --file ${file}`)).rows[0].n;
  } finally { fs.rmSync(file, { force: true }); }
}

try {
  const reg = await fetch(`${base}/functions/v1/nickname-auth`, { method: 'POST', headers, body: JSON.stringify({ action: 'register', nickname, pin }) });
  assert.equal(reg.status, 200);
  const tokenRes = await fetch(`${base}/auth/v1/token?grant_type=refresh_token`, { method: 'POST', headers, body: JSON.stringify({ refresh_token: (await reg.json()).refresh_token }) });
  assert.equal(tokenRes.status, 200);
  const s = await tokenRes.json();
  const uid = s.user.id;
  uids.add(uid);
  const user = { ...headers, Authorization: `Bearer ${s.access_token}` };
  const ask = (body) => fetch(`${base}/functions/v1/app-help`, { method: 'POST', headers: user, body: JSON.stringify(body) });
  const rpc = (kind) => fetch(`${base}/rest/v1/rpc/consume_ai_quota`, { method: 'POST', headers: user, body: JSON.stringify({ p_kind: kind }) });
  const myUsage = async () => (await (await fetch(`${base}/rest/v1/ai_usage_daily?select=help_count,record_count`, { headers: user })).json());

  stage = 'no usage before first question';
  assert.deepEqual(await myUsage(), []);

  stage = 'first help question consumes 1';
  const first = await ask({ question: '비밀번호를 잊어버렸어요' });
  const firstBody = await first.json();
  assert.equal(first.status, 200);
  assert.equal(firstBody.remaining, 29);
  assert.deepEqual(await myUsage(), [{ help_count: 1, record_count: 0 }]);
  console.log('1) 도움말 질문 200 · 남은 횟수 29 · 사용량 행 help_count 1');

  stage = 'no-document answer is free';
  const none = await ask({ question: '뭐 어떻게 해야 돼?' });
  assert.equal(none.status, 200);
  assert.equal((await myUsage())[0].help_count, 1);
  console.log('2) 관련 문서 없는 답 200 · 횟수 그대로 1');

  stage = 'user cannot write usage directly';
  const ins = await fetch(`${base}/rest/v1/ai_usage_daily`, { method: 'POST', headers: { ...user, Prefer: 'return=minimal' }, body: JSON.stringify({ user_id: uid, usage_date: '2000-01-01' }) });
  assert.ok([401, 403].includes(ins.status), `insert ${ins.status}`);
  const upd = await fetch(`${base}/rest/v1/ai_usage_daily?user_id=eq.${uid}`, { method: 'PATCH', headers: { ...user, Prefer: 'return=representation' }, body: JSON.stringify({ help_count: 0 }) });
  assert.ok([401, 403].includes(upd.status), `update ${upd.status}`);
  assert.equal((await myUsage())[0].help_count, 1);
  console.log(`3) 사용자가 직접 추가 ${ins.status}·수정 ${upd.status} 거부 · 횟수 그대로`);

  stage = 'unknown kind rejected';
  assert.equal((await rpc('other')).status, 400);

  stage = 'fill help quota to 30';
  let allowed = 0;
  for (let i = 0; i < 29; i++) { const r = await (await rpc('help')).json(); if (r.allowed) allowed++; }
  assert.equal(allowed, 29);
  const over = await (await rpc('help')).json();
  assert.deepEqual(over, { allowed: false, reason: 'DAILY_LIMIT', limit: 30, remaining: 0 });
  assert.equal((await myUsage())[0].help_count, 30);
  console.log('4) 한도 함수 29회 허용 후 31번째 DAILY_LIMIT · help_count 30에서 멈춤');

  stage = 'app-help returns 429 at limit';
  const blocked = await ask({ question: '비밀번호를 잊어버렸어요' });
  assert.equal(blocked.status, 429);
  assert.deepEqual(await blocked.json(), { error: 'DAILY_LIMIT', limit: 30 });
  console.log('5) 한도 도달 후 도움말 질문 429 DAILY_LIMIT(limit 30)');

  stage = 'record quota is separate';
  let rec = 0;
  for (let i = 0; i < 10; i++) { const r = await (await rpc('record')).json(); if (r.allowed) rec++; }
  assert.equal(rec, 10);
  assert.equal((await (await rpc('record')).json()).reason, 'DAILY_LIMIT');
  assert.deepEqual(await myUsage(), [{ help_count: 30, record_count: 10 }]);
  console.log('6) 생기부 상담 한도는 따로 10회 · 11번째 DAILY_LIMIT');

  stage = 'delete virtual account';
  const del = await fetch(`${base}/functions/v1/delete-account`, { method: 'POST', headers: user, body: JSON.stringify({ pin }) });
  assert.equal(del.status, 200);
  uids.clear();
  assert.equal(usageRowsOf(uid), 0);
  console.log('7) 가상 계정 삭제 · 사용량 행 함께 삭제(0행)');
  console.log('\nPASS: AI 상담 하루 호출 한도 실제 점검');
} catch (e) {
  if (e instanceof assert.AssertionError) console.error(`assert: ${e.message.slice(0, 200)} actual=${JSON.stringify(e.actual)} expected=${JSON.stringify(e.expected)}`);
  else console.error(`error: ${String(e?.message ?? e).replace(/eyJ[\w.-]+|gsk_\w+|sb_secret_\w+/g, '[redacted]').slice(0, 300)}`);
  console.error(`FAIL: ${stage}. 키·토큰은 출력하지 않음.`);
  process.exitCode = 1;
} finally {
  // 중간에 실패해도 이번 실행이 만든 가상 계정을 지운다(사용량 행은 계정 삭제로 함께 지워짐).
  if (uids.size > 0) {
    const key = JSON.parse(run(`projects api-keys --remote=${project} --output json`)).find((k) => k.name === 'service_role').api_key;
    const admin = { apikey: key, Authorization: `Bearer ${key}` };
    for (const id of uids) {
      const r = await fetch(`${base}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: admin });
      if (!r.ok && r.status !== 404) { console.error('가상 계정 정리 실패'); process.exitCode = 1; }
    }
    await fetch(`${base}/rest/v1/nickname_login_attempts?nickname_key=eq.${nickname}`, { method: 'DELETE', headers: admin });
  }
}
