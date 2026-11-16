import 'package:univ_pathfinder/models/counseling_session.dart';

class MapLocation {
  MapLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.category = '',
  }) {
    GeoPoint(latitude, longitude);
  }
  final String id, name, address, category;
  final double latitude, longitude;
  factory MapLocation.fromJson(Map<String, dynamic> value) => MapLocation(
    id: value['id'] as String,
    name: value['name'] as String,
    address: value['address'] as String,
    category: value['category'] as String? ?? '',
    latitude: (value['latitude'] as num).toDouble(),
    longitude: (value['longitude'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };
  double distanceKmTo(MapLocation other) => GeoPoint(
    latitude,
    longitude,
  ).distanceKmTo(GeoPoint(other.latitude, other.longitude));
}

class MapDestination {
  const MapDestination({
    required this.id,
    required this.label,
    this.location,
    this.university,
  });
  final String id, label;
  final String? university;
  final MapLocation? location;
  MapDestination withLocation(MapLocation place) => MapDestination(
    id: id,
    label: label,
    university: university,
    location: place,
  );
}

class MapConnection {
  const MapConnection(this.destination, this.distanceKm, this.nearest);
  final MapDestination destination;
  final double distanceKm;
  final bool nearest;
  Map<String, dynamic> toJson() => {
    ...destination.location!.toJson(),
    'label': destination.label,
    'distanceKm': distanceKm,
    'nearest': nearest,
  };
}

List<MapConnection> mapConnections(
  MapLocation? origin,
  Iterable<MapDestination> destinations,
) {
  if (origin == null) return [];
  final resolved = destinations.where((d) => d.location != null).toList();
  if (resolved.isEmpty) return [];
  final distances = {
    for (final d in resolved) d.id: origin.distanceKmTo(d.location!),
  };
  final minimum = distances.values.reduce((a, b) => a < b ? a : b);
  // Treat differences of at most one metre as joint nearest, before rounding.
  return [
    for (final d in resolved)
      MapConnection(d, distances[d.id]!, distances[d.id]! - minimum <= 0.001),
  ]..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
}

/// Only exact university/campus matches are safe to apply without user choice.
MapLocation? unambiguousUniversity(String query, List<MapLocation> places) {
  String compact(String text) =>
      text.replaceAll(RegExp(r'[\s()]'), '').toLowerCase();
  final expected = compact(query);
  final matches = places
      .where(
        (p) =>
            (p.category.contains('대학교') || p.category.contains('대학')) &&
            compact(p.name) == expected,
      )
      .toList();
  return matches.length == 1 ? matches.single : null;
}

/// 지도 영역의 대학 검색 결과(카카오 장소 카테고리 '학교' 중 대학교).
class CampusSearchResult {
  const CampusSearchResult({
    this.places = const [],
    this.failed = false,
    this.tooWide = false,
    this.truncated = false,
    this.needsReload = false,
    this.searching = false,
  });

  /// '현 지도에서 검색'을 눌러 새 검색을 시작했다(결과는 뒤에 따로 온다).
  final bool searching;

  final List<MapLocation> places;

  /// 카카오 검색이 실패했다(결과 없음과 구분).
  final bool failed;

  /// 지도가 너무 넓어 검색하지 않았다(확대 안내).
  final bool tooWide;

  /// 카카오가 주는 최대 개수(45곳)에 닿아 일부만 표시했다.
  final bool truncated;

  /// 브라우저에 예전 지도 스크립트가 남아 대학 표시를 쓸 수 없다(새로고침 안내).
  final bool needsReload;

  factory CampusSearchResult.fromJson(Map<String, dynamic> j) =>
      CampusSearchResult(
        places: [
          for (final p in j['places'] as List? ?? const [])
            MapLocation.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        failed: j['failed'] == true,
        tooWide: j['tooWide'] == true,
        truncated: j['truncated'] == true,
        searching: j['searching'] == true,
      );
}

/// 지도 위 대학 표시 켜기·끄기와 결과·마커 클릭을 화면에 전달한다.
class UniversityLayer {
  const UniversityLayer({
    required this.visible,
    required this.onFound,
    required this.onTap,
  });

  final bool visible;
  final void Function(CampusSearchResult result) onFound;
  final void Function(MapLocation place) onTap;
}

/// 카카오 장소 이름이 앱의 대학(검색어)과 정확히 같으면 그 앱 대학 이름을 준다.
/// 캠퍼스가 여럿인 대학을 잘못 잇지 않도록 정확히 같은 경우만 인정한다.
String? appUniversityFor(MapLocation place, Map<String, String> queries) {
  String compact(String text) =>
      text.replaceAll(RegExp(r'[\s()]'), '').toLowerCase();
  final name = compact(place.name);
  final hits = {
    for (final e in queries.entries)
      if (compact(e.value) == name) e.key,
  };
  return hits.length == 1 ? hits.single : null;
}
