// 앱 도움말 지식 베이스·검색 테스트 (외부 호출 없음)
// 실행: node --test tools/build_help_kb.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildKb, chunkMarkdown, neutralize, sanitize, serialize, MAX_CHUNK, OUTPUT } from './build_help_kb.mjs';
import { buildIndex, search, selectContext, tokenize } from '../supabase/functions/app-help/search.mjs';

const kb = buildKb();
const index = buildIndex(kb.chunks);

test('배포용 help_kb.json이 문서와 같다 (문서를 고쳤으면 node tools/build_help_kb.mjs)', () => {
  assert.equal(readFileSync(OUTPUT, 'utf8').replace(/\r\n/g, '\n'), serialize(kb));
});

test('코드 블록·비밀키·배포 명령·개인정보 폴더는 넣지 않는다', () => {
  const md = [
    '# 제목', '설명 문장입니다. 충분히 긴 설명 문장을 여기에 적어 둡니다.',
    '```powershell', 'flutter run --dart-define-from-file=.env.dev.json', '```',
    '`NVIDIA_API_KEY`는 서버에만 둡니다.', 'supabase secrets set --env-file x', '성적표/ 폴더 안내',
  ].join('\n');
  const clean = sanitize(md);
  assert.match(clean, /설명 문장/);
  for (const bad of ['flutter run', 'API_KEY', 'secrets set', '성적표/']) assert.ok(!clean.includes(bad), bad);

  const all = kb.chunks.map((c) => `${c.title}\n${c.text}`).join('\n');
  for (const re of [/```/, /_API_KEY/, /secrets\s+set/i, /service_role/i, /\.env\.dev/, /성적표\//, /gsk_|nvapi-/, /--dart-define/]) {
    assert.ok(!re.test(all), `지식 베이스에 ${re} 가 남아 있음`);
  }
});

test('2028 전형계획 기초 자료의 옛 표현·원본 파일 이름은 챗봇 지식 베이스에 넣지 않는다', () => {
  const all = kb.chunks.map((c) => `${c.title}\n${c.text}`).join('\n');
  for (const re of [/사용자\s*제공/, /사용자가\s*제공/, /정리본/, /대입전형계획 정리/, /(제작자|작성자)\s*정보/, /공개\s*운영/, /학교·학원에\s*공개/]) {
    assert.ok(!re.test(all), `지식 베이스에 ${re} 가 남아 있음`);
  }
  assert.equal(neutralize('기초 자료는 사용자 제공 정리본(`2028_대입전형계획 정리.html`)이며'), '기초 자료는 2028 전형계획 자료(2028 전형계획 자료)이며');
});

test('조각은 크기 제한을 지키고 제목 경로를 가진다', () => {
  assert.ok(kb.chunks.length > 100);
  for (const c of kb.chunks) {
    assert.ok(c.text.length <= MAX_CHUNK, `${c.id} ${c.text.length}`);
    assert.ok(c.title.length > 0);
  }
  const chunks = chunkMarkdown('# 가\n## 나\n' + '문장 '.repeat(500), { label: 'x' });
  assert.ok(chunks.length > 1);
  assert.ok(chunks.every((c) => c.title === '가 > 나'));
});

test('개발자용 절은 하위 절까지 건너뛴다', () => {
  const chunks = chunkMarkdown(
    '# R\n## 코드 검증\n검증 명령 설명이 아주 길게 들어 있는 문단입니다. 학생에게는 필요 없습니다.\n### 하위\n하위 절도 학생에게는 필요 없는 개발 설명 문단입니다. 길게 씁니다.\n## 로그인\n로그인 설명 문단입니다. 닉네임과 비밀번호로 로그인하는 방법을 길게 설명합니다.',
    { label: 'R', skip: [/^코드 검증$/] });
  assert.deepEqual(chunks.map((c) => c.title), ['R > 로그인']);
});

test('조사가 붙어도 같은 낱말로 찾는다', () => {
  const t = tokenize('리포트는');
  assert.ok(t.includes('리포'));
  assert.ok(tokenize('리포트를').includes('리포'));
  assert.deepEqual(tokenize('뭐부터 어떻게', { dropStopWords: true }).filter((x) => x.startsWith('w:')), ['w:뭐부터']);
});

// 가상 학생 질문 → 상위 3개 안에 있어야 할 조각 (경로, 제목 일부)
const CASES = [
  ['이 앱에서 뭐부터 시작해야 돼?', 'docs/APP_GUIDE.md', '처음 시작하는 순서'],
  ['비밀번호 잊어버렸어요', 'docs/APP_GUIDE.md', '회원가입과 로그인'],
  ['판단 보류는 왜 떠?', 'docs/APP_GUIDE.md', '판단 보류가 뜨는 이유'],
  ['성적표 사진 올리는 법', 'docs/APP_GUIDE.md', '내신 성적표 올리기'],
  ['모의고사 점수 어디에 넣어?', 'docs/APP_GUIDE.md', '모의고사 입력'],
  ['생기부 개인정보 지워야 해?', 'docs/APP_GUIDE.md', '생활기록부 올리기'],
  ['등록금은 어디서 봐?', 'docs/APP_GUIDE.md', '대학 탐색과 대학 비교'],
  ['집에서 학교까지 통학 시간', 'docs/APP_GUIDE.md', '출발지·대학 지도'],
  ['계정 삭제하는 방법', 'docs/APP_GUIDE.md', '계정 삭제'],
  ['체험 모드에서 리포트가 안 보여요', 'docs/APP_GUIDE.md', '체험 모드'],
  ['안정 적정 상향 뜻이 뭐야', 'docs/APP_GUIDE.md', '진학 컨설팅 리포트'],
  ['수능 최저 충족하는지 알 수 있어?', 'docs/APP_GUIDE.md', '수능 최저 확인'],
  ['관심 대학 몇 개까지 고를 수 있어?', 'docs/APP_GUIDE.md', '대학 후보와 관심 대학'],
  ['신뢰도가 낮음으로 나와', 'docs/APP_GUIDE.md', '신뢰도가 낮게 나오는 이유'],
  ['5등급제 내신은 어떻게 비교해?', 'docs/APP_GUIDE.md', '진학 컨설팅 리포트'],
  ['입결 자료는 어디서 가져왔어?', 'docs/APP_GUIDE.md', '자료 출처'],
  ['PDF로 리포트 저장', 'docs/APP_GUIDE.md', '진학 컨설팅 리포트'],
  ['내 성적 다른 사람이 볼 수 있어?', 'docs/APP_GUIDE.md', '개인정보'],
  ['지원 조합 예시가 뭐야', 'docs/APP_GUIDE.md', '진학 컨설팅 리포트'],
  ['생기부 컨설팅은 뭘 해줘?', 'docs/APP_GUIDE.md', '생기부 컨설팅'],
  // 학부모·선생님·학원 관계자 질문
  ['학원에서 학생 여러 명을 한 계정으로 관리할 수 있나요?', 'docs/APP_GUIDE.md', '학부모·선생님·학원에서 쓸 때'],
  ['학부모인데 아이 성적을 같이 볼 수 있어요?', 'docs/APP_GUIDE.md', '학부모·선생님·학원에서 쓸 때'],
  ['담임 선생님이 상담 자료로 리포트를 출력하려면?', 'docs/APP_GUIDE.md', '학부모·선생님·학원에서 쓸 때'], // 리포트 복사·인쇄 안내 포함
  ['생기부로 AI 상담하려면 어떻게 해요?', 'docs/APP_GUIDE.md', '생기부로 AI 상담하기'],
  ['이 앱은 누가 쓰는 거예요?', 'docs/APP_GUIDE.md', '누가 쓰나요'],
];

for (const [q, path, title] of CASES) {
  test(`검색: ${q}`, () => {
    const top = search(index, q, 3);
    assert.ok(
      top.some((r) => r.chunk.path === path && r.chunk.title.includes(title)),
      `상위 3개: ${top.map((r) => `${r.chunk.path} | ${r.chunk.title}`).join(' / ')}`,
    );
  });
}

test('관련 없는 말뿐인 질문은 조각을 고르지 않는다', () => {
  assert.deepEqual(search(index, '뭐 어떻게 해야 돼?', 5), []);
});

test('보낼 조각은 글자 수 한도 안에서 고른다 (첫 조각은 항상 포함)', () => {
  const picked = selectContext(search(index, '진학 컨설팅 리포트 판단 보류 신뢰도', 8), 2000);
  assert.ok(picked.length >= 1);
  const size = picked.reduce((s, c) => s + c.title.length + c.text.length, 0);
  assert.ok(picked.length === 1 || size <= 2000, String(size));
});
