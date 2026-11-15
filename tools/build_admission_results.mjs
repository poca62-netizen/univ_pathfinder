// Builds assets/data/admission_results.json from cached adiga pages (see fetch_adiga_pages.mjs).
// Columns are located by header text, never by fixed index. Rows that do not parse cleanly are skipped and counted.
// Usage: node tools/build_admission_results.mjs [--write] [--only=<code>]
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { grid, plain, compact } from './collect_admission_results.mjs';
import { adigaUniversities } from './adiga_universities.mjs';

const cache = 'tools/ocr/test-output/admission-public';
const num = (v) => {
  const s = String(v ?? '').replace(/,/g, '').replace(/%$/, '').replace(/s*:s*1$/, '').trim();
  return /^-?\d+(?:\.\d+)?$/.test(s) ? Number(s) : null;
};

function headerDepth(rows) {
  for (let i = 0; i < Math.min(rows.length, 8); i++) {
    if (rows[i].filter((v) => num(v) !== null).length >= 3) return i;
  }
  return -1;
}

function columnTexts(rows, depth) {
  const width = Math.max(...rows.slice(0, depth).map((r) => r.length));
  return Array.from({ length: width }, (_, i) =>
    compact(rows.slice(0, depth).map((r) => r[i] ?? '').join('|')),
  );
}

const find = (cols, test) => cols.findIndex(test);
const findLast = (cols, test) => cols.map((c, i) => (test(c) ? i : -1)).filter((i) => i >= 0).at(-1) ?? -1;

function trackTitle(rows) {
  const cell = rows[0].find((v) => v && !/모집단위|구분/.test(compact(v)));
  return cell ? compact(cell).replace(/\|/g, '') : null;
}

export function parsePage(html, university, pageYear) {
  const susi = [], jeongsi = [], skipped = [];
  for (const m of html.matchAll(/<table\b[^>]*>[\s\S]*?<\/table>/gi)) {
    const rows = grid(m[0]);
    const depth = headerDepth(rows);
    if (depth < 1) continue;
    const before = plain(html.slice(0, m.index));
    const year = Number([...before.matchAll(/Q\s*2\s*\.\s*(20\d{2})\s*학년도\s*전형\s*결과/g)].at(-1)?.[1]);
    const cols = columnTexts(rows, depth);
    // 2025 results: 50%/70% 환산 + per-area 백분위; 2024 results: 70% 환산 + one "70% cut 평균(백분위)".
    const title = trackTitle(rows);
    // 수시 first: tables with 최종등록자 교과성적 등급 columns, even if they also show 환산·백분위.
    const isSusi = !!title && cols.some((c) => c.includes('모집단위')) &&
      cols.some((c) => /최종등록자/.test(c) && /(교과|학생부)/.test(c) && /등급/.test(c)) && cols.some((c) => /(50|70|80|90)%|평균/.test(c));
    const isJeongsi = !isSusi && cols.some((c) => c.includes('백분위') || c.includes('학생성적')) &&
      cols.some((c) => c.includes('50%cut') || c.includes('70%cut'));
    if (!isJeongsi && !isSusi) continue;
    if (!year || year !== pageYear - 1) { skipped.push({ reason: 'result-year', title }); continue; }
    // Some pages split the header as "모집단|위"; match the prefix.
    const dept = findLast(cols, (c) => c.includes('모집단'));
    const quota = find(cols, (c) => c.includes('최종(a+b)')) >= 0 ? find(cols, (c) => c.includes('최종(a+b)')) : find(cols, (c) => c.includes('모집인원'));
    const comp = find(cols, (c) => c.includes('경쟁률'));
    if (dept < 0 || quota < 0) { skipped.push({ reason: 'columns', title }); continue; }
    if (isSusi) {
      const gradeCol = (c) => /등급/.test(c) && /(교과|학생부)/.test(c) && !/환산/.test(c);
      const cut50 = find(cols, (c) => gradeCol(c) && /(50%|평균)/.test(c));
      const cut70 = find(cols, (c) => gradeCol(c) && /70%/.test(c));
      const cut80 = find(cols, (c) => gradeCol(c) && /80%/.test(c));
      const cut90 = find(cols, (c) => gradeCol(c) && /90%/.test(c));
      if (cut50 < 0 && cut70 < 0 && cut80 < 0 && cut90 < 0) { skipped.push({ reason: 'grade-columns', title }); continue; }
      const metric = cut50 >= 0 ? (/평균/.test(cols[cut50]) ? '평균' : '50%컷') : null;
      const type = /교과/.test(title) ? '학생부교과' : /종합/.test(title) ? '학생부종합' : '미상';
      for (const r of rows.slice(depth)) {
        const d = plain(r[dept] ?? '').replace(/\s+/g, '');
        const q = num(r[quota]);
        const val = (i) => { const v = i >= 0 ? num(r[i]) : null; return v !== null && v >= 1 && v <= 9 ? v : null; };
        const a = val(cut50), b = val(cut70), c8 = val(cut80), c9 = val(cut90);
        if (!d || q === null || (a === null && b === null && c8 === null && c9 === null)) continue;
        susi.push({ university, year, type, track: title, department: d,
          quota: q, competition: comp >= 0 ? num(r[comp]) : null, metric, cut50: a, cut70: b, cut80: c8, cut90: c9 });
      }
    } else {
      // The 모집군 cell sits somewhere left of 모집단위 (one or two 구분 columns).
      // Variants seen: "가", "가군", "‘나’군", "가군 일반전형", "정시 가군 (일반)".
      const groupOf = (r) => {
        for (const v of r.slice(0, dept).map((x) => compact(x ?? '').replace(/['‘’"“”]/g, ''))) {
          const m = v.match(/^([가나다])$/) ?? v.match(/([가나다])군/);
          if (m) return m[1];
        }
        return '';
      };
      const conv50 = find(cols, (c) => c.includes('50%cut') && !c.includes('학생성적') && !c.includes('백분위'));
      const conv70 = find(cols, (c) => c.includes('70%cut') && !c.includes('학생성적') && !c.includes('백분위'));
      const total = find(cols, (c) => c.includes('총점'));
      const avg70 = find(cols, (c) => c.includes('70%cut') && c.includes('평균') && c.includes('백분위'));
      const leaf = (i) => compact(rows[depth - 1][i] ?? '');
      const pct = (which, name) => find(cols, (c, i) => leaf(i) === name && (which === 70 ? /70%/.test(c) : !/70%/.test(c)) && /(백분위|학생성적)/.test(c));
      const keys = { korean: '국', math: '수', inquiry1: '탐1', inquiry2: '탐2', english: '영', history: '한' };
      const at50 = Object.fromEntries(Object.entries(keys).map(([k, n]) => [k, pct(50, n)]));
      const at70 = Object.fromEntries(Object.entries(keys).map(([k, n]) => [k, pct(70, n)]));
      for (const r of rows.slice(depth)) {
        const d = plain(r[dept] ?? '').replace(/\s+/g, '');
        const q = num(r[quota]);
        if (!d || q === null) continue;
        const read = (idx) => Object.fromEntries(Object.entries(idx).map(([k, i]) => [k, i >= 0 ? num(r[i]) : null]));
        const p50 = read(at50), p70 = read(at70);
        const pctOk = (p) => [p.korean, p.math].every((v) => v === null || (v >= 0 && v <= 100));
        if (!pctOk(p50) || !pctOk(p70)) continue;
        const g = groupOf(r);
        if (!g) continue;
        // Common comparison metric across both formats: mean of 국·수·탐(two-subject mean) at the 70% cut.
        const inq = [p70.inquiry1, p70.inquiry2].filter((v) => v !== null);
        let pctAvg70 = avg70 >= 0 ? num(r[avg70]) : null;
        // Some pages write 0 for an unpublished value (e.g. 한국항공대 2024); a real 70% cut percentile is never 0.
        if (pctAvg70 !== null && pctAvg70 <= 0) pctAvg70 = null;
        let pctAvgMethod = pctAvg70 !== null ? '대학 공개 70% cut 평균 백분위' : null;
        if (pctAvg70 === null && p70.korean !== null && p70.math !== null && inq.length) {
          pctAvg70 = Math.round(((p70.korean + p70.math + inq.reduce((a, b) => a + b, 0) / inq.length) / 3) * 100) / 100;
          pctAvgMethod = '국·수·탐(평균) 70% cut 백분위의 평균(앱 계산)';
        }
        if (pctAvg70 !== null && (pctAvg70 < 0 || pctAvg70 > 100)) pctAvg70 = null;
        const conv = (i) => (i >= 0 ? num(r[i]) : null);
        if (pctAvg70 === null && conv(conv70) === null) continue;
        jeongsi.push({ university, year, group: g.replace(/군$/, '') + '군', department: d, quota: q,
          competition: comp >= 0 ? num(r[comp]) : null,
          convert50: conv(conv50), convert70: conv(conv70),
          convertTotal: total >= 0 ? num(r[total]) : null, pctAvg70, pctAvgMethod,
          english70: p70.english !== null && p70.english >= 1 && p70.english <= 9 ? p70.english : null });
      }
    }
  }
  return { susi, jeongsi, skipped };
}

async function main() {
  const only = process.argv.find((a) => a.startsWith('--only='))?.slice(7);
  const files = await readdir(cache);
  const out = { generated: '2026-11-15', source: '대입정보포털 어디가 대학별 전형결과(최종등록자 기준)', sources: [], susi: [], jeongsi: [] };
  const stats = [];
  for (const u of adigaUniversities) {
    if (only && u.code !== only) continue;
    for (const pageYear of [2025, 2026]) {
      const f = `${u.code}-${pageYear}.html`;
      if (!files.includes(f)) continue;
      const html = await readFile(`${cache}/${f}`, 'utf8');
      const { susi, jeongsi, skipped } = parsePage(html, u.name, pageYear);
      out.susi.push(...susi); out.jeongsi.push(...jeongsi);
      out.sources.push({ university: u.name, code: u.code, pageYear, resultYear: pageYear - 1,
        url: `https://www.adiga.kr/ucp/uvt/uni/univDetailSelection.do?menuId=PCUVTINF2000&searchSyr=${pageYear}&unvCd=${u.code}`,
        sha256: createHash('sha256').update(html).digest('hex'), susiRows: susi.length, jeongsiRows: jeongsi.length });
      stats.push({ u: u.name, pageYear, susi: susi.length, jeongsi: jeongsi.length, skipped: skipped.length });
    }
  }
  console.log(stats.map((s) => `${s.u} ${s.pageYear}: 수시 ${s.susi} 정시 ${s.jeongsi}${s.skipped ? ' (건너뜀 ' + s.skipped + ')' : ''}`).join('\n'));
  console.log(JSON.stringify({ susi: out.susi.length, jeongsi: out.jeongsi.length, pages: out.sources.length }));
  if (process.argv.includes('--write')) await writeFile('assets/data/admission_results.json', JSON.stringify(out) + '\n');
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) await main();
