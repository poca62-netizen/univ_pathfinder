import { readFile, writeFile } from 'node:fs/promises';
const input = process.argv[2];
if (!input) throw new Error('Pass the public-data JSON download path.');
const source = JSON.parse((await readFile(input, 'utf8')).replace(/^\uFEFF/, ''));
const admissions = JSON.parse(await readFile('assets/data/admissions_2028.json', 'utf8'));
const names = [...new Set(admissions.rows.map(r => r.university))];
const aliases = { '서울과기대':'서울과학기술대학교', '한국외대':'한국외국어대학교', '한경대':'한경국립대학교', '경인교대':'경인교육대학교', '서울교대':'서울교육대학교' };
const rows = [], missing = [];
for (const name of names) {
  const base = name.replace(/\([^)]*\)/g, '');
  const full = name === '한양대(ERICA)' ? '한양대학교(ERICA)' : aliases[base] ?? (base.endsWith('여대') ? base.slice(0,-2) + '여자대학교' : base.slice(0,-1) + '대학교');
  let matched = source.filter(r => r.UNIV_SE_NM === '대학' && r.UNIV_NM === full);
  if (name.includes('(서울)') || name === '단국대(죽전)') matched = matched.filter(r => r.MAINBRANCH_NM === '본교');
  if (!matched.length) { missing.push(name); continue; }
  for (const r of matched) {
    const annual = Number(r.AVG_REG_AMT);
    if (!Number.isFinite(annual) || annual <= 0) throw new Error(`Invalid tuition: ${name}`);
    rows.push({ university:name, officialName:full, campus:r.MAINBRANCH_NM, region:r.CTPV_NM,
      year:Number(r.CRTR_YR), asOf:r.CRTR_YMD, annualWon:annual,
      scope:name === '한국외대(글로벌)' ? '학교 본교 공시 참고 · 글로벌 캠퍼스 미분리' : '공시 본분교별 학부 연간 평균',
    });
  }
}
await writeFile('assets/data/tuition.json',JSON.stringify({
  source:'한국장학재단 · 전국대학별평균등록금정보표준데이터',
  sourceUrl:'https://www.data.go.kr/data/15107738/standard.do',
  note:'학과별 고지액·2028 확정액·장학금 차감 후 실부담액이 아님', rows,
},null,2)+'\n');
console.log(JSON.stringify({universities:new Set(rows.map(r=>r.university)).size,rows:rows.length,missing}));
