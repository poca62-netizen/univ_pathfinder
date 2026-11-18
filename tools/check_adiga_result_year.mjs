// 어디가에 새 학년도 입결이 공개됐는지 확인한다(외부 조회: 대학 3곳 페이지, 요청 간격 2초).
// 공개됐으면 tools/fetch_adiga_pages.mjs로 전체를 받고 tools/build_admission_results.mjs로 다시 만든다.
// 캐시(tools/ocr/test-output/admission-public)는 건드리지 않는다.
// 사용: node tools/check_adiga_result_year.mjs [pageYear=2027]   (2027 페이지 = 2026학년도 결과)
import { parsePage } from './build_admission_results.mjs';
import { adigaUniversities } from './adiga_universities.mjs';

const pageYear = Number(process.argv[2] ?? 2027);
const resultYear = pageYear - 1;
const sample = ['세종대', '가톨릭대', '경희대'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let published = 0;
for (const name of sample) {
  const u = adigaUniversities.find((x) => x.name === name);
  const url = `https://www.adiga.kr/ucp/uvt/uni/univDetailSelection.do?menuId=PCUVTINF2000&searchSyr=${pageYear}&unvCd=${u.code}`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(30000), headers: { 'User-Agent': 'Mozilla/5.0 (univ-pathfinder data refresh)' } });
    if (!res.ok) throw Error(`HTTP ${res.status}`);
    const page = parsePage(await res.text(), name, pageYear);
    const rows = [...(page.susi ?? []), ...(page.jeongsi ?? [])].length;
    if (rows > 0) published++;
    console.log(JSON.stringify({ university: name, resultYear, rows }));
  } catch (e) {
    console.log(JSON.stringify({ university: name, resultYear, error: String(e.message ?? e) }));
  }
  await sleep(2000);
}
console.log(published > 0
  ? `${resultYear}학년도 결과가 ${published}/${sample.length}개 대학에서 읽힘 → 전체 재수집 진행`
  : `${resultYear}학년도 결과 표가 아직 없음(공개 전 또는 표 형식 변경). 공개 후 다시 확인`);
