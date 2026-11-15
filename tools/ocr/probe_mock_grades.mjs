// Local diagnostic only: browser OCR is restricted to localhost assets.
import {chromium} from 'playwright-core';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
const web=path.resolve('web');
const response=JSON.parse(await fs.readFile('tools/ocr/test-output/private-mock-response.json','utf8'));
const words=response.data[0].text_detections.map(w=>({text:w.text_prediction.text.replace(/\s/g,''),x:w.bounding_box.points.reduce((s,p)=>s+p.x,0)/4,y:w.bounding_box.points.reduce((s,p)=>s+p.y,0)/4}));
const rows=['영어','한국사'].map(label=>words.find(w=>w.text===label&&w.x<.15&&w.y<.3));
if(rows.some(r=>!r))throw Error('Missing row anchors');
const server=createServer(async(req,res)=>{try{const route=new URL(req.url,'http://local').pathname;if(route==='/'){res.setHeader('Content-Type','text/html');return res.end('<script src="/vendor/ocr/tesseract/tesseract.min.js"></script>');}const file=path.resolve(web,'.'+route);if(!file.startsWith(web+path.sep)){res.writeHead(403);return res.end();}res.setHeader('Content-Type',({'.js':'text/javascript','.wasm':'application/wasm'})[path.extname(file)]??'application/octet-stream');res.end(await fs.readFile(file));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage();const base=`http://127.0.0.1:${server.address().port}`;await page.route('**/*',r=>r.request().url().startsWith(base)?r.continue():r.abort());await page.goto(base);await page.waitForFunction(()=>!!window.Tesseract);
 const bytes=[...await fs.readFile('성적표/M2-9.jpg')];
 const results=await page.evaluate(async({bytes,rows,base})=>{
  const image=await createImageBitmap(new Blob([Uint8Array.from(bytes)],{type:'image/jpeg'}));
  const worker=await Tesseract.createWorker('eng',1,{workerPath:base+'/vendor/ocr/tesseract/worker.min.js',corePath:base+'/vendor/ocr/core/',langPath:base+'/vendor/ocr/lang/',workerBlobURL:false,cacheMethod:'none'});
  const results=[];
  try{
   for(const row of rows){
    for(const size of [.003,.004,.005]){
     const left=.480-size,right=.480+size,top=row.y-.012,bottom=row.y+.012;
     const canvas=document.createElement('canvas');const pad=20,scale=4;
     canvas.width=Math.round((right-left)*image.width*scale)+pad*2;canvas.height=Math.round((bottom-top)*image.height*scale)+pad*2;
     const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,left*image.width,top*image.height,(right-left)*image.width,(bottom-top)*image.height,pad,pad,canvas.width-pad*2,canvas.height-pad*2);
     const pixels=ctx.getImageData(0,0,canvas.width,canvas.height);for(let i=0;i<pixels.data.length;i+=4){const value=(pixels.data[i]+pixels.data[i+1]+pixels.data[i+2])/3<160?0:255;pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=value;}ctx.putImageData(pixels,0,0);
     await worker.setParameters({tessedit_pageseg_mode:'8',tessedit_char_whitelist:'123456789'});
     const {data}=await worker.recognize(canvas);
     results.push({label:row.text,size,text:data.text.trim(),confidence:data.confidence});
    }
   }
   return results;
  }finally{await worker.terminate();image.close();}
 },{bytes,rows,base});
 await fs.writeFile('tools/ocr/test-output/private-mock-digit-probe.json',JSON.stringify(results));
 console.log(JSON.stringify(results.map(r=>({label:r.label,size:r.size,found:/^[1-9]$/.test(r.text),confidence:r.confidence}))));
}finally{await browser?.close();await new Promise(r=>server.close(r));}
