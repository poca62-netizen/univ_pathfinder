// Explicit administrator migration; credentials are read only from ignored local input.
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const config=JSON.parse(fs.readFileSync('.env.dev.json','utf8').replace(/^\uFEFF/,''));
const plan=JSON.parse(fs.readFileSync('tools/ocr/test-output/account-bootstrap.json','utf8').replace(/^\uFEFF/,''));
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
if(!uuid.test(plan.source)||!uuid.test(plan.target)||plan.source===plan.target||!/^[a-z0-9가-힣_]{2,20}$/.test(plan.nickname)||!/^\d{4}$/.test(plan.pin))throw Error('Invalid migration plan');
const project=new URL(config.SUPABASE_URL).hostname.split('.')[0];
if(!/^[a-z]{20}$/.test(project))throw Error('Invalid project');
const cli=command=>execFileSync('cmd.exe',['/d','/s','/c',command],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
let stage='administrator access';
try{
 const keys=JSON.parse(cli(`npx supabase projects api-keys --remote=${project} --output json`));
 const key=keys.find(k=>k.name==='service_role')?.api_key;
 if(!key)throw Error('Missing key');
 const headers={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
 async function api(path,body,method='POST'){
  const response=await fetch(`${config.SUPABASE_URL}${path}`,{headers,method,...(body===undefined?{}:{body:JSON.stringify(body)})});
  if(!response.ok)throw Error('Remote operation failed');
  return response.status===204?null:await response.json();
 }
 stage='account ownership preflight';
 const profiles=await api(`/rest/v1/profiles?select=id,nickname&id=in.(${plan.source},${plan.target})`,undefined,'GET');
 if(profiles.length!==2||!profiles.some(p=>p.id===plan.target&&p.nickname===plan.nickname))throw Error('Ownership mismatch');
 stage='permanent Auth identity';
 const updated=await api(`/auth/v1/admin/users/${plan.target}`,{email:`${plan.target}@nickname.invalid`,email_confirm:true,password:crypto.randomUUID()+crypto.randomUUID()},'PUT');
 if(updated.id!==plan.target)throw Error('Identity mismatch');
 stage='nickname registry';
 const existing=await api(`/rest/v1/nickname_accounts?select=user_id&nickname_key=eq.${encodeURIComponent(plan.nickname)}`,undefined,'GET');
 if(existing.length===0)await api('/rest/v1/rpc/register_nickname_account',{p_nickname:plan.nickname,p_pin:plan.pin,p_user_id:plan.target});
 else if(existing.length!==1||existing[0].user_id!==plan.target)throw Error('Nickname conflict');
 stage='transactional data migration';
 const sql=`begin;
 lock table public.grade_records in share row exclusive mode;
 do $migration$
 declare source_count integer; target_count integer; before_values jsonb; after_values jsonb;
 begin
 select count(*) into source_count from public.grade_records where user_id='${plan.source}';
 select count(*) into target_count from public.grade_records where user_id='${plan.target}';
 if source_count=0 and target_count=18 then return; end if;
 if source_count<>12 or target_count<>6 then raise exception 'Migration counts changed'; end if;
 select jsonb_agg(to_jsonb(g)-'user_id'-'updated_at' order by id) into before_values from public.grade_records g where user_id in ('${plan.source}','${plan.target}');
 update public.grade_records set user_id='${plan.target}' where user_id='${plan.source}';
 update public.mock_exam_records set user_id='${plan.target}' where user_id='${plan.source}';
 update public.school_record_evidence set user_id='${plan.target}' where user_id='${plan.source}';
 update public.profiles set nickname='이전계정_${plan.source.slice(0,8)}' where id='${plan.source}' and nickname='${plan.nickname}';
 select jsonb_agg(to_jsonb(g)-'user_id'-'updated_at' order by id) into after_values from public.grade_records g where user_id='${plan.target}';
 if before_values is distinct from after_values then raise exception 'Grade values changed'; end if;
 end; $migration$;
 commit;`;
 const sqlPath='tools/ocr/test-output/account-migration.sql';fs.writeFileSync(sqlPath,sql);
 cli(`npx supabase db query --remote=${project} --file ${sqlPath} --yes`);
 stage='new login verification';
 const logged=await fetch(`${config.SUPABASE_URL}/functions/v1/nickname-auth`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:JSON.stringify({action:'login',nickname:plan.nickname,pin:plan.pin})});
 if(!logged.ok)throw Error('Login failed');
 const login=await logged.json();
 const tokenResponse=await fetch(`${config.SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:login.refresh_token})});
 if(!tokenResponse.ok)throw Error('Refresh failed');
 const session=await tokenResponse.json();
 if(session.user.id!==plan.target)throw Error('Wrong user');
 const rowsResponse=await fetch(`${config.SUPABASE_URL}/rest/v1/grade_records?select=school_year,semester,exam_kind&user_id=eq.${plan.target}`,{headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`}});
 if(!rowsResponse.ok)throw Error('Read failed');
 const rows=await rowsResponse.json();
 if(rows.length!==18)throw Error('Unexpected count');
 const groups={};for(const r of rows){const k=`${r.school_year}/${r.semester}/${r.exam_kind}`;groups[k]=(groups[k]??0)+1;}
 console.log(JSON.stringify({success:true,subjects:rows.length,periods:groups}));
 await fetch(`${config.SUPABASE_URL}/auth/v1/logout?scope=local`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`}});
}catch{
 console.error(`Migration stopped at: ${stage}. Credentials and upstream responses are suppressed.`);process.exitCode=1;
}
