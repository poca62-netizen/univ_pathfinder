import 'package:univ_pathfinder/models/map_location.dart';

enum KakaoTravelMode {
  transit('traffic', '대중교통'),
  car('car', '자동차'),
  walk('walk', '도보'),
  bicycle('bicycle', '자전거');

  const KakaoTravelMode(this.code, this.label);
  final String code, label;
}

Uri kakaoDirectionsUri(
  MapLocation origin,
  MapLocation destination,
  KakaoTravelMode mode,
) {
  String point(MapLocation p) =>
      '${Uri.encodeComponent(p.name)},${p.latitude},${p.longitude}';
  return Uri.parse(
    'https://map.kakao.com/link/by/${mode.code}/${point(origin)}/${point(destination)}',
  );
}

List<MapDestination> orderedMapDestinations(
  MapLocation? origin,
  Iterable<MapDestination> destinations, {
  required bool byDistance,
}) {
  final list = destinations.toList();
  if (!byDistance || origin == null) return list;
  list.sort((a, b) {
    if (a.location == null && b.location == null) {
      return a.label.compareTo(b.label);
    }
    if (a.location == null) return 1;
    if (b.location == null) return -1;
    final order = origin
        .distanceKmTo(a.location!)
        .compareTo(origin.distanceKmTo(b.location!));
    return order == 0 ? a.label.compareTo(b.label) : order;
  });
  return list;
}
