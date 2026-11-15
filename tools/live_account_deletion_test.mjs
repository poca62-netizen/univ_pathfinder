// Explicit deployed account-deletion test with a throwaway virtual account.
// Writes to the remote DB. Run only with the user's approval. Credentials/tokens are never printed.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const config=JSON.parse(fs.readFileSync('.env.dev.json','utf8').replace(/^﻿/,''));
const base=config.SUPABASE_URL;
const project=new URL(base).hostname.split('.')[0];
if(!/^[a-z]{20}$/.test(project))throw Error('Invalid project');
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/s','/c',`npx supabase projects api-keys --remote=${project} --output json`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
const key=keys.find(k=>k.name==='service_role').api_key;
const admin={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'};
const nickname=`test_${crypto.randomUUID().replaceAll('-','').slice(0,12)}`;
const pin='0786';
const uids=new Set();
let stage='register virtual account';

const register=()=>fetch(`${base}/functions/v1/nickname-auth`,{method:'POST',headers,body:JSON.stringify({action:'register',nickname,pin})});
async function session(response){
  assert.equal(response.status,200);
  const data=await response.json();
  const token=await fetch(`${base}/auth/v1/token?grant_type=refresh_token`,{method:'POST',headers,body:JSON.stringify({refresh_token:data.refresh_token})});
  assert.equal(token.status,200);
  const s=await token.json();uids.add(s.user.id);return s;
}
const del=(body,token)=>fetch(`${base}/functions/v1/delete-account`,{method:'POST',headers:token?{...headers,Authorization:`Bearer ${token}`}:headers,body:JSON.stringify(body)});
// Row counts via read-only SQL (service_role has no table grant on user data tables).
function counts(uid){
  if(!/^[0-9a-f-]{36}$/.test(uid)||!/^test_[0-9a-f]{12}$/.test(nickname))throw Error('unsafe id');
  const sql=`select (select count(*) from auth.users where id='${uid}')::int as auth_user,`+
    `(select count(*) from public.profiles where id='${uid}')::int as profile,`+
    `(select count(*) from public.mock_exam_records where user_id='${uid}')::int as mock_exam,`+
    `(select count(*) from public.grade_records where user_id='${uid}')::int as grade,`+
    `(select count(*) from public.nickname_accounts where nickname_key='${nickname}')::int as credential,`+
    `(select count(*) from public.nickname_login_attempts where nickname_key='${nickname}')::int as attempts`;
  // Relative, space-free path under a Git-ignored folder: cmd.exe passes it without quoting.
  const file=`tools/ocr/test-output/account_deletion_${process.pid}.sql`;
  fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,sql);
  try{
    const out=execFileSync('cmd.exe',['/d','/s','/c',`npx supabase db query --remote=${project} --read-only --output json --file ${file}`],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
    return JSON.parse(out).rows[0];
  }finally{fs.rmSync(file,{force:true});}
}
const userExists=async(id)=>(await fetch(`${base}/auth/v1/admin/users/${id}`,{headers:admin})).ok;

try{
  const s=await session(await register());const uid=s.user.id;
  const user={...headers,Authorization:`Bearer ${s.access_token}`};

  stage='seed virtual mock exam row';
  const seeded=await fetch(`${base}/rest/v1/mock_exam_records`,{method:'POST',headers:{...user,Prefer:'return=minimal'},
    body:JSON.stringify({user_id:uid,calendar_year:2026,school_year:1,exam_month:6,subject:'국어',grade_rank:3})});
  assert.equal(seeded.status,201);
  const before=counts(uid);
  assert.equal(before.auth_user,1);assert.equal(before.profile,1);assert.equal(before.mock_exam,1);assert.equal(before.credential,1);

  stage='reject request without session';
  assert.equal((await del({pin})).status,401);

  stage='reject malformed PIN';
  assert.equal((await del({pin:'12a4'},s.access_token)).status,400);

  stage='reject wrong PIN and keep everything';
  const wrong=await del({pin:'9999'},s.access_token);
  assert.equal(wrong.status,401);assert.equal((await wrong.json()).error,'INVALID_CREDENTIALS');
  const kept=counts(uid);assert.equal(kept.auth_user,1);assert.equal(kept.mock_exam,1);assert.equal(kept.credential,1);

  stage='delete with correct PIN';
  const ok=await del({pin},s.access_token);
  assert.equal(ok.status,200);assert.deepEqual(await ok.json(),{deleted:true});

  stage='account and data gone';
  assert.equal(await userExists(uid),false);
  assert.deepEqual(counts(uid),{auth_user:0,profile:0,mock_exam:0,grade:0,credential:0,attempts:0});

  stage='old session cannot delete again';
  assert.notEqual((await del({pin},s.access_token)).status,200);

  stage='nickname reusable immediately';
  const again=await session(await register());
  assert.notEqual(again.user.id,uid);

  console.log('PASS: no-session 401, malformed PIN 400, wrong PIN 401 with data kept, correct PIN deletes Auth user + mock exam + profile + nickname credential + attempt row, old session rejected, nickname re-registrable.');
}catch(e){
  if(e instanceof assert.AssertionError)console.error(`assert: actual=${JSON.stringify(e.actual)} expected=${JSON.stringify(e.expected)}`);
  else console.error(`error: ${String(e?.stderr??e?.message??e).replace(/sb_secret_w+|eyJ[w.-]+/g,"[redacted]").slice(0,400)}`);
  console.error(`FAIL: ${stage}. Credentials and upstream responses suppressed.`);process.exitCode=1;
}finally{
  // Remove every virtual account this run created, even after an early failure.
  const found=await fetch(`${base}/rest/v1/nickname_accounts?select=user_id&nickname_key=eq.${nickname}`,{headers:admin});
  if(found.ok)for(const row of await found.json())uids.add(row.user_id);
  for(const id of uids){
    const r=await fetch(`${base}/auth/v1/admin/users/${id}`,{method:'DELETE',headers:admin});
    if(!r.ok&&r.status!==404){console.error('Test Auth cleanup failed.');process.exitCode=1;}
  }
  const cleaned=await fetch(`${base}/rest/v1/nickname_login_attempts?nickname_key=eq.${nickname}`,{method:'DELETE',headers:admin});
  if(!cleaned.ok){console.error('Test attempt cleanup failed.');process.exitCode=1;}
}
