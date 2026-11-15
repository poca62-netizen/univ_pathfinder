// Explicit integration check: fictional records in temporary anonymous accounts.
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const config=JSON.parse(fs.readFileSync('.env.dev.json','utf8').replace(/^\uFEFF/,''));
const project=new URL(config.SUPABASE_URL).hostname.split('.')[0];
if(!/^[a-z]{20}$/.test(project))throw Error('Invalid project');
const accounts=[];let stage='temporary authentication';
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/s','/c',`npx supabase projects api-keys --remote=${project} --output json`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
const admin=keys.find(k=>k.name==='service_role')?.api_key;if(!admin)throw Error('Missing test cleanup access');
async function api(path,body,token,method='POST'){
  const r=await fetch(config.SUPABASE_URL+path,{method,headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${token??config.SUPABASE_PUBLISHABLE_KEY}`,'Content-Type':'application/json',Prefer:'return=representation'},...(body===undefined?{}:{body:JSON.stringify(body)})});
  if(!r.ok)throw Error('Remote request rejected');
  return r.status===204?null:r.json();
}
const grade=(semester=1,subject='가상 국어')=>({id:randomUUID(),calendar_year:2026,school_year:1,semester,subject_name:subject,credit:4,raw_score:88,subject_average:73.5,achievement:'A',grade_rank:2,exam_kind:'semesterSummary',source_confirmed_at:new Date().toISOString(),source_location:'1쪽 · 가상 교과 표'});
const evidence=()=>({id:randomUUID(),calendar_year:2026,school_year:1,category:'세특 · 체육',evidence:'가상 스포츠 활동에서 동료와 협력하고 운동 원리를 탐구함.',source_location:'2쪽 · 가상 체육',source_confirmed_at:new Date().toISOString()});
try{
  for(let i=0;i<2;i++){const a=await api('/auth/v1/signup',{},undefined);assert.ok(a.user?.id&&a.access_token);accounts.push(a);}
  const [owner,other]=accounts;
  const read=(table,a=owner)=>api(`/rest/v1/${table}?select=*&user_id=eq.${owner.user.id}`,undefined,a.access_token,'GET');
  const batch=(grades,items,a=owner)=>api('/rest/v1/rpc/import_school_record',{p_grades:grades,p_evidence:items},a.access_token);
  stage='preserve exams and import both sources';
  const exam={...grade(),user_id:owner.user.id,exam_kind:'midterm'};
  await api('/rest/v1/grade_records',exam,owner.access_token);
  const source=[grade(),grade(1,'가상 수학')];const activity=evidence();
  let r=await batch(source,[activity]);assert.equal(r.grades,2);assert.equal(r.evidence,1);
  const snapshot=await read('grade_records');assert.equal(snapshot.length,3);
  stage='new review and repeat deduplication';
  r=await batch(source.map(g=>({...g,id:randomUUID()})),[{...activity,id:randomUUID()}]);
  assert.equal(r.grades,0);assert.equal(r.skipped_grades,2);assert.equal(r.skipped_evidence,1);
  assert.deepEqual(await read('grade_records'),snapshot);
  stage='transaction rollback';
  await assert.rejects(()=>batch([grade(2)],[{...evidence(),evidence:''}]));
  assert.deepEqual(await read('grade_records'),snapshot);
  stage='excluded numeric subjects and unsupported cohort';
  await assert.rejects(()=>batch([grade(2,'체육1')],[]));
  await assert.rejects(()=>batch([{...grade(2),calendar_year:2024}],[]));
  stage='parallel retries';
  const results=await Promise.all([batch([grade(2)],[]),batch([grade(2)],[])]);
  assert.equal(results.reduce((n,r)=>n+r.grades,0),1);
  stage='owner isolation and career toggle';
  assert.equal((await read('grade_records',other)).length,0);
  assert.equal((await read('school_record_evidence',other)).length,0);
  await api(`/rest/v1/school_record_evidence?id=eq.${activity.id}`,{career_evidence_enabled:false},owner.access_token,'PATCH');
  assert.equal((await read('school_record_evidence'))[0].career_evidence_enabled,false);
  const changed=await api(`/rest/v1/school_record_evidence?id=eq.${activity.id}`,{career_evidence_enabled:true},other.access_token,'PATCH');assert.equal(changed.length,0);
  console.log('PASS: atomic import, exam preservation, semester/evidence dedup, concurrent retries, rollback, cohort guard, RLS, counseling toggle');
}catch{throw Error(`School import integration failed at: ${stage}. Credentials and raw errors suppressed.`);}
finally{
  for(const a of accounts){const r=await fetch(`${config.SUPABASE_URL}/auth/v1/admin/users/${a.user.id}`,{method:'DELETE',headers:{apikey:admin,Authorization:`Bearer ${admin}`}});if(!r.ok)throw Error('Temporary account cleanup failed');}
}
