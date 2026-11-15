import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
const source = await readFile('web/kakao_map.js','utf8');
function environment(keyword = [], address = [], statuses = ['OK','OK']) {
  const records={lines:[],overlays:[],markers:[],elements:[]};
  class LatLng {constructor(lat,lng){this.lat=lat;this.lng=lng;}}
  class Bounds {points=[];extend(p){this.points.push(p);}getSouthWest(){return this.points[0];}}
  class Overlay {constructor(o){this.options=o;records.overlays.push(this);}setMap(m){this.map=m;}}
  class Polyline extends Overlay {constructor(o){super(o);records.lines.push(this);}}
  const maps={LatLng,LatLngBounds:Bounds,CustomOverlay:Overlay,Polyline,
    Map:class {addControl(){}relayout(){}setBounds(){}setCenter(){}setLevel(){}},
    Marker:class extends Overlay {constructor(o){super(o);records.markers.push(this);}},
    ZoomControl:class {},ControlPosition:{RIGHT:1},
    services:{Status:{OK:'OK',ZERO_RESULT:'ZERO_RESULT'},
      Places:class {keywordSearch(q,cb){records.keyword=q;cb(keyword,statuses[0]);}},
      Geocoder:class {addressSearch(q,cb){records.address=q;cb(address,statuses[1]);}}}};
  const context=vm.createContext({URL,setTimeout,clearTimeout,kakao:{maps},
    requestAnimationFrame:fn=>fn(),ResizeObserver:class {observe(){}disconnect(){records.disconnected=true;}},
    document:{createElement:()=> {const el={style:{},setAttribute(){}};records.elements.push(el);return el;}}});
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
