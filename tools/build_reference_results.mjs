// 참고 입결(예측에 쓰지 않음) 생성.
// 어디가 결과표에 없어 판단 보류인 전형 중, 대학이 직접 공개한 수시 입시결과 PDF(재게시본)에 결과가 있는 것을
// 학과별 수치로 옮긴다. 지표가 어디가(최종 등록자 50%·70% 컷)와 달라 예측(안정·적정 등)에는 쓰지 않고
// 판단 보류 카드에 참고로만 보여 준다(사용자 결정, 개발 로그 96).
//
// 입력: tools/ocr/test-output/reference-results/*.txt (PDF를 pdf.js로 텍스트화한 것, Git 제외)
// 실행: node tools/build_reference_results.mjs [--write]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const DIR = 'tools/ocr/test-output/reference-results';
const MIRROR = 'https://cdn013.negagea.net/dgsmidc/omr/seoul/web';
export const OUTPUT = 'assets/data/admission_reference_results.json';

// 학과명 칸의 글자 사이 공백(인천대 표)과 가운뎃점 앞뒤 공백을 정리한다.
export function cleanDepartment(s) {
  const t = s.trim().replace(/\s*·\s*/g, '·');
  // "국 어 국 문 학 과"처럼 한 글자씩 띄운 이름만 붙인다. 앞에 단과대학 이름 조각이 붙어 있으면
  // ("기술 정 보 통 신 공 학 과") 끝의 한 글자씩 띄운 부분만 학과명으로 쓴다.
  const run = t.match(/(?:^|\s)((?:\S\s)+\S)$/);
  if (run && run[1].split(' ').every((x) => x.length === 1)) return run[1].replace(/\s/g, '');
  // 학과명에는 공백이 없다: PDF 줄바꿈·괄호 앞뒤로 생긴 공백("테슬 (TESL) 전공", "건설환경공 학전공")을 지운다.
  return t.replace(/\s+/g, '');
}

// 숙명여대: "◈ … 전형" 절마다 "모집단위 모집인원 지원인원 경쟁률 충원인원 전체합격인원 충원율 교과등급평균".
export function parseSookmyung(text, sections) {
  const out = [];
  const lines = text.split(/\r?\n/);
  let current = null;
  for (const line of lines) {
    if (line.includes('◈')) {
      const flat = line.replace(/[\s[\]()]/g, '');
      current = sections.find((s) => flat.includes(s.match)) ?? null;
      continue;
    }
    if (!current) continue;
    const m = line.match(/^(.+?)\s+(\d+)\s+([\d,]+)\s+([\d.]+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\d\.\d{2})$/);
    if (!m) continue;
    const department = cleanDepartment(m[1]);
    if (/소계|전체|합계/.test(department)) continue;
    out.push({ track: current.track, department, quota: Number(m[2]), value: Number(m[8]) });
  }
  return out;
}

// 인천대 2024 학생부종합(자기추천전형): "모집단위 모집인원 지원인원 경쟁률 지원자평균 최초합격자평균 최종등록자평균 예비순위".
export function parseIncheon(text) {
  const out = [];
  const start = text.indexOf('2024학년도 학생부종합(자기추천전형)');
  const end = text.indexOf('2024학년도 학생부종합(기회균형전형)', start);
  if (start < 0) return out;
  for (const line of text.slice(start, end > 0 ? end : undefined).split(/\r?\n/)) {
    // 앞에 단과대학 이름이 붙은 줄도 있다("사회 미디어커뮤니케이션학과 …").
    const m = line.match(/^(.+?)\s+(\d+)\s+(\d+)\s+([\d.]+)\s+(\d\.\d{2})\s+(\d\.\d{2})\s+(\d\.\d{2})\s+(\d+)$/);
    if (!m) continue;
    let name = m[1].replace(/^(인문|자연|사회|과학|글로벌|정경|대학|공과|정보기술|경영|예술체육|사범|도시과학|생명과학기술|동북아국제통상물류|법학부?)\s+(?=\S)/, '');
    name = cleanDepartment(name);
    out.push({ track: '자기추천전형', department: name, quota: Number(m[2]), value: Number(m[7]) });
  }
  return out;
}

const SOURCES = [
  {
    id: 'sookmyung-2025', university: '숙명여대', year: 2025, file: '숙명여자대학교_2025입결.txt',
    title: '숙명여자대학교 2025학년도 수시모집 전형 결과',
    url: `${MIRROR}/univ_info2026/숙명여자대학교/숙명여자대학교_2025학년도_수시입시결과.pdf`,
    metric: '합격자 평균(최초+충원, 교과등급 단순 평균)',
    parse: (t) => parseSookmyung(t, [
      { match: '지역균형선발', track: '지역균형선발 전형', to: ['지역균형선발전형'] },
      { match: '소프트웨어인재', track: '소프트웨어인재전형', to: ['소프트웨어인재전형'] },
      { match: '숙명인재면접형', track: '숙명인재(면접형) 전형', to: ['숙명인재(면접형)전형'] },
    ]),
  },
  {
    id: 'sookmyung-2024', university: '숙명여대', year: 2024, file: '숙명여자대학교_2024입결.txt',
    title: '숙명여자대학교 2024학년도 수시모집 전형 결과',
    url: `${MIRROR}/univ_info2025/숙명여자대학교/숙명여자대학교_2024학년도_수시입시결과.pdf`,
    metric: '합격자 평균(최초+충원, 교과등급 단순 평균)',
    parse: (t) => parseSookmyung(t, [
      { match: '지역균형선발', track: '지역균형선발 전형', to: ['지역균형선발전형'] },
      { match: '숙명인재면접형', track: '숙명인재(면접형) 전형', to: ['숙명인재(면접형)전형'] },
    ]),
  },
  {
    id: 'incheon-2024', university: '인천대', year: 2024, file: '인천대학교_2024입결.txt',
    title: '인천대학교 2024학년도 수시 입시결과',
    url: `${MIRROR}/univ_info2025/인천대학교/인천대학교_2024학년도_수시입시결과.pdf`,
    metric: '최종등록자 평균(교과등급)',
    note: '2024 자기추천전형은 면접형·서류형으로 나뉘기 전',
    parse: (t) => parseIncheon(t),
  },
];
// 원본 절 이름 → 2028 전형명(같은 전형인지는 검증 전이며 참고로만 연결한다).
const TO = {
  '지역균형선발 전형': ['지역균형선발전형'],
  '소프트웨어인재전형': ['소프트웨어인재전형'],
  '숙명인재(면접형) 전형': ['숙명인재(면접형)전형'],
  '자기추천전형': ['자기추천(면접형)전형', '자기추천(서류형)전형'],
};

export function build(dir = DIR) {
  const sources = [];
  const rows = [];
  for (const s of SOURCES) {
    const path = `${dir}/${s.file}`;
    if (!existsSync(path)) throw new Error(`없음: ${path}`);
    const parsed = s.parse(readFileSync(path, 'utf8'));
    if (!parsed.length) throw new Error(`표를 읽지 못함: ${s.file}`);
    sources.push({ id: s.id, university: s.university, year: s.year, title: s.title, url: s.url, metric: s.metric, note: s.note ?? '', mirror: '재게시본(대학 공식 링크 미확인)' });
    for (const r of parsed) rows.push({ source: s.id, university: s.university, year: s.year, sourceTrack: r.track, tracks: TO[r.track], department: r.department, quota: r.quota, value: r.value, metric: s.metric });
  }
  return {
    checkedAt: '2026-11-17',
    note: '참고 입결(예측에 쓰지 않음). 어디가 결과표에 없어 판단 보류인 전형에 대해 대학이 공개한 입시결과의 학과별 수치를 그대로 옮겼다. 지표가 어디가(최종 등록자 50%·70% 컷)와 다르고(합격자 평균은 등록자 기준보다 좋게 나오는 경향), 2028 전형과 같은 기준인지 검증하지 않았다.',
    sources,
    rows,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const data = build();
  const by = {};
  for (const r of data.rows) by[`${r.university} ${r.year} ${r.sourceTrack}`] = (by[`${r.university} ${r.year} ${r.sourceTrack}`] ?? 0) + 1;
  console.log(by);
  if (process.argv.includes('--write')) writeFileSync(OUTPUT, JSON.stringify(data, null, 1) + '\n');
}
