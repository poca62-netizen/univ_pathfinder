// 배포된 app-help 실제 점검: 개발 DB에 가상 닉네임 계정을 만들어 가상 질문을 보내고 끝에 계정을 삭제한다.
// 원격 DB 쓰기·Groq 호출이 일어나므로 사용자 승인 후에만 실행한다. 키·토큰은 출력하지 않는다.
// 실행: node tools/live_app_help_test.mjs
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import assert from 'node:assert/strict';

const config = JSON.parse(fs.readFileSync('.env.dev.json', 'utf8').replace(/^﻿/, ''));
const base = config.SUPABASE_URL;
const project = new URL(base).hostname.split('.')[0];
if (!/^[a-z]{20}$/.test(project)) throw Error('Invalid project');
const headers = { apikey: config.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json' };
const nickname = `test_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`;
const pin = '0786';
const uids = new Set();
let stage = 'register virtual account';

const ask = (body, token) => fetch(`${base}/functions/v1/app-help`, {
  method: 'POST',
  headers: token ? { ...headers, Authorization: `Bearer ${token}` } : headers,
  body: JSON.stringify(body),
});

// 무료 등급 분당 토큰 한도(8,000)를 넘지 않게 Groq를 부르는 질문 사이에 간격을 둔다.
const pause = () => new Promise((r) => setTimeout(r, 15000));

async function show(label, response) {
  const data = await response.json();
  console.log(`\n[${label}] HTTP ${response.status}`);
  if (data.answer) console.log(data.answer);
  if (data.sources?.length) console.log(`근거: ${data.sources.map((s) => `${s.source} > ${s.title}`).join(' / ')}`);
  if (data.error) console.log(`오류 코드: ${data.error}`);
  return { status: response.status, ...data };
}

try {
  const reg = await fetch(`${base}/functions/v1/nickname-auth`, { method: 'POST', headers, body: JSON.stringify({ action: 'register', nickname, pin }) });
  assert.equal(reg.status, 200);
  const refresh = (await reg.json()).refresh_token;
  const tokenRes = await fetch(`${base}/auth/v1/token?grant_type=refresh_token`, { method: 'POST', headers, body: JSON.stringify({ refresh_token: refresh }) });
  assert.equal(tokenRes.status, 200);
  const s = await tokenRes.json();
  uids.add(s.user.id);
  const token = s.access_token;

  stage = 'reject request without session';
  assert.equal((await ask({ question: '이 앱에서 뭐부터 시작하나요?' })).status, 401);

  stage = 'reject invalid input';
  assert.equal((await ask({ question: '' }, token)).status, 400);

  stage = 'start question';
  const first = await show('뭐부터 시작', await ask({ question: '이 앱에서 뭐부터 시작해야 하나요?' }, token));
  assert.equal(first.status, 200);
  assert.ok(first.sources.some((x) => x.title.includes('처음 시작하는 순서')));

  stage = 'follow-up question';
  await pause();
  const follow = await show('이어 묻기', await ask({
    question: '그럼 성적표는 어디서 올려요?',
    history: [{ role: 'user', content: '이 앱에서 뭐부터 시작해야 하나요?' }, { role: 'assistant', content: first.answer }],
  }, token));
  assert.equal(follow.status, 200);

  stage = 'academy question';
  await pause();
  const academy = await show('학원 여러 학생', await ask({ question: '학원에서 학생 여러 명을 한 계정으로 관리할 수 있나요?' }, token));
  assert.equal(academy.status, 200);

  stage = 'admission judgement request';
  await pause();
  const judge = await show('합격 판단 요청(가상 성적)', await ask({ question: '내신 2.3등급인데 연세대 학생부교과 붙을 수 있을까요?' }, token));
  assert.equal(judge.status, 200);

  stage = 'off-topic question';
  await pause();
  const off = await show('앱과 무관한 질문', await ask({ question: '미적분 숙제 풀어 주세요' }, token));
  assert.equal(off.status, 200);

  stage = 'no matching document';
  const none = await show('관련 문서 없음', await ask({ question: '뭐 어떻게 해야 돼?' }, token));
  assert.equal(none.status, 200);
  assert.deepEqual(none.sources, []);

  stage = 'delete virtual account';
  const del = await fetch(`${base}/functions/v1/delete-account`, { method: 'POST', headers: { ...headers, Authorization: `Bearer ${token}` }, body: JSON.stringify({ pin }) });
  assert.equal(del.status, 200);
  uids.clear();
  console.log('\nPASS: 세션 없음 401, 빈 질문 400, 질문·이어 묻기·학원·합격 판단·무관 질문 200, 문서 없음은 모델 미호출 안내, 가상 계정 삭제.');
} catch (e) {
  if (e instanceof assert.AssertionError) console.error(`assert: actual=${JSON.stringify(e.actual)} expected=${JSON.stringify(e.expected)}`);
  else console.error(`error: ${String(e?.message ?? e).replace(/eyJ[\w.-]+|gsk_\w+|sb_secret_\w+/g, '[redacted]').slice(0, 300)}`);
  console.error(`FAIL: ${stage}. 키·토큰은 출력하지 않음.`);
  process.exitCode = 1;
} finally {
  // 중간에 실패해도 이번 실행이 만든 가상 계정을 지운다.
  if (uids.size > 0) {
    const keys = JSON.parse(execFileSync('cmd.exe', ['/d', '/s', '/c', `npx supabase projects api-keys --remote=${project} --output json`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
    const key = keys.find((k) => k.name === 'service_role').api_key;
    const admin = { apikey: key, Authorization: `Bearer ${key}` };
    for (const id of uids) {
      const r = await fetch(`${base}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: admin });
      if (!r.ok && r.status !== 404) { console.error('가상 계정 정리 실패'); process.exitCode = 1; }
    }
    await fetch(`${base}/rest/v1/nickname_login_attempts?nickname_key=eq.${nickname}`, { method: 'DELETE', headers: admin });
  }
}
