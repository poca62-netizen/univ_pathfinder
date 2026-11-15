import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/map_location.dart';

bool openKakaoDirections(Uri uri) => false;
bool openAdmissionSource(Uri uri) => false;

Future<List<MapLocation>> searchMapLocations(String query) async =>
    throw StateError('카카오 지도 검색은 웹 버전에서 사용할 수 있습니다.');

class KakaoMapView extends StatelessWidget {
  const KakaoMapView({
    super.key,
    required this.origin,
    required this.destinations,
  });
  final MapLocation? origin;
  final List<MapDestination> destinations;
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('카카오 지도는 웹 버전에서 사용할 수 있습니다.'));
}
