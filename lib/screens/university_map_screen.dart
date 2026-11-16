import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/screens/commute_comparison_dialog.dart';
import 'package:univ_pathfinder/services/kakao_directions.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/map_location.dart';
import 'package:univ_pathfinder/services/kakao_map.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';
import 'package:univ_pathfinder/widgets/university_selection_controls.dart';

class UniversityMapScreen extends StatefulWidget {
  const UniversityMapScreen({
    super.key,
    this.search,
    this.mapBuilder,
    this.selectionStore,
    this.universityQueries,
    this.openDirections,
    this.layerMapBuilder,
  });
  final Future<List<MapLocation>> Function(String)? search;
  final Widget Function(MapLocation?, List<MapDestination>)? mapBuilder;
  final UniversitySelectionStore? selectionStore;
  final Map<String, String>? universityQueries;
  final bool Function(Uri)? openDirections;

  /// 테스트용: 대학 표시 레이어까지 받는 지도.
  final Widget Function(MapLocation?, List<MapDestination>, UniversityLayer)?
  layerMapBuilder;
  @override
  State<UniversityMapScreen> createState() => _UniversityMapScreenState();
}

class _UniversityMapScreenState extends State<UniversityMapScreen> {
  final _session = CounselingSession.instance;
  final _originText = TextEditingController(),
      _destinationText = TextEditingController();
  final _destinationFocus = FocusNode();
  Map<String, MapDestination> get _destinations => _session.mapDestinations;
  final Map<String, String> _universityQueries = {};
  final Set<String> _attempted = {}, _resolving = {};
  final Map<String, String> _universityErrors = {};
  MapLocation? get _origin => _session.mapOrigin;
  List<MapLocation> _originResults = [], _destinationResults = [];
  String? _originError, _destinationError, _targetUniversity;
  bool _originBusy = false, _destinationBusy = false, _queriesLoaded = false;
  int _originRequest = 0, _destinationRequest = 0;
  bool _byDistance = true;
  KakaoTravelMode _travelMode = KakaoTravelMode.transit;
  bool _showCampuses = false, _campusLoading = false;
  CampusSearchResult? _campuses;

  void _route(MapDestination destination) {
    if (_origin == null || destination.location == null) return;
    final uri = kakaoDirectionsUri(
      _origin!,
      destination.location!,
      _travelMode,
    );
    bool opened;
    try {
      opened = (widget.openDirections ?? openKakaoDirections)(uri);
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('새 창을 열지 못했습니다. 팝업을 허용하거나 링크를 복사하세요.'),
        action: SnackBarAction(
          label: '링크 복사',
          onPressed: () async {
            try {
              await Clipboard.setData(ClipboardData(text: uri.toString()));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('현재 출발지·목적지의 카카오 길찾기 링크를 복사했습니다.'),
                  ),
                );
              }
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('링크를 복사하지 못했습니다. 다시 시도하세요.')),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<List<MapLocation>> _search(String query) =>
      (widget.search ?? searchMapLocations)(query);
  String _error(Object error) => error is StateError
      ? error.message.toString()
      : '장소를 검색하지 못했습니다. 다시 시도하세요.';

  @override
  void initState() {
    super.initState();
    _originText.text = _origin?.name ?? '';
    _session.addListener(_syncUniversities);
    _loadQueries();
  }

  Future<void> _loadQueries() async {
    if (widget.universityQueries != null) {
      _universityQueries.addAll(widget.universityQueries!);
    } else {
      try {
        final tuition = await UniversityRecommendationService().loadTuition();
        for (final row in tuition.rows) {
          // Reference tuition may be from another campus; never borrow that location.
          if (!row.scope.contains('미분리') && !row.scope.contains('본교 참고')) {
            _universityQueries.putIfAbsent(
              row.university,
              () => row.officialName,
            );
          }
        }
      } catch (_) {
        /* College names remain searchable if tuition is unavailable. */
      }
    }
    // Explicit campus qualifiers must survive the official-name expansion.
    _universityQueries.addAll({
      '연세대(서울)': '연세대학교 신촌캠퍼스',
      '고려대(서울)': '고려대학교 서울캠퍼스',
      '한양대(서울)': '한양대학교 서울캠퍼스',
      '한양대(ERICA)': '한양대학교 ERICA캠퍼스',
      '한국외대(서울)': '한국외국어대학교 서울캠퍼스',
      '한국외대(글로벌)': '한국외국어대학교 글로벌캠퍼스',
      '홍익대(서울)': '홍익대학교 서울캠퍼스',
      '건국대(서울)': '건국대학교 서울캠퍼스',
      '동국대(서울)': '동국대학교 서울캠퍼스',
    });
    if (!mounted) return;
    _queriesLoaded = true;
    _syncUniversities();
  }

  void _syncUniversities() {
    if (!mounted || !_queriesLoaded) return;
    final selected = _session.catalogSelection;
    setState(() {
      _destinations.removeWhere(
        (_, d) => d.university != null && !selected.contains(d.university),
      );
      for (final name in selected) {
        _destinations.putIfAbsent(
          'university:$name',
          () => MapDestination(
            id: 'university:$name',
            label: name,
            university: name,
          ),
        );
      }
      if (_targetUniversity != null && !selected.contains(_targetUniversity)) {
        _targetUniversity = null;
        _destinationRequest++;
        _destinationBusy = false;
        _destinationResults = [];
      }
    });
    _attempted.retainAll(selected);
    for (final name in selected) {
      if (_destinations['university:$name']?.location == null &&
          !_resolving.contains(name) &&
          _attempted.add(name)) {
        _resolveUniversity(name);
      }
    }
  }

  Future<void> _resolveUniversity(String name) async {
    if (!mounted) return;
    setState(() {
      _resolving.add(name);
      _universityErrors.remove(name);
    });
    try {
      final query = _universityQueries[name] ?? name;
      final results = await _search(query);
      if (!mounted || !_session.catalogSelection.contains(name)) return;
      final exact = unambiguousUniversity(query, results);
      final id = 'university:$name';
      if (exact != null && _destinations[id]?.location == null) {
        setState(
          () => _destinations[id] = _destinations[id]!.withLocation(exact),
        );
      } else if (exact == null) {
        setState(() => _universityErrors[name] = '캠퍼스 위치를 검색해 선택하세요.');
      }
    } catch (e) {
      if (mounted && _session.catalogSelection.contains(name)) {
        setState(() => _universityErrors[name] = _error(e));
      }
    } finally {
      if (mounted) setState(() => _resolving.remove(name));
    }
  }

  void _editSearch(bool origin) {
    setState(() {
      if (origin) {
        _originRequest++;
        _originResults = [];
        _originError = null;
        _originBusy = false;
      } else {
        _destinationRequest++;
        _destinationResults = [];
        _destinationError = null;
        _destinationBusy = false;
      }
    });
  }

  Future<void> _find(bool origin) async {
    final query = (origin ? _originText : _destinationText).text.trim();
    if (query.isEmpty) {
      setState(() {
        if (origin) {
          _originError = '기관명 또는 주소를 입력하세요.';
        } else {
          _destinationError = '대학·기관명 또는 주소를 입력하세요.';
        }
      });
      return;
    }
    final request = origin ? ++_originRequest : ++_destinationRequest;
    setState(() {
      if (origin) {
        _originBusy = true;
        _originResults = [];
        _originError = null;
      } else {
        _destinationBusy = true;
        _destinationResults = [];
        _destinationError = null;
      }
    });
    try {
      final results = await _search(query);
      if (!mounted ||
          request != (origin ? _originRequest : _destinationRequest)) {
        return;
      }
      setState(() {
        final message = results.isEmpty
            ? '검색 결과가 없습니다. 지역명과 기관명을 함께 입력하거나 도로명·지번 주소로 다시 검색하세요.'
            : null;
        if (origin) {
          _originResults = results;
          _originError = message;
        } else {
          _destinationResults = results;
          _destinationError = message;
        }
      });
    } catch (e) {
      if (mounted &&
          request == (origin ? _originRequest : _destinationRequest)) {
        setState(() {
          if (origin) {
            _originError = _error(e);
          } else {
            _destinationError = _error(e);
          }
        });
      }
    } finally {
      if (mounted &&
          request == (origin ? _originRequest : _destinationRequest)) {
        setState(() {
          if (origin) {
            _originBusy = false;
          } else {
            _destinationBusy = false;
          }
        });
      }
    }
  }

  void _choose(MapLocation place, bool origin) {
    if (!origin && _targetUniversity == null) {
      final duplicate = _destinations.values.any(
        (d) => d.location != null && d.location!.distanceKmTo(place) < 0.001,
      );
      if (duplicate ||
          _destinations.values.where((d) => d.university == null).length >=
              10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              duplicate
                  ? '이미 추가한 목적지입니다.'
                  : '직접 추가하는 목적지는 최대 10개까지 표시할 수 있습니다.',
            ),
          ),
        );
        return;
      }
    }
    setState(() {
      if (origin) {
        _session.mapOrigin = place;
        _originText.text = place.name;
        _originResults = [];
        _originError = null;
      } else {
        final id = _targetUniversity == null
            ? 'custom:${place.id}'
            : 'university:$_targetUniversity';
        if (_targetUniversity == null) {
          _destinations[id] = MapDestination(
            id: id,
            label: place.name,
            location: place,
          );
        } else {
          _destinations[id] = _destinations[id]!.withLocation(place);
          _universityErrors.remove(_targetUniversity);
        }
        _destinationResults = [];
        _destinationText.clear();
        _targetUniversity = null;
        _destinationError = null;
      }
    });
  }

  void _locateUniversity(String name) {
    setState(() {
      _targetUniversity = name;
      _destinationText.text = _universityQueries[name] ?? name;
    });
    _destinationFocus.requestFocus();
    _find(false);
  }

  @override
  void dispose() {
    _session.removeListener(_syncUniversities);
    _originText.dispose();
    _destinationText.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  Widget _searchPanel(bool origin) {
    final busy = origin ? _originBusy : _destinationBusy;
    final error = origin ? _originError : _destinationError;
    final results = origin ? _originResults : _destinationResults;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              origin
                  ? '출발지 검색'
                  : _targetUniversity == null
                  ? '목적지 추가'
                  : '$_targetUniversity 위치 선택',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: origin ? _originText : _destinationText,
              focusNode: origin ? null : _destinationFocus,
              decoration: InputDecoration(
                labelText: origin ? '출발지 기관명 또는 주소' : '목적지 대학·기관명 또는 주소',
                hintText: '예: 서울시청 / 서울 중구 세종대로 110',
              ),
              onChanged: (_) => _editSearch(origin),
              onSubmitted: (_) => _find(origin),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : () => _find(origin),
              icon: const Icon(Icons.search),
              label: Text(origin ? '출발지 검색' : '목적지 검색'),
            ),
            if (!origin && _targetUniversity != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _targetUniversity = null;
                    _destinationText.clear();
                  });
                  _editSearch(false);
                },
                child: const Text('일반 목적지 추가로 전환'),
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error),
            if (results.isNotEmpty)
              Text(
                '검색 결과 ${results.length}개 · 장소명과 주소를 확인하고 선택하세요. 더 정확한 결과는 지역·캠퍼스명을 함께 입력하세요.',
              ),
            for (final p in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text('${p.address}\n${p.category}'),
                isThreeLine: true,
                trailing: const Icon(Icons.add_location_alt_outlined),
                onTap: () => _choose(p, origin),
              ),
            if (origin && _origin != null) ...[
              Text('적용된 출발지: ${_origin!.name}\n${_origin!.address}'),
              TextButton(
                onPressed: () => setState(() {
                  _session.mapOrigin = null;
                  _originText.clear();
                  _originResults = [];
                  _originRequest++;
                  _originBusy = false;
                  _originError = null;
                }),
                child: const Text('출발지 지우기'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _destinationList() {
    final connections = mapConnections(_origin, _destinations.values);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '목적지 ${_destinations.length}개 · 위치 확인 ${_destinations.values.where((d) => d.location != null).length}개',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_destinations.isEmpty)
              const Text('대학 탐색에서 대학을 체크하거나 기관명·주소를 검색해 목적지를 추가하세요.'),
            OutlinedButton.icon(
              icon: const Icon(Icons.directions_car_outlined),
              label: const Text('자동차 통학시간 비교'),
              onPressed: _origin == null || connections.isEmpty
                  ? null
                  : () => showCommuteComparison(
                      context,
                      _origin!,
                      _destinations.values,
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('직선거리 가까운 순'),
              value: _byDistance,
              onChanged: _origin == null
                  ? null
                  : (value) => setState(() => _byDistance = value),
            ),
            DropdownButtonFormField<KakaoTravelMode>(
              initialValue: _travelMode,
              decoration: const InputDecoration(labelText: '카카오 길찾기 이동수단'),
              items: KakaoTravelMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) setState(() => _travelMode = mode);
              },
            ),
            const Text(
              '길찾기는 선택한 출발지·목적지와 이동수단을 카카오맵 새 창으로 전달합니다. 실제 경로·시간은 카카오맵에서 확인하세요. 직선거리 순서와 실제 이동시간 순서는 다를 수 있습니다.',
            ),
            for (final d in orderedMapDestinations(
              _origin,
              _destinations.values,
              byDistance: _byDistance,
            ))
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      d.location == null
                          ? Icons.location_searching
                          : Icons.location_on,
                      color:
                          connections.any(
                            (c) => c.destination.id == d.id && c.nearest,
                          )
                          ? const Color(0xFFD94C20)
                          : const Color(0xFF2867B2),
                    ),
                    title: Text(d.label),
                    subtitle: Text(
                      d.location == null
                          ? _resolving.contains(d.university)
                                ? '카카오에서 위치 검색 중…'
                                : _universityErrors[d.university] ?? '위치 선택 필요'
                          : '${d.location!.name}\n${d.location!.address}${connections.where((c) => c.destination.id == d.id).map((c) => '\n직선거리 ${c.distanceKm.toStringAsFixed(2)}km${c.nearest ? " · 최단" : ""}').join()}',
                    ),
                    trailing: d.university != null
                        ? IconButton(
                            tooltip: '${d.label} 위치 선택·변경',
                            onPressed: () => _locateUniversity(d.university!),
                            icon: const Icon(Icons.edit_location_alt_outlined),
                          )
                        : IconButton(
                            tooltip: '${d.label} 목적지 삭제',
                            onPressed: () =>
                                setState(() => _destinations.remove(d.id)),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  TextButton.icon(
                    key: ValueKey('route:${d.id}'),
                    onPressed: _origin == null || d.location == null
                        ? null
                        : () => _route(d),
                    icon: const Icon(Icons.directions_outlined),
                    label: Text('${d.label} 카카오 길찾기'),
                  ),
                ],
              ),
            if (_origin != null && connections.isNotEmpty)
              Text(
                '위치가 확인된 ${connections.length}개 목적지 중 최단 직선거리를 주황색으로 강조합니다. 1m 이내 차이는 공동 최단입니다.',
              ),
            if (_destinations.values.any((d) => d.location == null))
              const Text(
                '위치 미확인 대학은 지도와 최단거리 비교에서 제외됩니다. 위치 선택 버튼으로 캠퍼스를 확인하세요.',
              ),
          ],
        ),
      ),
    );
  }

  UniversityLayer get _campusLayer => UniversityLayer(
    visible: _showCampuses,
    onFound: (result) {
      if (!mounted || !_showCampuses) return;
      setState(() {
        // 새 검색 시작 알림이면 이전 목록을 지우고 검색 중으로 표시한다.
        _campuses = result.searching ? null : result;
        _campusLoading = result.searching;
      });
    },
    onTap: _campusTapped,
  );

  void _toggleCampuses(bool on) => setState(() {
    _showCampuses = on;
    _campusLoading = on;
    _campuses = null;
  });

  // 지도에서 대학을 누르면 이름·주소를 보여 주고 목적지 추가를 제안한다.
  void _campusTapped(MapLocation place) {
    if (!mounted) return;
    final app = appUniversityFor(place, _universityQueries);
    // 버튼이 달린 스낵바는 저절로 닫히지 않아 다음 알림이 밀리므로, 앞 알림을 닫고 시간이 지나면 닫히게 한다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 6),
          content: Text(
            '${place.name}\n${place.address}${app == null ? '' : '\n앱 대학 목록: $app'}',
          ),
          action: SnackBarAction(
            label: '목적지에 추가',
            onPressed: () => _choose(place, false),
          ),
        ),
      );
  }

  Widget _campusList() {
    final result = _campuses;
    final selected = _session.catalogSelection;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result == null
                  ? '지도 영역의 대학'
                  : '지도 영역의 대학 ${result.places.length}곳',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_campusLoading) const LinearProgressIndicator(),
            if (result?.tooWide == true)
              const Text(
                '지도가 너무 넓어 대학을 검색하지 않았습니다. 지도를 확대한 뒤 지도 위 "현 지도에서 검색"을 누르세요.',
              ),
            if (result?.needsReload == true)
              const Text(
                '지도 기능이 새로 바뀌었습니다. 브라우저에서 강력 새로고침(Ctrl+Shift+R 또는 Ctrl+F5)을 한 뒤 다시 켜 주세요.',
              ),
            if (result?.failed == true)
              const Text('대학을 검색하지 못했습니다. 지도를 조금 옮긴 뒤 "현 지도에서 검색"을 다시 누르세요.'),
            if (result != null &&
                !result.tooWide &&
                !result.failed &&
                result.places.isEmpty)
              const Text('이 지도 영역에는 대학이 없습니다. 지도를 옮기거나 축소한 뒤 다시 검색하세요.'),
            if (result?.truncated == true)
              const Text(
                '대학이 많아 카카오 검색 결과 최대 개수까지만 표시했습니다. 지도를 확대하면 빠진 대학을 찾을 수 있습니다.',
              ),
            for (final p in result?.places ?? const <MapLocation>[])
              Builder(
                builder: (context) {
                  final app = appUniversityFor(p, _universityQueries);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.school_outlined),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.address}${app == null ? '' : '\n앱 대학 목록에 있음: $app (전형·입결 비교 가능)'}',
                    ),
                    isThreeLine: app != null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (app != null && !selected.contains(app))
                          IconButton(
                            tooltip: '$app 관심 대학에 추가',
                            icon: const Icon(Icons.star_outline),
                            onPressed: () {
                              if (!_session.toggleCatalogUniversity(app)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('관심 대학은 최대 10곳까지 고를 수 있습니다.'),
                                  ),
                                );
                              }
                            },
                          ),
                        IconButton(
                          tooltip: '${p.name} 목적지에 추가',
                          icon: const Icon(Icons.add_location_alt_outlined),
                          onPressed: () => _choose(p, false),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const Text(
              '카카오 장소 분류의 "대학교"를 지도에 보이는 영역 안에서 찾습니다. 지도를 옮긴 뒤 지도 위 "현 지도에서 검색"을 누르면 그 영역을 다시 찾습니다. 앱 대학 목록 표시는 이름이 정확히 같은 경우만 붙입니다.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _map() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          FilterChip(
            avatar: const Icon(Icons.school_outlined, size: 18),
            label: const Text('대학'),
            tooltip: '지도에 보이는 영역의 대학 표시',
            selected: _showCampuses,
            onSelected: _toggleCampuses,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('초록: 출발지 · 파랑: 목적지/일반 직선 · 주황: 최단 직선 · 보라: 지도 영역의 대학'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: MediaQuery.sizeOf(context).width < 850 ? 380 : 620,
        child:
            widget.layerMapBuilder?.call(
              _origin,
              _destinations.values.toList(),
              _campusLayer,
            ) ??
            widget.mapBuilder?.call(_origin, _destinations.values.toList()) ??
            KakaoMapView(
              origin: _origin,
              destinations: _destinations.values.toList(),
              universities: _campusLayer,
            ),
      ),
      const Text(
        '직선거리는 도로·대중교통 최단 경로나 소요시간과 다릅니다. 검색어는 카카오에 전달됩니다. 선택한 위치는 앱 실행 중에 유지되며 로그아웃하면 지워집니다.',
      ),
      if (_showCampuses) _campusList(),
      _destinationList(),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('출발지·대학 직선거리 지도')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UniversitySelectionControls(store: widget.selectionStore),
              _searchPanel(true),
              _searchPanel(false),
            ],
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: constraints.maxWidth >= 850
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 360, child: controls),
                          const SizedBox(width: 20),
                          Expanded(child: _map()),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          controls,
                          const SizedBox(height: 16),
                          _map(),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
