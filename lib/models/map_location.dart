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
