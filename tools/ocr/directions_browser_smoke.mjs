import {chromium} from 'playwright-core';
import assert from 'node:assert/strict';
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
try {
 const context=await browser.newContext();
 const requests=[];
 await context.route('https://map.kakao.com/link/by/**',async route=>{requests.push(route.request().url());await route.abort();});
 const page=await context.newPage();
 await page.setContent('<button id="route">카카오 길찾기</button>');
 await page.addScriptTag({path:'web/kakao_map.js'});
 for(const mode of ['traffic','car','walk','bicycle']) {
   const url=`https://map.kakao.com/link/by/${mode}/${encodeURIComponent('서울시청')},37.5668,126.9786/${encodeURIComponent('서울대학교 관악캠퍼스')},37.4598,126.9511`;
   await page.evaluate(url=>{document.getElementById('route').onclick=()=>{window.opened=univKakaoOpenDirections(url);};},url);
   const popupPromise=page.waitForEvent('popup');
   await page.click('#route');
   const popup=await popupPromise;
   await page.waitForFunction(()=>window.opened===true);
   await new Promise(r=>setTimeout(r,100));
   assert(requests.some(request=>request===url));
   await popup.close();
 }
 console.log('Chrome: four transport modes open the exact Kakao directions URL in a new tab.');
} finally {await browser.close();}
