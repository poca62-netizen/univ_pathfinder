// Politely downloads adiga university-detail pages (one request every 1.5 s) into a Git-ignored cache.
// Usage: node tools/fetch_adiga_pages.mjs [pageYear ...]   (default 2026 2027 = results of 2025, 2026)
import { mkdir, writeFile, access } from 'node:fs/promises';
import { adigaUniversities } from './adiga_universities.mjs';

const cache = 'tools/ocr/test-output/admission-public';
const years = process.argv.slice(2).map(Number).filter(Boolean);
const pageYears = years.length ? years : [2026, 2027];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
await mkdir(cache, { recursive: true });
let fetched = 0, skipped = 0, failed = 0;
for (const u of adigaUniversities) {
  for (const pageYear of pageYears) {
    const path = `${cache}/${u.code}-${pageYear}.html`;
    try { await access(path); skipped++; continue; } catch { /* not cached */ }
    const url = `https://www.adiga.kr/ucp/uvt/uni/univDetailSelection.do?menuId=PCUVTINF2000&searchSyr=${pageYear}&unvCd=${u.code}`;
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(30000), headers: { 'User-Agent': 'Mozilla/5.0 (univ-pathfinder data refresh)' } });
      if (!res.ok) throw Error(`HTTP ${res.status}`);
      await writeFile(path, await res.text());
      fetched++;
    } catch (e) {
      failed++;
      console.log(JSON.stringify({ university: u.name, pageYear, error: String(e.message ?? e) }));
    }
    await sleep(1500);
  }
}
console.log(JSON.stringify({ fetched, skipped, failed }));
