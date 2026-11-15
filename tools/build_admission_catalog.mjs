import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

// Parse JSON only. Never execute scripts or copy page decoration/author metadata.
const source = process.argv[2];
if (!source) throw new Error('Pass the reference HTML path.');
const html = await readFile(source, 'utf8');
const match = html.match(/<script\s+id="data"\s+type="application\/json">([\s\S]*?)<\/script>/);
if (!match) throw new Error('Admission data JSON not found.');
const data = JSON.parse(match[1]);
const metro = new Set(data.sheets.filter(s => ['서울', '경기+인천'].includes(s.name)).flatMap(s => s.rows.map(r => r.u)));
metro.add('서울교대');
metro.add('경인교대');
const rows = [];
const seen = new Set();
for (const sheet of data.sheets) for (const row of sheet.rows) {
  if (!metro.has(row.u)) continue;
  const record = { region: sheet.name === '경기+인천' || row.u === '경인교대' ? '경기·인천' : '수도권', section: sheet.name };
  for (const [key, field] of Object.entries({ u:'university', m:'department', t:'type', j:'name', n:'quota', q:'eligibility', rn:'recommendation', rb:'recommender', me:'selection', s:'minimum' })) {
    record[field] = String(row[key] ?? '');
  }
  const key = JSON.stringify(Object.values(record).slice(2));
  if (!seen.has(key)) { seen.add(key); rows.push(record); }
}
await mkdir('assets/data', { recursive: true });
await writeFile('assets/data/admissions_2028.json', JSON.stringify({ year:2028, source:path.basename(source), status:'사용자 제공 정리 자료 · 대학별 공식 원문 대조 전', rows }, null, 2) + '\n');
console.log(JSON.stringify({ universities:new Set(rows.map(r => r.university)).size, tracks:rows.length, departmentRows:rows.filter(r=>r.department).length }));
