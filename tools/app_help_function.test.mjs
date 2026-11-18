// 앱 도움말 Edge Function 로직 테스트. fetch를 가짜로 바꿔 Supabase·Groq를 실제로 부르지 않는다.
// 실행: node --test tools/app_help_function.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  createHandler, parseBody, findChunks, GROQ_URL, DEFAULT_MODEL, NOT_FOUND_ANSWER, MAX_HISTORY,
} from '../supabase/functions/app-help/handler.mjs';

const kb = JSON.parse(readFileSync('supabase/functions/app-help/help_kb.json', 'utf8'));
const FAKE_KEY = 'test-key-not-real';

function setup({ env = {}, user = { id: 'u1' }, groq, quota } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith('/auth/v1/user')) {
      return user ? Response.json(user) : new Response('{}', { status: 401 });
    }
    if (String(url).endsWith('/rest/v1/rpc/consume_ai_quota')) {
      return quota ? quota(JSON.parse(init.body), init) : Response.json({ allowed: true, limit: 30, remaining: 29 });
    }
    if (url === GROQ_URL) {
      return groq ? groq(JSON.parse(init.body)) : Response.json({ choices: [{ message: { content: ' 답변입니다. ' } }] });
    }
    throw new Error(`예상하지 못한 호출: ${url}`);
  };
  const values = { SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'anon', GROQ_API_KEY: FAKE_KEY, ...env };
  return { handler: createHandler({ kb, env: (k) => values[k] || undefined, fetch }), calls };
}

const post = (body, auth = 'Bearer token') => new Request('https://fn.test/app-help', {
  method: 'POST',
  headers: { 'content-type': 'application/json', ...(auth ? { authorization: auth } : {}) },
  body: JSON.stringify(body),
});

test('질문 → 문서 검색 → Groq 호출 → 답변과 근거 문서', async () => {
  let sent;
  const { handler, calls } = setup({ groq: (b) => { sent = b; return Response.json({ choices: [{ message: { content: '먼저 회원가입하세요.' } }] }); } });
  const res = await handler(post({ question: '이 앱에서 뭐부터 시작해야 돼?' }));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.answer, '먼저 회원가입하세요.');
  assert.ok(body.sources.length >= 1 && body.sources.length <= 3);
  assert.match(body.sources[0].title, /처음 시작하는 순서/);

  assert.equal(sent.model, DEFAULT_MODEL);
  assert.equal(sent.reasoning_effort, 'low'); // 기본 모델(gpt-oss)은 추론을 낮춘다
  assert.equal(sent.messages[0].role, 'system');
  assert.match(sent.messages[0].content, /\[앱 문서\]/);
  assert.match(sent.messages[0].content, /처음 시작하는 순서/);
  assert.match(sent.messages[0].content, /합격을 보장하거나 단정하는 표현은 쓰지 마세요/);
  assert.deepEqual(sent.messages.at(-1), { role: 'user', content: '이 앱에서 뭐부터 시작해야 돼?' });
  assert.ok(sent.messages[0].content.length < 6000, '보내는 문서가 너무 길다');

  const groqCall = calls.find((c) => c.url === GROQ_URL);
  assert.equal(groqCall.init.headers.authorization, `Bearer ${FAKE_KEY}`);
});

test('GROQ_MODEL 서버 설정으로 모델을 바꿀 수 있다', async () => {
  let sent;
  const { handler } = setup({ env: { GROQ_MODEL: 'other-model' }, groq: (b) => { sent = b; return Response.json({ choices: [{ message: { content: 'ok' } }] }); } });
  await handler(post({ question: '판단 보류는 왜 떠?' }));
  assert.equal(sent.model, 'other-model');
  assert.equal(sent.reasoning_effort, undefined);
});

test('로그인하지 않았거나 세션이 무효면 401, Groq를 부르지 않는다', async () => {
  const a = setup();
  assert.equal((await a.handler(post({ question: '시작' }, null))).status, 401);
  const b = setup({ user: null });
  const res = await b.handler(post({ question: '시작' }));
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: 'AUTH' });
  assert.ok(!b.calls.some((c) => c.url === GROQ_URL));
});

test('키가 없으면 503 NOT_CONFIGURED', async () => {
  const { handler } = setup({ env: { GROQ_API_KEY: '' } });
  const res = await handler(post({ question: '시작' }));
  assert.equal(res.status, 503);
  assert.deepEqual(await res.json(), { error: 'NOT_CONFIGURED' });
});

test('입력 검사: 빈 질문·너무 긴 질문·잘못된 대화 기록은 400', async () => {
  const { handler } = setup();
  for (const body of [{}, { question: '  ' }, { question: 'a'.repeat(501) }, { question: '시작', history: [{ role: 'system', content: 'x' }] }, { question: '시작', history: 'x' }]) {
    assert.equal((await handler(post(body))).status, 400, JSON.stringify(body).slice(0, 60));
  }
  assert.equal((await handler(new Request('https://fn.test', { method: 'GET' }))).status, 405);
  assert.equal((await handler(new Request('https://fn.test', { method: 'OPTIONS' }))).status, 200);
});

test('대화 기록은 최근 몇 개만, 길면 잘라서 보낸다', () => {
  const history = Array.from({ length: 10 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: `${i} ${'가'.repeat(900)}` }));
  const parsed = parseBody({ question: '그건 어디 있어?', history });
  assert.equal(parsed.history.length, MAX_HISTORY);
  assert.ok(parsed.history.every((m) => m.content.length <= 600));
});

test('지금 질문만으로 찾을 게 없을 때만 직전 질문과 함께 검색한다', async () => {
  let sent;
  const { handler } = setup({ groq: (b) => { sent = b; return Response.json({ choices: [{ message: { content: 'ok' } }] }); } });
  await handler(post({ question: '그거 어디서 해요?', history: [{ role: 'user', content: '계정 삭제하고 싶어요' }, { role: 'assistant', content: '설정에서 할 수 있습니다.' }] }));
  assert.match(sent.messages[0].content, /계정 삭제/);
  assert.equal(sent.messages.length, 4); // system + 기록 2 + 질문
});

test('관련 문서가 없으면 Groq를 부르지 않고 안내 문구를 준다', async () => {
  const { handler, calls } = setup();
  const res = await handler(post({ question: '뭐 어떻게 해야 돼?' }));
  assert.deepEqual(await res.json(), { answer: NOT_FOUND_ANSWER, sources: [] });
  assert.ok(!calls.some((c) => c.url === GROQ_URL));
});

test('Groq 한도 초과는 429, 그 밖의 실패는 502로 알린다', async () => {
  const limited = setup({ groq: () => new Response('{}', { status: 429 }) });
  assert.equal((await limited.handler(post({ question: '판단 보류는 왜 떠?' }))).status, 429);
  const broken = setup({ groq: () => new Response('err', { status: 500 }) });
  assert.equal((await broken.handler(post({ question: '판단 보류는 왜 떠?' }))).status, 502);
  const empty = setup({ groq: () => Response.json({ choices: [] }) });
  assert.equal((await empty.handler(post({ question: '판단 보류는 왜 떠?' }))).status, 502);
  const thrown = setup({ groq: () => { throw new Error('network'); } });
  const res = await thrown.handler(post({ question: '판단 보류는 왜 떠?' }));
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { error: 'UNAVAILABLE' });
});

test('응답과 오류에 키 값이 나오지 않는다', async () => {
  const { handler } = setup({ groq: () => new Response(`bad ${FAKE_KEY}`, { status: 400 }) });
  const text = await (await handler(post({ question: '판단 보류는 왜 떠?' }))).text();
  assert.ok(!text.includes(FAKE_KEY));
});

test('지금 질문에 내용이 있으면 직전 질문이 검색 결과를 덮어쓰지 않는다', async () => {
  const { buildIndex } = await import('../supabase/functions/app-help/search.mjs');
  const index = buildIndex(kb.chunks);
  const history = [{ role: 'user', content: '이 앱에서 뭐부터 시작해야 하나요?' }, { role: 'assistant', content: '...' }];
  const own = findChunks(index, '그럼 성적표는 어디서 올려요?', history);
  assert.match(own[0].chunk.title, /내신 성적표 올리기/);
  const vague = findChunks(index, '그럼 그건 어디서 해요?', [{ role: 'user', content: '계정 삭제하고 싶어요' }]);
  assert.match(vague[0].chunk.title, /계정 삭제/);
  assert.deepEqual(findChunks(index, '그럼 그건 어디서 해요?', []), []);
});

test('모델을 부르기 직전에 사용자 세션으로 하루 한도를 차감하고 남은 횟수를 돌려준다', async () => {
  let quotaCall;
  const { handler, calls } = setup({ quota: (b, init) => { quotaCall = { b, init }; return Response.json({ allowed: true, limit: 30, remaining: 12 }); } });
  const res = await handler(post({ question: '비밀번호 잊어버렸어요' }));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).remaining, 12);
  assert.deepEqual(quotaCall.b, { p_kind: 'help' });
  assert.equal(quotaCall.init.headers.authorization, 'Bearer token'); // 서비스 키가 아니라 사용자 세션
  const order = calls.map((c) => c.url);
  assert.ok(order.findIndex((u) => u.endsWith('consume_ai_quota')) < order.indexOf(GROQ_URL));
});

test('하루 한도를 넘으면 모델을 부르지 않고 429 DAILY_LIMIT', async () => {
  const { handler, calls } = setup({ quota: () => Response.json({ allowed: false, reason: 'DAILY_LIMIT', limit: 30, remaining: 0 }) });
  const res = await handler(post({ question: '비밀번호 잊어버렸어요' }));
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: 'DAILY_LIMIT', limit: 30 });
  assert.ok(!calls.some((c) => c.url === GROQ_URL));
});

test('전체 하루 상한에 닿으면 429 SERVICE_LIMIT', async () => {
  const { handler, calls } = setup({ quota: () => Response.json({ allowed: false, reason: 'SERVICE_LIMIT', limit: 30, remaining: 5 }) });
  const res = await handler(post({ question: '비밀번호 잊어버렸어요' }));
  assert.equal(res.status, 429);
  assert.equal((await res.json()).error, 'SERVICE_LIMIT');
  assert.ok(!calls.some((c) => c.url === GROQ_URL));
});

test('한도 함수를 부를 수 없으면 한도 없이 모델을 부르지 않는다', async () => {
  const { handler, calls } = setup({ quota: () => new Response('{}', { status: 404 }) });
  const res = await handler(post({ question: '비밀번호 잊어버렸어요' }));
  assert.equal(res.status, 502);
  assert.ok(!calls.some((c) => c.url === GROQ_URL));
});

test('관련 문서가 없어 모델을 부르지 않는 답은 횟수에 넣지 않는다', async () => {
  const { handler, calls } = setup();
  const res = await handler(post({ question: '뭐 어떻게 해야 돼?' }));
  assert.equal(res.status, 200);
  assert.ok(!calls.some((c) => c.url.endsWith('consume_ai_quota')));
});
