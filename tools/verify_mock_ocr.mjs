// Explicit OCR-only reproduction. No grade/profile/database writes.
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const config=JSON.parse(fs.readFileSync('.env.dev.json','utf8').replace(/^\uFEFF/,''));
const project=new URL(config.SUPABASE_URL).hostname.split('.')[0];
if(!/^[a-z]{20}$/.test(project))throw Error('Invalid project');
let uid,stage='temporary authentication';
try{
 const signup=await fetch(`${config.SUPABASE_URL}/auth/v1/signup`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:'{}'});
 if(!signup.ok)throw Error('Auth failed');
 const session=await signup.json();uid=session.user.id;
 stage='NVIDIA image recognition';
 const response=await fetch(`${config.SUPABASE_URL}/functions/v1/nemotron-ocr`,{method:'POST',headers:{apikey:config.SUPABASE_PUBLISHABLE_KEY,Authorization:`Bearer ${session.access_token}`,'Content-Type':'image/jpeg'},body:fs.readFileSync(process.argv[2] ?? '성적표/M2-9.jpg')});
 if(!response.ok)throw Error('OCR failed');
 const data=await response.json();
 fs.writeFileSync(process.argv[3] ?? 'tools/ocr/test-output/private-mock-response.json',JSON.stringify(data));
 console.log(JSON.stringify({success:true,detections:data.data[0].text_detections.length,storedLocally:true}));
}catch{console.error(`Failed at ${stage}; credentials and upstream responses suppressed.`);process.exitCode=1;}
finally{
 if(uid){
  try{
   const raw=execFileSync('cmd.exe',['/d','/s','/c',`npx supabase projects api-keys --remote=${project} --output json`],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
   const key=JSON.parse(raw).find(k=>k.name==='service_role').api_key;
   const deleted=await fetch(`${config.SUPABASE_URL}/auth/v1/admin/users/${uid}`,{method:'DELETE',headers:{apikey:key,Authorization:`Bearer ${key}`}});
   if(!deleted.ok)throw Error('Cleanup failed');
   console.log('Temporary Auth account removed.');
  }catch{console.error('Temporary Auth cleanup failed.');process.exitCode=1;}
 }
}
