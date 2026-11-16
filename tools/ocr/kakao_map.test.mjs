import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source = await readFile('web/kakao_map.js','utf8');
function environment(keyword = [], address = [], statuses = ['OK','OK']) {
  const records={lines:[],overlays:[],markers:[],elements:[],listeners:{},categoryCalls:0,level:5,campusData:[]};
  class LatLng {constructor(lat,lng){this.lat=lat;this.lng=lng;}}
  class Bounds {points=[];extend(p){this.points.push(p);}getSouthWest(){return this.points[0];}}
  class Overlay {constructor(o){this.options=o;records.overlays.push(this);}setMap(m){this.map=m;}}
  class Polyline extends Overlay {constructor(o){super(o);records.lines.push(this);}}
  const maps={LatLng,LatLngBounds:Bounds,CustomOverlay:Overlay,Polyline,
    Map:class {addControl(){}relayout(){}setBounds(){records.fitted=(records.fitted||0)+1;}setCenter(){}setLevel(){}getLevel(){return records.level;}},
    event:{addListener(target,type,fn){records.listeners[type]=fn;}},
    Marker:class extends Overlay {constructor(o){super(o);records.markers.push(this);}},
    ZoomControl:class {},ControlPosition:{RIGHT:1},
    services:{Status:{OK:'OK',ZERO_RESULT:'ZERO_RESULT'},
      Places:class {keywordSearch(q,cb){records.keyword=q;cb(keyword,statuses[0]);}
        categorySearch(code,cb,opts){records.categoryCalls++;records.category={code,opts};cb(records.campusData,records.campusData.length?'OK':'ZERO_RESULT',{hasNextPage:false});}},
      Geocoder:class {addressSearch(q,cb){records.address=q;cb(address,statuses[1]);}}}};
  const context=vm.createContext({URL,setTimeout,clearTimeout,kakao:{maps},console,getComputedStyle:()=>({position:'static'}),
    requestAnimationFrame:fn=>fn(),ResizeObserver:class {observe(){}disconnect(){records.disconnected=true;}},
    document:{createElement:()=> {const el={style:{},listeners:{},setAttribute(){},addEventListener(type,fn){this.listeners[type]=fn;}};records.elements.push(el);return el;}}});
  vm.runInContext(source,context);
  return {api:context,records};
}
test('기관명과 주소를 모두 검색하고 좌표 중복은 제거한다',async()=>{
  const p={id:'1',place_name:'서울시청',road_address_name:'서울 중구 세종대로 110',category_name:'공공기관',x:'126.978',y:'37.566'};
  const {api,records}=environment([p],[{address_name:p.road_address_name,x:p.x,y:p.y}]);
  const result=JSON.parse(await api.univKakaoSearch('browser-key','서울시청'));
  assert.equal(records.keyword,'서울시청');assert.equal(records.address,'서울시청');
  assert.equal(result.places.length,1);assert.equal(result.places[0].name,'서울시청');assert.equal(result.partialFailure,false);
});
test('장소 결과가 없어도 도로명·지번 주소 결과를 반환한다',async()=>{
  const {api}=environment([],[{address_name:'서울 중구 태평로1가 31',road_address:{address_name:'서울 중구 세종대로 110',building_name:'서울시청'},x:'126.978',y:'37.566'}],['ZERO_RESULT','OK']);
  const result=JSON.parse(await api.univKakaoSearch('browser-key','서울 중구 세종대로 110'));
  assert.equal(result.places[0].name,'서울시청');assert.equal(result.places[0].address,'서울 중구 세종대로 110');
});
test('검색 실패와 결과 없음을 구분하고 키 없는 요청을 차단한다',async()=>{
  const failed=environment([],[],['ERROR','ERROR']);
  await assert.rejects(failed.api.univKakaoSearch('key','서울'),/SEARCH_FAILED/);
  await assert.rejects(failed.api.univKakaoSearch('','서울'),/KEY_MISSING/);
  const empty=environment([],[],['ZERO_RESULT','ZERO_RESULT']);
  assert.equal(JSON.parse(await empty.api.univKakaoSearch('key','없는 주소')).places.length,0);
});
test('최단 직선만 주황·굵은 선, 일반 선은 파랑, 라벨은 안전한 텍스트',async()=>{
  const {api,records}=environment();
  const element={style:{},setAttribute(){},isConnected:true,clientWidth:600,clientHeight:400,replaceChildren(){}};
  await api.univKakaoCreate(element,'key');
  const origin={id:'o',name:'출발',latitude:37.5,longitude:127};
  const destinations=[{id:'a',label:'<img src=x onerror=alert(1)>',latitude:37.6,longitude:127},{id:'b',label:'다른 대학',latitude:37.8,longitude:127}];
  api.univKakaoRender(element,JSON.stringify({origin,destinations,connections:destinations.map((p,i)=>({...p,nearest:i===0,distanceKm:i+1}))}));
  assert.deepEqual(records.lines.map(l=>l.options.strokeColor),['#2867b2','#d94c20']);
  assert.deepEqual(records.lines.map(l=>l.options.strokeWeight),[3,6]);
  assert.equal(records.elements.some(e=>e.textContent?.includes('<img')),true);
  assert.equal(records.elements.some(e=>e.innerHTML),false);
  api.univKakaoRender(element,JSON.stringify({origin:null,destinations:[],connections:[]}));
  assert.equal(records.lines.every(l=>l.map===null),true);
  api.univKakaoDispose(element);assert.equal(records.disconnected,true);
});

test('길찾기 새 창은 카카오 URL만 허용하고 opener를 분리한다',()=>{
  const {api}=environment();
  const tab={opener:{},location:{}};
  api.open=()=>tab;
  assert.equal(api.univKakaoOpenDirections('https://map.kakao.com/link/by/traffic/start,37,127/end,38,127'),true);
  assert.equal(tab.opener,null);
  assert.equal(tab.location.href,'https://map.kakao.com/link/by/traffic/start,37,127/end,38,127');
  assert.equal(api.univKakaoOpenDirections('https://example.org/link/by/car/a/b'),false);
  api.open=()=>null;
  assert.equal(api.univKakaoOpenDirections('https://map.kakao.com/link/by/walk/a/b'),false);
});

function mapElement(){return {style:{},children:[],setAttribute(){},isConnected:true,clientWidth:600,clientHeight:400,replaceChildren(){},append(c){this.children.push(c);}};}
const uni=(id,name,category='교육,학문 > 학교 > 대학교')=>({id,place_name:name,category_name:category,road_address_name:'가상 주소',x:'127.0',y:'37.5'});

test('지도 영역의 대학: 대학교만 남기고 하위 장소는 빼며, 결과·클릭을 전달한다',async()=>{
  const {api,records}=environment();
  records.campusData=[uni('1','가상대학교'),uni('2','가상대학교 공과대학'),uni('3','가상고등학교','교육,학문 > 학교 > 고등학교'),uni('4','가상전문대학','교육,학문 > 학교 > 전문대학')];
  const element=mapElement();await api.univKakaoCreate(element,'key');
  const found=[],taps=[];
  api.univKakaoCampuses(element,true,r=>found.push(JSON.parse(r)),r=>taps.push(JSON.parse(r)));
  await new Promise(r=>setTimeout(r,0));
  assert.equal(records.category.code,'SC4');assert.equal(records.category.opts.useMapBounds,true);
  assert.equal(found[0].searching,true);
  const last=found.at(-1);
  assert.deepEqual(last.places.map(p=>p.name),['가상대학교','가상전문대학']);
  // 대학 표시 버튼을 누르면 장소를 넘기고, 지도 끌기로 이어지지 않게 막는다.
  const marker=records.elements.find(e=>e.textContent==='🎓 가상대학교');
  let stopped=false;marker.listeners.click({stopPropagation(){stopped=true;}});
  assert.equal(taps[0].name,'가상대학교');assert.equal(stopped,true);
  // 이미 켜져 있으면 다시 그려도 검색을 반복하지 않는다.
  api.univKakaoCampuses(element,true,r=>found.push(JSON.parse(r)),r=>taps.push(JSON.parse(r)));
  assert.equal(records.categoryCalls,1);
});

test('목적지를 추가해 지도를 다시 맞춘 뒤에도 현 지도에서 검색·껐다 켜기가 동작한다(사용자 보고 재현)',async()=>{
  const {api,records}=environment();
  records.campusData=[uni('1','가상대학교')];
  const element=mapElement();await api.univKakaoCreate(element,'key');
  const found=[];const on=()=>api.univKakaoCampuses(element,true,r=>found.push(JSON.parse(r)),()=>{});
  on();await new Promise(r=>setTimeout(r,0));
  // 목적지 추가 → 다시 그리기(앱이 지도를 맞춤) → 같은 레이어 상태로 다시 호출
  api.univKakaoRender(element,JSON.stringify({origin:null,destinations:[{id:'a',label:'가상대학교',latitude:37.5,longitude:127},{id:'b',label:'다른 곳',latitude:37.6,longitude:127}],connections:[]}));
  on();
  const button=element.children.find(c=>c.textContent?.includes('현 지도에서 검색'));
  // 앱이 맞춘 이동(zoom_changed)은 버튼을 띄우지 않고, 사용자가 끌면 띄운다.
  records.listeners.zoom_changed();assert.equal(button.style.display,'none');
  records.listeners.idle();records.listeners.dragend();assert.equal(button.style.display,'block');
  // 버튼은 지도로 입력을 넘기지 않고 다시 검색한다.
  let stopped=0;const ev={stopPropagation(){stopped++;},preventDefault(){}};
  button.listeners.mousedown(ev);button.listeners.click(ev);
  await new Promise(r=>setTimeout(r,0));
  assert.equal(stopped,2);assert.equal(records.categoryCalls,2);assert.equal(found.at(-1).places.length,1);
  // 끄고 다시 켜면 새로 검색한다.
  api.univKakaoCampuses(element,false,()=>{},()=>{});on();
  await new Promise(r=>setTimeout(r,0));
  assert.equal(records.categoryCalls,3);
  // 너무 넓으면 검색하지 않고 알린다.
  records.level=12;records.listeners.dragend();button.listeners.click(ev);
  await new Promise(r=>setTimeout(r,0));
  assert.equal(records.categoryCalls,3);assert.equal(found.at(-1).tooWide,true);
});
