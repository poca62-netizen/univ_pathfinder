// PINs, tokens, credentials and upstream responses must never be logged.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
};
Deno.serve(async (req: Request) => {
  const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {status,headers:{...cors,'Content-Type':'application/json'}});
  if(req.method==='OPTIONS') return new Response(null,{headers:cors});
  if(req.method!=='POST') return reply(405,{error:'METHOD'});
  let createdUser: string | null = null;
  const url=Deno.env.get('SUPABASE_URL')!;
  const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const headers={apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'};
  async function api(path:string,body:unknown,method='POST') {
    return await fetch(`${url}${path}`,{method,headers,body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  }
  try {
    // Bound the streamed body even if Content-Length is missing or forged.
    const reader=req.body?.getReader(); if(!reader)return reply(400,{error:'INPUT'});
    const chunks:Uint8Array[]=[];let size=0;
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>1024){await reader.cancel();return reply(413,{error:'INPUT'});}chunks.push(value);}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    const input=JSON.parse(new TextDecoder().decode(bytes));
    const nickname=typeof input.nickname==='string'?input.nickname.normalize('NFKC').trim().toLowerCase():'';
    const pin=typeof input.pin==='string'?input.pin:'';
    const action=input.action;
    if(!/^[a-z0-9가-힣_]{2,20}$/.test(nickname)||!/^\d{4}$/.test(pin)||!['register','login'].includes(action))return reply(400,{error:'INPUT'});
    const address=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()??'unknown';
    const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(address));
    const bucket=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
    const rate=await api('/rest/v1/rpc/nickname_auth_rate_limit',{p_bucket:bucket});
    if(!rate.ok)return reply(503,{error:'UNAVAILABLE'});
    if(await rate.json()!==true)return reply(429,{error:'RATE_LIMIT'});
    let userId:string;
    if(action==='register'){
      // A random internal address has no inbox and is never used as user input.
      const id=crypto.randomUUID();
      const created=await api('/auth/v1/admin/users',{email:`${id}@nickname.invalid`,email_confirm:true,password:crypto.randomUUID()+crypto.randomUUID()});
      if(!created.ok)return reply(503,{error:'UNAVAILABLE'});
      userId=(await created.json()).id;createdUser=userId;
      const registered=await api('/rest/v1/rpc/register_nickname_account',{p_nickname:nickname,p_pin:pin,p_user_id:userId});
      if(!registered.ok){const code=(await registered.json()).code;return reply(code==='23505'?409:503,{error:code==='23505'?'NICKNAME_TAKEN':'UNAVAILABLE'});}
      createdUser=null;
    }else{
      const checked=await api('/rest/v1/rpc/authenticate_nickname',{p_nickname:nickname,p_pin:pin});
      if(!checked.ok)return reply(503,{error:'UNAVAILABLE'});
      const result=await checked.json();
      if(result.status!=='ok')return reply(result.status==='locked'?429:401,{error:result.status==='locked'?'LOCKED':'INVALID_CREDENTIALS'});
      userId=result.user_id;
    }
    const account=await fetch(`${url}/auth/v1/admin/users/${userId}`,{headers,signal:AbortSignal.timeout(15000)});
    if(!account.ok)return reply(503,{error:'UNAVAILABLE'});
    const email=(await account.json()).email;
    if(!email)return reply(503,{error:'UNAVAILABLE'});
    // Admin-generated links do not send email; only the verified PIN can reach here.
    const link=await api('/auth/v1/admin/generate_link',{type:'magiclink',email});
    if(!link.ok)return reply(503,{error:'UNAVAILABLE'});
    const hash=(await link.json()).hashed_token;
    if(!hash)return reply(503,{error:'UNAVAILABLE'});
    const session=await api('/auth/v1/verify',{type:'magiclink',token_hash:hash});
    if(!session.ok)return reply(503,{error:'UNAVAILABLE'});
    const data=await session.json();
    return reply(200,{refresh_token:data.refresh_token,nickname});
  }catch{
    return reply(503,{error:'UNAVAILABLE'});
  }finally{
    // Roll back the unused Auth user after a duplicate nickname race.
    if(createdUser){try{await fetch(`${url}/auth/v1/admin/users/${createdUser}`,{method:'DELETE',headers,signal:AbortSignal.timeout(10000)});}catch{/* No credentials in logs. */}}
  }
});
