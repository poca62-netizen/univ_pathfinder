import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/models/map_location.dart';

Future<void> showCommuteComparison(
  BuildContext context,
  MapLocation origin,
  Iterable<MapDestination> destinations,
) async {
  final resolved = destinations.where((item) => item.location != null).toList();
  if (resolved.isEmpty) return;
  final future = _load(origin, resolved);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('자동차 통학시간 비교'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<_Commute>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text(snapshot.error.toString());
            final rows = snapshot.data;
            if (rows == null) return const LinearProgressIndicator();
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('출발지 ${origin.name}'),
                  const Text('카카오모빌리티 조회 시점 예상 · 소요시간 짧은 순'),
                  for (final row in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.label),
                      subtitle: Text(
                        row.seconds == null
                            ? '자동차 경로를 확인하지 못했습니다.'
                            : '약 ${(row.seconds! / 60).ceil()}분 · ${(row.meters! / 1000).toStringAsFixed(1)} km',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
}

class _Commute {
  const _Commute(this.label, this.seconds, this.meters);
  final String label;
  final int? seconds, meters;
}

Future<List<_Commute>> _load(
  MapLocation origin,
  List<MapDestination> destinations,
) async {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    // The offline preview has no initialized Supabase client.
  }
  if (client == null || client.auth.currentSession == null) {
    throw '자동차 통학시간을 비교하려면 로그인하세요.';
  }
  Map<String, double> point(MapLocation place) => {
    'x': place.longitude,
    'y': place.latitude,
  };
  try {
    final response = await client.functions
        .invoke(
          'commute-times',
          body: {
            'origin': point(origin),
            'destinations': destinations
                .map((item) => point(item.location!))
                .toList(),
          },
        )
        .timeout(const Duration(seconds: 35));
    final data = response.data;
    final routes = data is Map ? data['routes'] : null;
    if (routes is! List || routes.length != destinations.length) {
      throw const FormatException();
    }
    final rows = <_Commute>[];
    for (var i = 0; i < destinations.length; i++) {
      final route = routes[i];
      final seconds = route is Map ? route['duration'] : null;
      final meters = route is Map ? route['distance'] : null;
      rows.add(
        seconds is int && seconds >= 0 && meters is int && meters >= 0
            ? _Commute(destinations[i].label, seconds, meters)
            : _Commute(destinations[i].label, null, null),
      );
    }
    rows.sort((a, b) {
      final order = (a.seconds ?? double.infinity).compareTo(
        b.seconds ?? double.infinity,
      );
      return order == 0 ? a.label.compareTo(b.label) : order;
    });
    return rows;
  } on FunctionException catch (error) {
    if (error.status == 404 || error.status == 503) {
      throw '자동차 통학시간 비교 기능의 서버 설정이 필요합니다.';
    }
    throw '자동차 경로를 조회하지 못했습니다. 잠시 후 다시 시도하세요.';
  } catch (_) {
    throw '자동차 경로를 조회하지 못했습니다. 서버 설정과 네트워크를 확인한 뒤 다시 시도하세요.';
  }
}
