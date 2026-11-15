// Explicit deployed-auth test. Test credentials/tokens are never printed.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const config=JSON.parse(fs.readFileSync('.env.dev.json','utf8').replace(/^\uFEFF/,''));
const project=new URL(config.SUPABASE_URL).hostname.split('.')[0];
if(!/^[a-z]{20}$/.test(project))throw Error('Invalid project');
const keys=JSON.parse(execFileSync('cmd.exe',['/d','/s','/c',`npx supabase projects api-keys --remote=${project} --output json`],{encoding:'utf8',stdio:['ignore','pipe','pipe']}));
const key=keys.find(k=>k.name==='service_role').api_key;
const adminHeaders={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
const headers={apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'};
const nickname=`test_${crypto.randomUUID().replaceAll('-','').slice(0,12)}`;
let uid,stage='registration race';
async function auth(action,pin='0786',name=nickname){return await fetch(`${config.SUPABASE_URL}/functions/v1/nickname-auth`,{method:'POST',headers,body:JSON.stringify({action,nickname:name,pin})});}
async function session(response){assert.equal(response.status,200);const data=await response.json();assert.equal(data.pin,undefined);assert.equal(data.pin_hash,undefined);const token=await fetch(`${config.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`,{method:'POST',headers,body:JSON.stringify({refresh_token:data.refresh_token})});assert.equal(token.status,200);return await token.json();}
try{
 const race=await Promise.all([auth('register'),auth('register','0786',nickname.toUpperCase())]);
 assert.deepEqual(race.map(r=>r.status).sort(),[200,409]);
 const first=await session(race.find(r=>r.status===200));uid=first.user.id;
 stage='fresh login keeps account';const second=await session(await auth('login'));assert.equal(second.user.id,uid);
 stage='duplicate name';assert.equal((await auth('register')).status,409);
 stage='four digits only';for(const pin of ['123','12345','abcd'])assert.equal((await auth('login',pin)).status,400);
 stage='private credential table';
 const userHeaders={...headers,Authorization:`Bearer ${second.access_token}`};
 const exposed=await fetch(`${config.SUPABASE_URL}/rest/v1/nickname_accounts?select=*`,{headers:userHeaders});assert.ok([401,403].includes(exposed.status));
 const rpc=await fetch(`${config.SUPABASE_URL}/rest/v1/rpc/authenticate_nickname`,{method:'POST',headers:userHeaders,body:JSON.stringify({p_nickname:nickname,p_pin:'0786'})});assert.ok([401,403,404].includes(rpc.status));
 stage='five wrong PINs lock correct login';
 for(let i=0;i<5;i++){assert.equal((await auth('login','9999')).status,i<4?401:429);}
 assert.equal((await auth('login')).status,429);
 console.log('PASS: concurrent nickname uniqueness, fresh-session identity, duplicate rejection, four-digit validation, credential isolation, five-failure lock.');
}catch{console.error(`FAIL: ${stage}. Credentials and upstream responses suppressed.`);process.exitCode=1;}
finally{
 // Find only the uniquely generated test account, even if an assertion failed early.
 if(!uid){const found=await fetch(`${config.SUPABASE_URL}/rest/v1/nickname_accounts?select=user_id&nickname_key=eq.${nickname}`,{headers:adminHeaders});if(found.ok)uid=(await found.json())[0]?.user_id;}
 if(uid){const deleted=await fetch(`${config.SUPABASE_URL}/auth/v1/admin/users/${uid}`,{method:'DELETE',headers:adminHeaders});if(!deleted.ok){console.error('Test Auth cleanup failed.');process.exitCode=1;}}
 const cleaned=await fetch(`${config.SUPABASE_URL}/rest/v1/nickname_login_attempts?nickname_key=eq.${nickname}`,{method:'DELETE',headers:adminHeaders});if(!cleaned.ok){console.error('Test attempt cleanup failed.');process.exitCode=1;}
}
