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
  const view = {map, maps, overlays: [], state: null};
  const observer = new ResizeObserver(() => { map.relayout(); if (view.bounds) map.setBounds(view.bounds, 45, 50, 60, 50); });
  observer.observe(element); view.observer = observer; views.set(element, view);
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
  if (count === 1) { map.setCenter(bounds.getSouthWest()); map.setLevel(5); }
  else if (count > 1) map.setBounds(bounds, 45, 50, 60, 50);
};
globalThis.univKakaoDispose = element => {
  const view = views.get(element);
  if (!view) return;
  view.observer.disconnect();
  for (const overlay of view.overlays) overlay.setMap(null);
  views.delete(element); element.replaceChildren();
};
