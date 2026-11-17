// 참고 입결 빌드 테스트. 실행: node --test tools/build_reference_results.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { build, cleanDepartment, parseIncheon, parseSookmyung, OUTPUT } from './build_reference_results.mjs';

test('학과명 정리: 한 글자씩 띄운 이름, 단과대학 조각, PDF 줄바꿈 공백', () => {
  assert.equal(cleanDepartment('국 어 국 문 학 과'), '국어국문학과');
  assert.equal(cleanDepartment('기술 정 보 통 신 공 학 과'), '정보통신공학과');
  assert.equal(cleanDepartment('프랑스언어 · 문화학과'), '프랑스언어·문화학과');
  assert.equal(cleanDepartment('테슬 (TESL) 전공'), '테슬(TESL)전공');
  assert.equal(cleanDepartment('건설환경공 학전공'), '건설환경공학전공');
});

test('숙명여대 표: 절 제목으로 전형을 나누고 소계·전체 줄은 뺀다(가상 수치)', () => {
  const text = [
    '◈ [학생부교과] 지역균형선발 전형',
    '모집단위 모집인원 지원인원 경쟁률 충원인원 충원율',
    '가상학부 8 52 6.50 9 17 113% 2.07',
    '인문계열 소계 10 60 6.00 9 19 90% 2.10',
    '◈ [학생부종합] 소프트웨어인재전형',
    '가상공학부 18 138 7.67 8 26 44% 2.71',
    '전체 18 138 7.67 8 26 44% 2.71',
    '◈ 논술위주 논술우수자전형',
    '가상학과 5 900 180.0 1 6 20% 3.10',
  ].join('\n');
  const rows = parseSookmyung(text, [
    { match: '지역균형선발', track: '지역균형선발 전형' },
    { match: '소프트웨어인재', track: '소프트웨어인재전형' },
  ]);
  assert.deepEqual(rows, [
    { track: '지역균형선발 전형', department: '가상학부', quota: 8, value: 2.07 },
    { track: '소프트웨어인재전형', department: '가상공학부', quota: 18, value: 2.71 },
  ]);
});

test('인천대 표: 자기추천 절의 최종등록자 평균(6번째 수치)을 쓴다(가상 수치)', () => {
  const text = [
    'Ⅲ 2024학년도 학생부종합(자기추천전형)',
    '가 상 학 과 10 97 9.70 4.02 3.37 3.60 5',
    '사회 가상커뮤니케이션학과 10 217 21.70 3.87 3.05 3.18 4',
    'Ⅳ 2024학년도 학생부종합(기회균형전형)',
    '다 른 학 과 10 50 5.00 4.50 4.00 4.10 2',
  ].join('\n');
  assert.deepEqual(parseIncheon(text).map((r) => [r.department, r.value]), [['가상학과', 3.6], ['가상커뮤니케이션학과', 3.18]]);
});

test('번들 파일이 원본 텍스트에서 다시 만든 결과와 같다(원본이 있는 PC에서만)', (t) => {
  if (!existsSync('tools/ocr/test-output/reference-results/숙명여자대학교_2025입결.txt')) return t.skip('원본 텍스트 없음(Git 제외)');
  assert.deepEqual(JSON.parse(readFileSync(OUTPUT, 'utf8')), build());
});

test('번들: 모든 행은 출처가 있고 등급 범위 안이며 공백 없는 학과명', () => {
  const data = JSON.parse(readFileSync(OUTPUT, 'utf8'));
  const ids = new Set(data.sources.map((s) => s.id));
  assert.ok(data.rows.length > 100);
  for (const r of data.rows) {
    assert.ok(ids.has(r.source), r.source);
    assert.ok(r.value >= 1 && r.value <= 9, `${r.department} ${r.value}`);
    assert.ok(!/\s/.test(r.department), r.department);
    assert.ok(r.tracks.length > 0);
  }
  for (const s of data.sources) assert.match(s.mirror, /재게시본/);
});
