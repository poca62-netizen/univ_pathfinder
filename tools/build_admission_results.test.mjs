import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parsePage } from './build_admission_results.mjs';

// 가상 대학 결과표. 전형명 위치만 바꿔 가며 확인한다.
const head = (first) => `<tr><th rowspan="2">${first}</th><th rowspan="2">모집단위</th><th rowspan="2">모집인원</th><th rowspan="2">경쟁률</th><th colspan="2">최종등록자 교과성적 학생부등급</th></tr><tr><th>50%</th><th>70%</th></tr>`;
const row = '<tr><td>공학</td><td>컴퓨터공학과</td><td>10</td><td>5.2</td><td>2.1</td><td>2.4</td></tr>';
const page = (body) => `<p>Q 2. 2025 학년도 전형 결과</p>${body}`;
const titles = (html) => parsePage(page(html), '가대', 2026).susi.map((r) => r.track);

test('첫 칸이 열 이름(계열)이면 그다음 칸의 전형명을 쓴다', () => {
  // 이화여대형: 1행 = 계열 | 모집단위 | 전형명(데이터 열 전체), 2·3행 = 열 이름.
  const table = `<table><tr><th rowspan="3">계열</th><th rowspan="3">모집단위</th><th colspan="4">미래인재전형</th></tr><tr><th rowspan="2">모집인원</th><th rowspan="2">경쟁률</th><th colspan="2">최종등록자 교과성적 학생부등급</th></tr><tr><th>50%</th><th>70%</th></tr>${row}</table>`;
  assert.deepEqual(titles(table), ['미래인재전형']);
});

test('"계열적합"처럼 열 이름으로 시작하는 실제 전형명은 그대로 둔다', () => {
  assert.deepEqual(titles(`<table>${head('계열적합')}${row}</table>`), ['계열적합']);
});

test('표에 전형명이 없으면 바로 위 ■ 제목을 쓰고 괄호 주석은 뺀다', () => {
  const table = `<table><tr><th rowspan="2">모집단위</th><th rowspan="2">모집인원</th><th rowspan="2">경쟁률</th><th colspan="2">최종등록자 교과성적 학생부등급</th><th rowspan="2">평가에 반영된 교과목</th></tr><tr><th>50%</th><th>70%</th></tr><tr><td>컴퓨터공학과</td><td>10</td><td>5.2</td><td>2.1</td><td>2.4</td><td>국영수</td></tr></table>`;
  assert.deepEqual(titles(`<p>■ EU 자기추천 (2026 학년도 전형명 변경 ‘EU 면접형’)</p>${table}`), ['eu자기추천']);
});
