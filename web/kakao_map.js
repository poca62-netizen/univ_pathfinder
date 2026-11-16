// Only the browser JavaScript key is supplied by Dart. No REST key is used here.
let sdkPromise;
globalThis.univKakaoOpenDirections = raw => {
  const url = new URL(raw);
  if (url.origin !== 'https://map.kakao.com' || !/^\/link\/by\/(traffic|car|walk|bicycle)\//.test(url.pathname)) return false;
  return openExternalTab(url);
};
globalThis.univOpenAdmissionSource = raw => {
  const url = new URL(raw);
  const hosts = ['admission.snu.ac.kr', 'admission.yonsei.ac.kr', 'oku.korea.ac.kr', 'iphak.khu.ac.kr', 'iphak.ssu.ac.kr',
    // Public data sources listed on the in-app data-sources screen.
    'www.adiga.kr', 'www.data.go.kr', 'www.kcue.or.kr', 'www.pen.go.kr', 'cheongun-h.goeyp.kr', 'jinhak.jje.go.kr'];
  if (url.protocol !== 'https:' || !hosts.includes(url.hostname)) return false;
  return openExternalTab(url);
};
function openExternalTab(url) {
  const tab = globalThis.open('about:blank', '_blank');
  if (!tab) return false;
  tab.opener = null;
  tab.location.href = url.href;
  return true;
}
function sdk(key) {
  if (!key) return Promise.reject(new Error('KEY_MISSING'));
  if (globalThis.kakao?.maps?.services) return Promise.resolve(globalThis.kakao.maps);
  if (sdkPromise) return sdkPromise;
  sdkPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    const timer = setTimeout(() => { script.remove(); reject(new Error('SDK_TIMEOUT')); }, 20000);
    script.src = `https://dapi.kakao.com/v2/maps/sdk.js?appkey=${encodeURIComponent(key)}&autoload=false&libraries=services`;
    script.onerror = () => { clearTimeout(timer); script.remove(); reject(new Error('SDK_LOAD_FAILED')); };
    script.onload = () => {
      if (!globalThis.kakao?.maps?.load) { clearTimeout(timer); script.remove(); reject(new Error('SDK_UNAVAILABLE')); return; }
      globalThis.kakao.maps.load(() => { clearTimeout(timer); resolve(globalThis.kakao.maps); });
    };
    document.head.append(script);
  }).catch(error => { sdkPromise = null; throw error; });
  return sdkPromise;
}

function request(run, maps) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve({places: [], failed: true}), 12000);
    run((data, status) => {
      clearTimeout(timer);
      resolve({places: status === maps.services.Status.OK ? data : [], failed: status !== maps.services.Status.OK && status !== maps.services.Status.ZERO_RESULT});
    });
  });
}

globalThis.univKakaoSearch = async (key, query) => {
  const maps = await sdk(key);
  if (!query.trim()) return JSON.stringify({places: [], partialFailure: false});
  const [keywords, addresses] = await Promise.all([
    request(cb => new maps.services.Places().keywordSearch(query, cb, {size: 15}), maps),
    request(cb => new maps.services.Geocoder().addressSearch(query, cb, {size: 10}), maps),
  ]);
  const places = [];
  const seen = new Set();
  function add(place) {
    if (!Number.isFinite(place.latitude) || !Number.isFinite(place.longitude)) return;
    const coordinate = `${place.latitude.toFixed(6)},${place.longitude.toFixed(6)}`;
    if (seen.has(coordinate)) return;
    seen.add(coordinate); places.push(place);
  }
  for (const p of keywords.places) add({id: `place:${p.id}`, name: p.place_name, address: p.road_address_name || p.address_name || '', category: p.category_name || '', latitude: Number(p.y), longitude: Number(p.x)});
  for (const a of addresses.places) add({id: `address:${a.x},${a.y}`, name: a.road_address?.building_name || a.address_name, address: a.road_address?.address_name || a.address_name, category: '주소', latitude: Number(a.y), longitude: Number(a.x)});
  if (keywords.failed && addresses.failed) throw new Error('SEARCH_FAILED');
  return JSON.stringify({places, partialFailure: keywords.failed || addresses.failed});
};

const views = new WeakMap();
globalThis.univKakaoCreate = async (element, key) => {
  Object.assign(element.style, {width: '100%', height: '100%', background: '#edf2ed'});
  element.setAttribute('aria-label', '출발지와 목적지 직선거리 카카오 지도');
  const maps = await sdk(key);
  await new Promise((resolve, reject) => {
    let attempts = 0;
    function attached() {
      if (element.isConnected && element.clientWidth && element.clientHeight) return resolve();
      if (++attempts > 300) return reject(new Error('MAP_NOT_ATTACHED'));
      requestAnimationFrame(attached);
    }
    attached();
  });
  const map = new maps.Map(element, {center: new maps.LatLng(37.5665, 126.978), level: 8});
  map.addControl(new maps.ZoomControl(), maps.ControlPosition.RIGHT);
  const view = {map, maps, overlays: [], state: null, programmatic: false, element};
  const observer = new ResizeObserver(() => { map.relayout(); if (view.bounds) fit(view); });
  observer.observe(element); view.observer = observer; views.set(element, view);
  // 사용자가 지도를 옮기거나 확대·축소했을 때만 '현 지도에서 검색'을 보인다(앱이 맞춘 이동은 제외).
  maps.event.addListener(map, 'dragend', () => campusMoved(view));
  maps.event.addListener(map, 'zoom_changed', () => { if (!view.programmatic) campusMoved(view); });
  maps.event.addListener(map, 'idle', () => { view.programmatic = false; });
};

function fit(view) {
  view.programmatic = true;
  view.map.setBounds(view.bounds, 45, 50, 60, 50);
}

// ---- 지도 영역의 대학 표시 (카카오 장소 카테고리 SC4=학교 중 대학교만) ----
const CAMPUS_MAX_LEVEL = 9; // 이보다 넓게 보면 결과가 잘려 의미가 없어 확대를 안내한다.
const CAMPUS_COLOR = '#6a3fb5';

function campusButton(view) {
  const c = view.campus;
  if (c.button) return c.button;
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = '↻ 현 지도에서 검색';
  Object.assign(button.style, {position: 'absolute', top: '12px', left: '50%', transform: 'translateX(-50%)', zIndex: 10, display: 'none', padding: '8px 14px', border: 'none', borderRadius: '18px', background: CAMPUS_COLOR, color: 'white', font: 'bold 13px sans-serif', boxShadow: '0 2px 6px #0006', cursor: 'pointer'});
  // 카카오 지도가 끌기 처리를 위해 마우스·터치 입력을 가져가지 않게 버튼에서 멈춘다.
  for (const type of ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend', 'dblclick', 'wheel']) {
    button.addEventListener(type, e => e.stopPropagation());
  }
  button.addEventListener('click', e => { e.stopPropagation(); e.preventDefault(); searchCampuses(view); });
  if (getComputedStyle(view.element).position === 'static') view.element.style.position = 'relative';
  view.element.append(button);
  c.button = button;
  return button;
}

function campusMoved(view) {
  if (view.campus?.on) campusButton(view).style.display = 'block';
}

function clearCampuses(view) {
  for (const o of view.campus?.overlays ?? []) o.setMap(null);
  if (view.campus) view.campus.overlays = [];
}

// 대학 건물·단과대학처럼 같은 대학의 하위 장소는 빼고 캠퍼스 대표 장소만 남긴다.
function campusPlaces(raw) {
  const kept = [];
  for (const p of raw) {
    const category = p.category_name || '';
    if (!/대학교$|전문대학$/.test(category.trim())) continue;
    kept.push({id: `place:${p.id}`, name: p.place_name, address: p.road_address_name || p.address_name || '', category, latitude: Number(p.y), longitude: Number(p.x)});
  }
  const names = kept.map(p => p.name);
  return kept.filter(p => Number.isFinite(p.latitude) && Number.isFinite(p.longitude) &&
    !names.some(n => n !== p.name && p.name.startsWith(`${n} `)));
}

async function searchCampuses(view) {
  const c = view.campus;
  const token = ++c.token;
  try {
    await searchCampusesNow(view, token);
  } catch (error) {
    // 어떤 이유로든 실패하면 화면이 '검색 중'에 멈추지 않게 실패를 알린다.
    console.error('univKakaoCampuses', error);
    if (token === c.token && c.on) c.onFound?.(JSON.stringify({places: [], failed: true, tooWide: false, truncated: false}));
  }
}

async function searchCampusesNow(view, token) {
  const c = view.campus, {map, maps} = view;
  campusButton(view).style.display = 'none';
  clearCampuses(view);
  c.onFound?.(JSON.stringify({places: [], searching: true}));
  if (map.getLevel() > CAMPUS_MAX_LEVEL) {
    c.onFound?.(JSON.stringify({places: [], failed: false, tooWide: true, truncated: false}));
    return;
  }
  const result = await new Promise(resolve => {
    const out = [];
    const timer = setTimeout(() => resolve({out, failed: true}), 12000);
    new maps.services.Places(map).categorySearch('SC4', (data, status, pagination) => {
      if (status === maps.services.Status.OK) {
        out.push(...data);
        if (pagination?.hasNextPage) { pagination.nextPage(); return; } // 카카오는 최대 3쪽(45곳)
      }
      clearTimeout(timer);
      resolve({out, failed: status !== maps.services.Status.OK && status !== maps.services.Status.ZERO_RESULT});
    }, {useMapBounds: true});
  });
  if (token !== c.token || !c.on) return; // 그 사이 끄거나 다시 검색함
  const places = campusPlaces(result.out);
  for (const place of places) {
    const content = document.createElement('button');
    content.type = 'button';
    // 장소 이름을 HTML로 넣지 않는다.
    content.textContent = `🎓 ${place.name}`;
    Object.assign(content.style, {padding: '4px 8px', border: `2px solid ${CAMPUS_COLOR}`, borderRadius: '12px', background: 'white', color: CAMPUS_COLOR, font: 'bold 11px sans-serif', whiteSpace: 'nowrap', boxShadow: '0 1px 4px #0004', cursor: 'pointer'});
    for (const type of ['mousedown', 'pointerdown', 'touchstart']) content.addEventListener(type, e => e.stopPropagation());
    content.addEventListener('click', e => { e.stopPropagation(); c.onTap?.(JSON.stringify(place)); });
    const overlay = new maps.CustomOverlay({position: new maps.LatLng(place.latitude, place.longitude), content, yAnchor: 1.2, zIndex: 2, clickable: true});
    overlay.setMap(map);
    c.overlays.push(overlay);
  }
  c.onFound?.(JSON.stringify({places, failed: result.failed, tooWide: false, truncated: result.out.length >= 45}));
}

globalThis.univKakaoCampuses = (element, enabled, onFound, onTap) => {
  const view = views.get(element);
  if (!view) return;
  const c = view.campus ??= {on: false, overlays: [], token: 0, button: null};
  c.onFound = raw => onFound(raw);
  c.onTap = raw => onTap(raw);
  if (!enabled) {
    if (!c.on) return;
    c.on = false; c.token++;
    clearCampuses(view);
    if (c.button) c.button.style.display = 'none';
    return;
  }
  if (c.on) return; // 켜진 상태에서 다시 그릴 때는 검색을 반복하지 않는다.
  c.on = true;
  searchCampuses(view);
};

function label(maps, place, text, color, zIndex, origin = false) {
  const content = document.createElement('div');
  Object.assign(content.style, {padding: '6px 9px', borderRadius: '8px', background: color, color: 'white', font: 'bold 12px sans-serif', width: 'max-content', maxWidth: '230px', whiteSpace: 'normal', wordBreak: 'keep-all', boxSizing: 'border-box', boxShadow: '0 1px 5px #0005', transform: origin ? 'translateY(12px)' : 'translateY(-12px)'});
  // Never interpolate place names/addresses into HTML.
  content.textContent = text;
  return new maps.CustomOverlay({position: new maps.LatLng(place.latitude, place.longitude), content, yAnchor: origin ? 0 : 1, zIndex});
}
globalThis.univKakaoRender = (element, raw) => {
  const view = views.get(element);
  if (!view) return;
  if (view.state === raw) return;
  view.state = raw;
  const state = JSON.parse(raw), {map, maps} = view;
  for (const overlay of view.overlays) overlay.setMap(null);
  view.overlays = [];
  const bounds = new maps.LatLngBounds(); let count = 0;
  function mark(place, text, color, zIndex = 3, origin = false) {
    const position = new maps.LatLng(place.latitude, place.longitude);
    bounds.extend(position); count++;
    const marker = new maps.Marker({position, title: text, map});
    const overlay = label(maps, place, text, color, zIndex, origin); overlay.setMap(map);
    view.overlays.push(marker, overlay);
  }
  if (state.origin) mark(state.origin, `출발: ${state.origin.name}`, '#1b654f', 7, true);
  for (const destination of state.destinations) {
    const connection = state.connections.find(c => c.id === destination.id && c.label === destination.label);
    const nearest = connection?.nearest;
    const distance = connection ? ` · ${connection.distanceKm.toFixed(2)}km${nearest ? ' · 최단' : ''}` : '';
    mark(destination, `${destination.label}${distance}`, nearest ? '#d94c20' : '#2867b2', nearest ? 6 : 3);
  }
  if (state.origin) for (const connection of [...state.connections].sort((a,b) => Number(a.nearest)-Number(b.nearest))) {
    const line = new maps.Polyline({map, path: [new maps.LatLng(state.origin.latitude, state.origin.longitude), new maps.LatLng(connection.latitude, connection.longitude)], strokeWeight: connection.nearest ? 6 : 3, strokeColor: connection.nearest ? '#d94c20' : '#2867b2', strokeOpacity: 0.9, strokeStyle: 'solid', zIndex: connection.nearest ? 2 : 1});
    view.overlays.push(line);
  }
  view.bounds = count ? bounds : null;
  map.relayout();
  if (count === 1) { view.programmatic = true; map.setCenter(bounds.getSouthWest()); map.setLevel(5); }
  else if (count > 1) fit(view);
};
globalThis.univKakaoDispose = element => {
  const view = views.get(element);
  if (!view) return;
  view.observer.disconnect();
  for (const overlay of view.overlays) overlay.setMap(null);
  if (view.campus) { view.campus.on = false; clearCampuses(view); }
  views.delete(element); element.replaceChildren();
};
