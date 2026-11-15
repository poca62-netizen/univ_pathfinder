// Conservative plan based on detected table rows/columns, never expected scores.
const median = values => { const a=[...values].sort((x,y)=>x-y);return (a[Math.floor((a.length-1)/2)]+a[Math.ceil((a.length-1)/2)])/2; };
export function findMockGradeTargets(response) {
  const detections=response?.data?.[0]?.text_detections;
  if(!Array.isArray(detections))return [];
  const words=detections.flatMap(d=>{
    const p=d.bounding_box?.points;
    if(!Array.isArray(p)||p.length<4||p.some(v=>!Number.isFinite(v.x)||!Number.isFinite(v.y)||v.x<0||v.x>1||v.y<0||v.y>1))return [];
    return [{text:String(d.text_prediction?.text??'').replace(/\s/g,''),x:median(p.map(v=>v.x)),y:median(p.map(v=>v.y)),w:Math.max(...p.map(v=>v.x))-Math.min(...p.map(v=>v.x))}];
  });
  const labels=['국어','수학','영어','한국사','사회','과학'];
  const rows=labels.map(label=>words.filter(w=>w.text===label&&w.x<.35).sort((a,b)=>a.y-b.y)[0]).filter(Boolean).sort((a,b)=>a.y-b.y);
  if(!['국어','수학','영어','한국사'].every(label=>rows.some(r=>r.text===label)))return [];
  const gaps=rows.slice(1).map((r,i)=>r.y-rows[i].y);
  const gap=median(gaps);
  if(gap<=0||gaps.some(g=>g<gap*.6||g>gap*1.5))return [];
  const nearRow=w=>rows.find(r=>Math.abs(w.y-r.y)<gap*.35);
  const counts=words.filter(w=>/^\d{4,}$/.test(w.text)&&nearRow(w));
  if(counts.length<2)return [];
  const respondentX=Math.min(...counts.map(w=>w.x));
  const digits=words.filter(w=>/^[1-9]$/.test(w.text)&&nearRow(w)&&w.x>Math.max(...rows.map(r=>r.x))+.05&&w.x<respondentX-.005);
  const clusters=[];
  for(const digit of digits.sort((a,b)=>a.x-b.x)){
    const cluster=clusters.find(c=>Math.abs(median(c.map(w=>w.x))-digit.x)<.012);
    if(cluster)cluster.push(digit);else clusters.push([digit]);
  }
  const columns=clusters.filter(c=>new Set(c.map(w=>nearRow(w).text)).size>=2);
  if(!columns.length)return [];
  const column=columns.sort((a,b)=>median(b.map(w=>w.x))-median(a.map(w=>w.x)))[0];
  const x=median(column.map(w=>w.x)),halfWidth=median(column.map(w=>w.w))/2;
  if(halfWidth<=0||halfWidth>.025)return [];
  return rows.filter(r=>['영어','한국사'].includes(r.text)).filter(r=>!words.some(w=>Math.abs(w.y-r.y)<gap*.35&&(/^[1-9]$/.test(w.text)&&Math.abs(w.x-x)<.012 || /^원점수에의한등급\([1-9]\)$/.test(w.text)))).map(r=>({subject:r.text,x,y:r.y,halfWidth,halfHeight:gap*.42}));
}
export function acceptMockGradeVotes(votes) {
  const valid=votes.filter(v=>/^[1-9]$/.test(v.text)&&Number.isFinite(v.confidence));
  if(valid.length<2||new Set(valid.map(v=>v.text)).size!==1||Math.max(...valid.map(v=>v.confidence))<65)return null;
  return {grade:Number(valid[0].text),confidence:Math.max(...valid.map(v=>v.confidence))};
}
