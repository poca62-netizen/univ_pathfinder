import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/map_location.dart';

const _key = String.fromEnvironment('KAKAO_JAVASCRIPT_KEY');
@JS('univOpenAdmissionSource')
external JSBoolean _openAdmissionSource(JSString url);

bool openAdmissionSource(Uri uri) {
  try {
    return _openAdmissionSource(uri.toString().toJS).toDart;
  } catch (_) {
    return false;
  }
}

@JS('univKakaoOpenDirections')
external JSBoolean _openDirections(JSString url);
bool openKakaoDirections(Uri uri) {
  try {
    return _openDirections(uri.toString().toJS).toDart;
  } catch (_) {
    return false;
  }
}

@JS('univKakaoSearch')
external JSPromise<JSString> _search(JSString key, JSString query);
@JS('univKakaoCreate')
external JSPromise<JSAny?> _create(JSObject element, JSString key);
@JS('univKakaoRender')
external void _render(JSObject element, JSString state);
@JS('univKakaoDispose')
external void _dispose(JSObject element);
@JS('univKakaoCampuses')
external void _campuses(
  JSObject element,
  JSBoolean enabled,
  JSFunction onFound,
  JSFunction onTap,
);

String _message(Object error) => error.toString().contains('KEY_MISSING')
    ? '카카오 JavaScript 키가 없습니다. 개발 설정을 적용해 앱을 다시 실행하세요.'
    : '카카오 지도를 연결하지 못했습니다. 네트워크와 카카오 앱의 지도 사용 설정·웹 도메인을 확인한 뒤 다시 시도하세요.';

Future<List<MapLocation>> searchMapLocations(String query) async {
  if (query.trim().isEmpty) return [];
  try {
    final raw = (await _search(_key.toJS, query.trim().toJS).toDart).toDart;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final places = (data['places'] as List)
        .map((p) => MapLocation.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    if (data['partialFailure'] == true) {
      // Do not silently present a partial search as a complete successful search.
      throw StateError('PARTIAL_SEARCH');
    }
    return places;
  } catch (e) {
    throw StateError(_message(e));
  }
}

class KakaoMapView extends StatefulWidget {
  const KakaoMapView({
    super.key,
    required this.origin,
    required this.destinations,
    this.universities,
  });
  final MapLocation? origin;
  final List<MapDestination> destinations;

  /// 지도 영역의 대학 표시(켜면 현재 영역을 검색하고, 지도를 옮기면 '현 지도에서 검색' 버튼이 나온다).
  final UniversityLayer? universities;
  @override
  State<KakaoMapView> createState() => _KakaoMapViewState();
}

class _KakaoMapViewState extends State<KakaoMapView> {
  JSObject? _element;
  bool _ready = false;
  String? _error;
  int _attempt = 0;
  late final JSFunction _onCampuses = ((JSString raw) {
    try {
      widget.universities?.onFound(
        CampusSearchResult.fromJson(
          jsonDecode(raw.toDart) as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      widget.universities?.onFound(const CampusSearchResult(failed: true));
    }
  }).toJS;
  late final JSFunction _onCampusTap = ((JSString raw) {
    try {
      widget.universities?.onTap(
        MapLocation.fromJson(jsonDecode(raw.toDart) as Map<String, dynamic>),
      );
    } catch (_) {
      /* 잘못된 장소 정보는 무시한다. */
    }
  }).toJS;
  Future<void> _initialize(Object element) async {
    final target = element as JSObject;
    _element = target;
    try {
      await _create(target, _key.toJS).toDart;
      if (!mounted || _element != target) {
        _dispose(target);
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
      _update();
    } catch (e) {
      if (mounted && _element == target) setState(() => _error = _message(e));
    }
  }

  void _update() {
    if (!_ready || _element == null) return;
    _render(
      _element!,
      jsonEncode({
        'origin': widget.origin?.toJson(),
        'destinations': [
          for (final d in widget.destinations.where((d) => d.location != null))
            {...d.location!.toJson(), 'label': d.label},
        ],
        'connections': mapConnections(
          widget.origin,
          widget.destinations,
        ).map((c) => c.toJson()).toList(),
      }).toJS,
    );
    final visible = widget.universities?.visible ?? false;
    try {
      _campuses(_element!, visible.toJS, _onCampuses, _onCampusTap);
      _staleReported = false;
    } catch (_) {
      // 브라우저가 예전 kakao_map.js를 캐시해 함수가 없을 때: 지도는 그대로 두고 대학 표시만 실패로 알린다.
      // 결과 보고가 다시 그리기를 부르므로 켤 때 한 번만, 그리기가 끝난 뒤 알린다.
      if (visible && !_staleReported) {
        _staleReported = true;
        final layer = widget.universities;
        Future.microtask(
          () => layer?.onFound(const CampusSearchResult(needsReload: true)),
        );
      }
      if (!visible) _staleReported = false;
    }
  }

  bool _staleReported = false;

  @override
  void didUpdateWidget(covariant KakaoMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    if (_element != null) _dispose(_element!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (_error == null)
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            key: ValueKey(_attempt),
            tagName: 'div',
            onElementCreated: _initialize,
          ),
        ),
      if (!_ready && _error == null)
        const Center(child: CircularProgressIndicator()),
      if (_error != null)
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () {
                        if (_element != null) _dispose(_element!);
                        setState(() {
                          _ready = false;
                          _error = null;
                          _attempt++;
                        });
                      },
                      child: const Text('지도 다시 연결'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
