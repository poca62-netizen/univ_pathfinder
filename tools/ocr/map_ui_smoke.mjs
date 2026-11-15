import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=path.resolve('build/map-preview');
const server=createServer(async(req,res)=>{
  try {
    const file=path.resolve(root,'.'+new URL(req.url,'http://localhost').pathname.replace(/\/$/,'/index.html'));
    if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
    res.setHeader('Content-Type',({'.html':'text/html;charset=utf-8','.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png'})[path.extname(file)]??'application/octet-stream');
    res.end(await readFile(file));
  }catch{res.writeHead(404);res.end();}
});
await new Promise((r,j)=>{server.once('error',j);server.listen(8080,'localhost',r);});
let browser;
try {
  browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  for(const [name,width,height] of [['desktop',1440,1100],['mobile',390,844]]) {
    const page=await browser.newPage({viewport:{width,height}});
    const errors=[]; page.on('pageerror',e=>errors.push(e.message.replace(/appkey=[^&\s]+/g,'appkey=[redacted]')));
    await page.goto('http://localhost:8080');
    await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
    await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
    await page.waitForFunction(()=>globalThis.kakao?.maps?.Polyline,{timeout:30000});
    await page.evaluate(()=>{
      const Native=kakao.maps.Polyline;globalThis.__lines=[];
      kakao.maps.Polyline=function(o){const line=new Native(o);__lines.push({line,options:o});return line;};
    });
    const input=page.getByRole('textbox',{name:/출발지 기관명 또는 주소/});
    await input.waitFor({timeout:5000}).catch(async error => {
        await mkdir('tools/ocr/test-output/maps',{recursive:true});
      await page.screenshot({path:'tools/ocr/test-output/maps/flutter-map-debug.png'});
      throw error;
    });
    await input.click();await page.waitForTimeout(200);await page.keyboard.press('Control+A');await page.keyboard.insertText('서울시청');await page.keyboard.press('Tab');await page.waitForTimeout(100);
    await page.getByRole('button',{name:'출발지 검색',exact:true}).click();
    await page.waitForTimeout(1500);
    await page.getByRole('button',{name:/^서울특별시청\s+서울 중구 세종대로 110/}).first().click();
    await page.getByRole('button',{name:'출발지 지우기',exact:true}).waitFor();
    await page.getByRole('button',{name:'서울대 위치 선택·변경',exact:true}).click();
    await page.getByRole('button',{name:/^서울대학교 관악캠퍼스\s+서울 관악구 관악로 1/}).first().click();
    await page.waitForFunction(()=>__lines.filter(x=>x.line.getMap()).length===2);
    let lines=await page.evaluate(()=>__lines.filter(x=>x.line.getMap()).map(x=>x.options.strokeColor));
    assert.deepEqual(lines.sort(),['#2867b2','#d94c20'].sort());
    const destination=page.getByRole('textbox',{name:/목적지 대학·기관명 또는 주소/});
    await destination.click();await page.waitForTimeout(200);await page.keyboard.press('Control+A');await page.keyboard.insertText('서울도서관');await page.keyboard.press('Tab');await page.waitForTimeout(100);
    await page.getByRole('button',{name:'목적지 검색',exact:true}).click();
    await page.getByRole('button',{name:/^서울도서관\s+서울 중구 세종대로 110/}).first().click();
    await page.waitForFunction(()=>__lines.filter(x=>x.line.getMap()).length===3);
    const nearest=await page.evaluate(()=>__lines.filter(x=>x.line.getMap()&&x.options.strokeColor==='#d94c20').length);
    assert.equal(nearest,1);
    // Replace the selected origin with an address search.
    await page.getByRole('button',{name:'출발지 지우기',exact:true}).click();
    await input.click();await page.waitForTimeout(200);await page.keyboard.press('Control+A');await page.keyboard.insertText('서울 중구 세종대로 110');await page.keyboard.press('Tab');await page.waitForTimeout(100);
    await page.getByRole('button',{name:'출발지 검색',exact:true}).click();
    await page.getByRole('button',{name:/^서울특별시청\s+서울 중구 세종대로 110/}).first().click();
    await page.getByRole('button',{name:'출발지 지우기',exact:true}).waitFor();
    if(width<500) { await page.mouse.move(4,600);await page.mouse.wheel(0,520);await page.waitForTimeout(500); }
    await mkdir('tools/ocr/test-output/maps',{recursive:true});
    await page.screenshot({path:`tools/ocr/test-output/maps/flutter-map-${name}.png`});
    assert.deepEqual(errors,[]);
    console.log(`${name}: institution/address origin, selected universities, custom destination, three lines and nearest highlight passed.`);
    await page.close();
  }
} finally {if(browser)await browser.close();await new Promise(r=>server.close(r));}
