import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const colleges = [
  { name:'홍익대(서울)', id:'0000212', title:'홍익대학교', track:'학교장추천자전형', past:['학교장추천자전형'], metric:'등록자 평균', campus:'서울' },
  { name:'광운대', id:'0000074', title:'광운대학교', track:'지역균형전형', past:['지역균형전형'], metric:'50%컷' },
  { name:'국민대', id:'0000078', title:'국민대학교', track:'교과우수자(학교장추천)Ⅰ전형', past:['교과성적우수자전형','교과우수자전형'], metric:'50%컷' },
  { name:'숭실대', id:'0000143', title:'숭실대학교', track:'교과우수자전형', past:['학생부우수자전형','교과우수자전형'], metric:'50%컷' },
  { name:'경희대', id:'0000066', title:'경희대학교', track:'지역균형전형', past:['지역균형전형'], metric:'50%컷' },
];
const cache='tools/ocr/test-output/admission-public';
export const compact = s => s.replace(/[\s\u00a0·ㆍ・]/g,'').toLowerCase();
export function plain(s) {
  return s.replace(/<script\b[\s\S]*?<\/script>/gi,'').replace(/<style\b[\s\S]*?<\/style>/gi,'')
    .replace(/<br\s*\/?\s*>/gi,' ').replace(/<[^>]*>/g,' ')
    .replace(/&#x([\da-f]+);/gi,(_,n)=>String.fromCodePoint(parseInt(n,16)))
    .replace(/&#(\d+);/g,(_,n)=>String.fromCodePoint(Number(n)))
    .replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"')
    .replace(/\s+/g,' ').trim();
}

export function grid(table) {
  const rows=[];
  for(const [rowIndex,m] of [...table.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)].entries()) {
    const row=rows[rowIndex]??=[]; let col=0;
    for(const cell of m[1].matchAll(/<(td|th)\b([^>]*)>([\s\S]*?)<\/\1>/gi)) {
      while(row[col]!==undefined)col++;
      const span=(name)=>Number(cell[2].match(new RegExp(`${name}\\s*=\\s*["']?(\\d+)`,'i'))?.[1]??1);
      const w=span('colspan'),h=span('rowspan');
      if(w<1||h<1||w>50||h>1000)throw Error('Invalid table span');
      for(let y=0;y<h;y++)for(let x=0;x<w;x++)(rows[rowIndex+y]??=[])[col+x]=plain(cell[3]);
      col+=w;
    }
  }
  return rows;
}

export function inspect(html) {
  return [...html.matchAll(/<table\b[^>]*>[\s\S]*?<\/table>/gi)].map(m=>grid(m[0])).filter(rows=>
    rows.slice(0,5).flat().some(v=>compact(v).includes('최종등록자')),
  ).map(rows=>({header:rows.slice(0,4),sample:rows.slice(4,6),length:rows.length}));
}

export function extractResults(html,c,pageYear) {
  const records=[], rejected=[];
  for(const table of html.matchAll(/<table\b[^>]*>[\s\S]*?<\/table>/gi)) {
    const rows=grid(table[0]);
    const head=compact(rows.slice(0,4).flat().join(' '));
    if(!c.past.some(t=>head.includes(compact(t))) || /농어촌|기회균형|기초생활|논술/.test(head))continue;
    const before=plain(html.slice(0,table.index));
    const years=[...before.matchAll(/Q\s*2\s*\.\s*(20\d{2})\s*학년도\s*전형\s*결과/g)];
    const year=Number(years.at(-1)?.[1]);
    if(!year || year!==pageYear-1){rejected.push({reason:'결과학년도 확인 불가'});continue;}
    const header=rows.slice(0,5);
    const gradeIndices=[];
    for(let i=0;i<Math.max(...header.map(r=>r.length));i++) {
      if(header.some(r=>/최종등록자.*(?:교과성적.*등급|학생부등급)/.test(compact(r[i]??''))))gradeIndices.push(i);
    }
    if(gradeIndices.length!==2){rejected.push({reason:'교과등급 열 2개 미확인'});continue;}
    const [centralCol,cutCol]=gradeIndices;
    const majorCols=rows[0].map((v,i)=>compact(v).includes('모집단위')?i:-1).filter(i=>i>=0);
    const majorCol=majorCols.at(-1);
    const quotaCol=header.flatMap(r=>r.map((v,i)=>compact(v)==='모집인원'?i:-1)).find(i=>i>=0);
    if(majorCol===undefined || quotaCol===undefined){rejected.push({reason:'모집단위/인원 열 미확인'});continue;}
    const centralLabels=header.map(r=>compact(r[centralCol]??''));
    const metric=centralLabels.some(v=>v==='평균') || c.metric==='등록자 평균' ? '등록자 평균' : centralLabels.some(v=>v.includes('50%'))?'50%컷':null;
    if(!metric){rejected.push({reason:'중앙 지표 미확인'});continue;}
    let campus=null;
    for(const row of rows) {
      const department=plain(row[majorCol]??'').replace(/\s+/g,'');
      const explicit=row.slice(0,majorCol).find(v=>['서울','세종'].includes(compact(v)));
      if(explicit)campus=compact(explicit);
      if(department.startsWith('서울캠퍼스'))campus='서울';
      if(department.startsWith('세종캠퍼스'))campus='세종';
      if(c.campus && campus!==c.campus)continue;
      if(!department || department==='모집단위')continue;
      const numeric=v=>/^\d+(?:\.\d+)?$/.test(String(v??'').trim())?Number(v):null;
      const central=numeric(row[centralCol]),cut70=numeric(row[cutCol]),quota=numeric(row[quotaCol]);
      if(central===null||cut70===null||central<1||central>9||cut70<1||cut70>9||quota===null)continue;
      records.push({university:c.name,department,track:c.track,type:'학생부교과',centralMetric:metric,
        year,central,cut70,quota,sourcePageYear:pageYear});
    }
  }
  return {records,rejected};
}

export function assemble(records,original) {
  const groups=new Map();
  for(const r of records) {
    // An explicit, documented administrative alias, never fuzzy department matching.
    const department=r.university==='국민대' && r.department==='경영학부경영학전공'?'경영학부':r.department;
    const key=JSON.stringify([r.university,department,r.track]);
    const b=groups.get(key)??{university:r.university,department,track:r.track,type:r.type,centralMetric:r.centralMetric,
      mappingNote:'과거 교과전형의 학업 참고 비교입니다. 2028 모집단위·반영 방식·지원조건의 동일성을 확정하지 않습니다.',history:[]};
    if(b.centralMetric!==r.centralMetric) { b.mixedMetrics=true; }
    if(b.history.some(h=>h.year===r.year))throw Error(`Duplicate source row: ${key}/${r.year}`);
    b.history.push({year:r.year,central:r.central,cut70:r.cut70,quota:r.quota,centralMetric:r.centralMetric});
    groups.set(key,b);
  }
  // Preserve the original eight manually verified anchor values.
  for(const old of original.benchmarks) {
    const b=groups.get(JSON.stringify([old.university,old.department,old.track]));
    if(!b)throw Error(`Missing verified anchor: ${old.university}/${old.department}`);
    for(const h of old.history) {
      const found=b.history.find(v=>v.year===h.year);
      if(!found || found.central!==h.central || found.cut70!==h.cut70)throw Error(`Anchor mismatch: ${old.university}/${old.department}/${h.year}`);
    }
    b.mappingNote=old.mappingNote??b.mappingNote;
  }
  return [...groups.values()].filter(b=>b.history.length>=2).map(b=>({...b,history:b.history.sort((a,b)=>a.year-b.year)}));
}

async function main() {
  await mkdir(cache,{recursive:true});
  const offline=process.argv.includes('--offline');
  const inspectOnly=process.argv.includes('--inspect');
  const sources=[], records=[], rejected=[];
  for(const c of (inspectOnly ? colleges.slice(0,1) : colleges))for(const pageYear of (inspectOnly?[2026]:[2025,2026,2027])) {
    const url=`https://www.adiga.kr/ucp/uvt/uni/univDetailSelection.do?menuId=PCUVTINF2000&searchSyr=${pageYear}&unvCd=${c.id}`;
    const path=`${cache}/${c.id}-${pageYear}.html`;
    let html;
    if(offline)html=await readFile(path,'utf8');
    else {
      const response=await fetch(url,{signal:AbortSignal.timeout(30000)});
      if(!response.ok)throw Error(`Public source HTTP ${response.status}`);
      html=await response.text();
      if(!plain(html).includes(c.title))throw Error(`University mismatch: ${c.name}`);
      await writeFile(path,html);
    }
    const tables=inspect(html);
    const parsed=extractResults(html,c,pageYear); records.push(...parsed.records);rejected.push(...parsed.rejected.map(r=>({...r,university:c.name,pageYear})));
    sources.push({university:c.name,pageYear,url,sha256:createHash('sha256').update(html).digest('hex'),tables,recordCount:parsed.records.length});
    console.log(JSON.stringify({university:c.name,pageYear,tables:tables.length,records:parsed.records.length,...(inspectOnly?{tables}:{} )}));
  }
  await writeFile(`${cache}/inspection.json`,JSON.stringify(sources,null,2));
  await writeFile(`${cache}/records.json`,JSON.stringify({records,rejected},null,2));
  if(process.argv.includes('--write')) {
    const path='assets/data/admission_comparison.json';
    const original=JSON.parse(await readFile(path,'utf8'));
    const benchmarks=assemble(records,original);
    const publishedSources=sources.filter(s=>s.recordCount>0).map(s=>({university:s.university,year:s.pageYear-1,url:s.url,sha256:s.sha256,note:`${s.pageYear-1}학년도 결과 · 공개 교과등급 원문` }));
    await writeFile(path,JSON.stringify({...original,benchmarks,sources:publishedSources},null,2)+'\n');
    console.log(JSON.stringify({universities:new Set(benchmarks.map(b=>b.university)).size,departments:benchmarks.length,historyRows:benchmarks.reduce((n,b)=>n+b.history.length,0)}));
  }
}
if(process.argv[1] && fileURLToPath(import.meta.url)===process.argv[1])await main();
