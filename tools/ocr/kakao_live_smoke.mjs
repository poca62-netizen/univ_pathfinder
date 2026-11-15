import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const config = JSON.parse(await readFile('.env.dev.json','utf8'));
const sdkResponse = await fetch(`https://dapi.kakao.com/v2/maps/sdk.js?appkey=${encodeURIComponent(config.KAKAO_JAVASCRIPT_KEY)}&autoload=false&libraries=services`, {headers:{Referer:'http://localhost:8080/'}});
const sdkText = await sdkResponse.text();
if (sdkResponse.headers.get('content-type')?.includes('json') || !sdkResponse.ok) {
  console.log(JSON.stringify({sdkStatus:sdkResponse.status, response:sdkText.slice(0,1000).replaceAll(config.KAKAO_JAVASCRIPT_KEY,'[redacted]')}));
}
const root = path.resolve('web');
const server = createServer(async (req,res) => {
  const url = new URL(req.url,'http://localhost');
  if(url.pathname === '/') { res.setHeader('Content-Type','text/html;charset=utf-8');return res.end('<!doctype html><html lang="ko"><meta charset="utf-8"><title>카카오 지도 연결 검증</title><body style="margin:0;height:100vh"><div id="map" style="width:100vw;height:100vh"></div><script src="/kakao_map.js"></script></body></html>'); }
  if(url.pathname === '/kakao_map.js') {res.setHeader('Content-Type','text/javascript');return res.end(await readFile(path.join(root,'kakao_map.js')));}
  res.writeHead(404);res.end();
});
await new Promise((resolve,reject)=> {server.once('error',reject);server.listen(8080,'localhost',resolve);});
let browser;
try {
  browser = await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  const page = await browser.newPage({viewport:{width:1200,height:800}});
  const network = [];
  page.on('requestfailed', request => { const u = new URL(request.url()); network.push({host:u.hostname,path:u.pathname,error:request.failure()?.errorText}); });
  page.on('response', response => {
    if (response.status() >= 400) { const u = new URL(response.url()); network.push({host:u.hostname,path:u.pathname,status:response.status()}); }
  });
  await page.goto('http://localhost:8080');
  const result = await page.evaluate(async key => {
    try {
      await univKakaoCreate(document.getElementById('map'),key);
      const queries = ['서울시청','서울 중구 세종대로 110','서울대학교','연세대학교 신촌캠퍼스'];
      const results = [];
      for(const query of queries) {
        const result = JSON.parse(await univKakaoSearch(key,query));
        results.push({query,...result});
      }
      return {ok:true,results};
    } catch (error) { return {ok:false,reason:String(error.message).replaceAll(key,'[redacted]').replaceAll(encodeURIComponent(key),'[redacted]')}; }
  }, config.KAKAO_JAVASCRIPT_KEY);
  if(!result.ok) {console.log(JSON.stringify({...result,network}));process.exitCode=1;}
  else {
    console.log(JSON.stringify(result.results.map(r=>({query:r.query,partial:r.partialFailure,count:r.places.length,first:r.places.slice(0,3)})),null,2));
    assert(result.results[0].places.length>0);
    assert(result.results[1].places.length>0);
    const origin=result.results[0].places[0], destinations=[result.results[2].places[0],result.results[3].places[0]];
    const colors=await page.evaluate(({origin,destinations})=>{
      const Original=kakao.maps.Polyline, options=[];
      kakao.maps.Polyline=function(o){options.push(o);return new Original(o);};
      univKakaoRender(document.getElementById('map'),JSON.stringify({origin,destinations:destinations.map((p,i)=>({...p,label:'대학 '+i})),connections:destinations.map((p,i)=>({...p,label:'대학 '+i,distanceKm:10+i,nearest:i===0}))}));
      return options.map(o=>o.strokeColor);
    },{origin,destinations});
    assert.deepEqual(colors,['#2867b2','#d94c20']);
    await page.waitForTimeout(1500);
    await mkdir('tools/ocr/test-output/maps',{recursive:true});
    await page.screenshot({path:'tools/ocr/test-output/maps/live-kakao-map.png'});
    console.log('Live Kakao map, keyword/address search, and nearest-line colors passed.');
  }
} finally {if(browser) await browser.close();await new Promise(r=>server.close(r));}
