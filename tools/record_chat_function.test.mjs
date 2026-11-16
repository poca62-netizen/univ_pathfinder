// 생기부 상담 채팅 모드(app-help, mode: 'record') 테스트. 가짜 fetch로 Supabase·Groq를 부르지 않는다.
// 근거는 모두 가상 학생 자료다.
// 실행: node --test tools/record_chat_function.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHandler, GROQ_URL } from '../supabase/functions/app-help/handler.mjs';
import {
  checkCitations, formatEvidence, parseRecordFields, EVIDENCE_CHARS, MAX_EVIDENCE,
} from '../supabase/functions/app-help/record.mjs';

const kb = JSON.parse(readFileSync('supabase/functions/app-help/help_kb.json', 'utf8'));
const id = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const ROWS = [
  { id: id(1), calendar_year: 2025, school_year: 1, category: '세특(통합과학)', evidence: '가상 학생이 산성비 실험을 설계하고 pH 변화를 조별로 비교함.', career_interest: '환경공학' },
  { id: id(2), calendar_year: 2025, school_year: 1, category: '동아리', evidence: '가상 과학 동아리에서 하천 수질 조사 보고서를 작성함.', career_interest: null },
];

function setup({ rows = ROWS, rest, groq } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const u = String(url);
    calls.push({ url: u, init });
    if (u.endsWith('/auth/v1/user')) return Response.json({ id: 'u1' });
    if (u.includes('/rest/v1/school_record_evidence?')) {
      if (rest) return rest(u, init);
      const ids = decodeURIComponent(new URL(u).searchParams.get('id')).replace(/^in\.\(|\)$/g, '').split(',');
      return Response.json(rows.filter((r) => ids.includes(r.id)));
    }
    if (u === GROQ_URL) return groq ? groq(JSON.parse(init.body)) : Response.json({ choices: [{ message: { content: '실험을 직접 설계한 점이 보입니다 [근거 1].' } }] });
    throw new Error(`예상하지 못한 호출: ${u}`);
  };
  const values = { SUPABASE_URL: 'https://example.test', SUPABASE_ANON_KEY: 'anon', GROQ_API_KEY: 'test-key' };
  return { handler: createHandler({ kb, env: (k) => values[k], fetch }), calls };
}

const post = (body) => new Request('https://fn.test/app-help', {
  method: 'POST',
  headers: { 'content-type': 'application/json', authorization: 'Bearer user-token' },
  body: JSON.stringify({ mode: 'record', ...body }),
});

test('근거 ID → 사용자 세션으로 원문 조회 → Groq → 인용 근거 반환', async () => {
  let sent;
  const { handler, calls } = setup({ groq: (b) => { sent = b; return Response.json({ choices: [{ message: { content: '실험 설계 경험이 보입니다 [근거 1]. 수질 조사도 이어집니다 [근거 2].' } }] }); } });
  const res = await handler(post({ question: '제 강점이 뭘까요?', evidenceIds: [id(2), id(1)], goal: '환경 분야 탐구' }));
  assert.equal(res.status, 200);
  const body = await res.json();
  // 앱에서 고른 순서대로 번호: 근거 1 = id(2), 근거 2 = id(1)
  assert.deepEqual(body.citations.map((c) => c.id), [id(2), id(1)]);
  assert.equal(body.citations[0].label, '2025년 1학년 · 동아리');
  assert.equal(body.invalidCitations, 0);

  const rest = calls.find((c) => c.url.includes('/rest/v1/'));
  assert.equal(rest.init.headers.authorization, 'Bearer user-token'); // RLS가 사용자 세션으로 걸린다
  assert.match(decodeURIComponent(rest.url), /career_evidence_enabled=eq\.true/);

  const system = sent.messages[0].content;
  assert.match(system, /\[근거 1\] 2025년 1학년 · 동아리/);
  assert.match(system, /하천 수질 조사/);
  assert.match(system, /학생 진로 메모: 환경공학/);
  assert.match(system, /\[이번 상담 목표\]\n환경 분야 탐구/);
  assert.match(system, /합격 가능성, 등급·점수 추정/);
  assert.equal(sent.temperature, 0.4);
  assert.ok(!calls.some((c) => c.url.includes('help_kb')));
});

test('남의 근거·삭제된 근거·상담 활용을 끈 근거가 섞이면 400 EVIDENCE, Groq 미호출', async () => {
  const { handler, calls } = setup({ rows: [ROWS[0]] }); // RLS로 id(2)는 안 보이는 상황
  const res = await handler(post({ question: '강점?', evidenceIds: [id(1), id(2)] }));
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: 'EVIDENCE' });
  assert.ok(!calls.some((c) => c.url === GROQ_URL));
});

test('입력 검사: 근거 없음·7개 이상·UUID 아님·중복·긴 목표는 400 INPUT, DB 미조회', async () => {
  const { handler, calls } = setup();
  const many = Array.from({ length: MAX_EVIDENCE + 1 }, (_, i) => id(i + 1));
  for (const extra of [
    { evidenceIds: [] }, { evidenceIds: many }, { evidenceIds: ["x') or 1=1"] }, { evidenceIds: [id(1), id(1)] },
    { evidenceIds: [id(1)], goal: '가'.repeat(301) }, { evidenceIds: 'abc' },
  ]) {
    const res = await handler(post({ question: '강점?', ...extra }));
    assert.equal(res.status, 400, JSON.stringify(extra).slice(0, 50));
  }
  assert.ok(!calls.some((c) => c.url.includes('/rest/v1/')));
  assert.equal(parseRecordFields({ evidenceIds: [id(1)] }).goal, '');
});

test('근거 조회가 실패하면 502, Groq 429는 429', async () => {
  const down = setup({ rest: () => new Response('err', { status: 500 }) });
  assert.equal((await down.handler(post({ question: '강점?', evidenceIds: [id(1)] }))).status, 502);
  const limited = setup({ groq: () => new Response('{}', { status: 429 }) });
  assert.equal((await limited.handler(post({ question: '강점?', evidenceIds: [id(1)] }))).status, 429);
});

test('제공하지 않은 근거 번호는 답에서 지우고 개수를 센다', () => {
  const r = checkCitations('봉사를 꾸준히 했습니다 [근거 3]. 실험을 설계했습니다 [근거 1]. 다시 [근거 1].', ROWS);
  assert.equal(r.answer, '봉사를 꾸준히 했습니다. 실험을 설계했습니다 [근거 1]. 다시 [근거 1].');
  assert.equal(r.invalidCitations, 1);
  assert.deepEqual(r.citations.map((c) => c.number), [1]);
  // 실제 점검에서 모델이 묶어 쓴 형식([근거 1, 2])도 인용으로 읽는다. 잘못된 번호만 뺀다.
  const grouped = checkCitations('두 활동을 이어 보세요 [근거 1, 2]. 그리고 [근거 2·5].', ROWS);
  assert.equal(grouped.answer, '두 활동을 이어 보세요 [근거 1][근거 2]. 그리고 [근거 2].');
  assert.deepEqual(grouped.citations.map((c) => c.number), [1, 2]);
  assert.equal(grouped.invalidCitations, 1);
  assert.equal(checkCitations('잘못 [근거 7, 9].', ROWS).answer, '잘못.');
  const none = checkCitations('일반적인 조언입니다.', ROWS);
  assert.deepEqual(none.citations, []);
});

test('긴 근거는 잘라서 보내고 출처 위치는 보내지 않는다', () => {
  const long = { ...ROWS[0], evidence: '가'.repeat(EVIDENCE_CHARS + 100), source_location: '3쪽 세특' };
  const text = formatEvidence([long], '');
  assert.match(text, /…\(이하 생략\)/);
  assert.ok(!text.includes('가'.repeat(EVIDENCE_CHARS + 1)));
  assert.ok(!text.includes('3쪽'));
  assert.ok(!text.includes('[이번 상담 목표]'));
});

test('mode 없는 요청은 기존 도움말 모드로 동작한다', async () => {
  const { handler, calls } = setup();
  const res = await handler(new Request('https://fn.test/app-help', {
    method: 'POST', headers: { authorization: 'Bearer t' }, body: JSON.stringify({ question: '판단 보류는 왜 떠?' }),
  }));
  assert.equal(res.status, 200);
  assert.ok((await res.json()).sources.length > 0);
  assert.ok(!calls.some((c) => c.url.includes('/rest/v1/')));
});
