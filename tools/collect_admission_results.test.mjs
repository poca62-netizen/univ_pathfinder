import {test} from 'node:test';
import assert from 'node:assert/strict';
import {grid, extractResults, assemble} from './collect_admission_results.mjs';
const college={name:'테스트대',track:'지역균형전형',past:['지역균형전형'],metric:'50%컷'};
const table=`<table><tr><th rowspan="3">지역균형전형 모집단위</th><th rowspan="3">모집인원</th><th colspan="2">최종등록자 학생부등급</th><th colspan="2">환산점수</th></tr><tr><th>50%컷</th><th>70%컷</th><th>50%컷</th><th>70%컷</th></tr><tr></tr><tr><td>컴퓨터공학과</td><td>10</td><td>2.1</td><td>2.4</td><td>980</td><td>970</td></tr></table>`;
test('병합 헤더 복원 및 환산점수와 교과등급 분리',()=>{
  assert.equal(grid(table)[2][0],'지역균형전형 모집단위');
  const parsed=extractResults(`Q2. 2025학년도 전형 결과 ${table}`,college,2026);
  assert.equal(parsed.records.length,1);
  assert.equal(parsed.records[0].central,2.1);
  assert.equal(parsed.records[0].cut70,2.4);
});
test('결과 연도 명시가 없거나 다르면 제외',()=>{
  assert.equal(extractResults(table,college,2026).records.length,0);
  assert.equal(extractResults(`Q2. 2024학년도 전형 결과 ${table}`,college,2026).records.length,0);
});
test('서울캠퍼스에 세종 자료를 섞지 않음',()=>{
  assert.equal(extractResults(`Q2. 2025학년도 전형 결과 ${table}`,{...college,campus:'서울'},2026).records.length,0);
});
test('다른 학과를 합쳐 연도를 채우지 않고 중복 자료 차단',()=>{
  const row={university:'테스트대',department:'컴퓨터공학과',track:'지역균형전형',type:'학생부교과',centralMetric:'50%컷',year:2024,central:2,cut70:2.5,quota:10};
  assert.equal(assemble([row,{...row,department:'소프트웨어학과',year:2025}],{benchmarks:[]}).length,0);
  assert.throws(()=>assemble([row,row],{benchmarks:[]}));
});
