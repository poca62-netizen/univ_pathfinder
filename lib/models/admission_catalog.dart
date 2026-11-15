class AdmissionTrack {
  const AdmissionTrack({
    required this.university,
    required this.department,
    required this.type,
    required this.name,
    required this.quota,
    required this.eligibility,
    required this.recommendation,
    required this.recommender,
    required this.selection,
    required this.minimum,
    required this.section,
    this.officialReview = const {},
    this.specialEligibilityOverride,
  });
  final Map<String, String> officialReview;
  final bool? specialEligibilityOverride;
  final String university,
      department,
      type,
      name,
      quota,
      eligibility,
      recommendation,
      recommender,
      selection,
      minimum,
      section;
  factory AdmissionTrack.fromJson(Map<String, dynamic> r) => AdmissionTrack(
    university: r['university'] as String,
    department: r['department'] as String,
    type: r['type'] as String,
    name: r['name'] as String,
    quota: r['quota'] as String,
    eligibility: r['eligibility'] as String,
    recommendation: r['recommendation'] as String,
    recommender: r['recommender'] as String,
    selection: r['selection'] as String,
    minimum: r['minimum'] as String,
    section: r['section'] as String,
    officialReview: Map.unmodifiable(
      Map<String, String>.from(r['officialReview'] as Map? ?? const {}),
    ),
    specialEligibilityOverride: r['specialEligibilityOverride'] as bool?,
  );
  bool get requiresSpecialEligibility =>
      specialEligibilityOverride ??
      RegExp(
        '농어촌|기회균형|기초생활|차상위|특성화|장애|특수교육|보훈|사회통합|사회배려|다문화|재외|성인|만학|재직|수도자|가톨릭지도자|북한|서해|지역인재|교육인재|특성화고',
      ).hasMatch('$name $eligibility');
}

class AdmissionCatalog {
  AdmissionCatalog({
    required this.year,
    required this.source,
    required this.status,
    required this.tracks,
  });
  final int year;
  final String source, status;
  final List<AdmissionTrack> tracks;
  factory AdmissionCatalog.fromJson(Map<String, dynamic> r) => AdmissionCatalog(
    year: r['year'] as int,
    source: r['source'] as String,
    status: r['status'] as String,
    tracks: (r['rows'] as List)
        .map((r) => AdmissionTrack.fromJson(Map<String, dynamic>.from(r)))
        .toList(),
  );
}
