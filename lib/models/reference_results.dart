/// 참고 입결(예측에 쓰지 않음).
///
/// 어디가 결과표에 없어 판단 보류인 전형에 대해 대학이 직접 공개한 입시결과의 학과별 수치.
/// 지표가 어디가(최종 등록자 50%·70% 컷)와 달라(예: 최초+충원 합격자 평균) 안정·적정 등 예측에는
/// 쓰지 않고, 판단 보류 목록에 지표·연도·출처와 함께 참고로만 보여 준다.
/// 생성: `node tools/build_reference_results.mjs --write`.
class ReferenceSource {
  const ReferenceSource({
    required this.id,
    required this.university,
    required this.year,
    required this.title,
    required this.url,
    required this.metric,
    this.note = '',
    this.mirror = '',
  });

  final String id, university, title, url, metric, note, mirror;
  final int year;

  factory ReferenceSource.fromJson(Map<String, dynamic> j) => ReferenceSource(
    id: j['id'] as String,
    university: j['university'] as String,
    year: j['year'] as int,
    title: j['title'] as String,
    url: j['url'] as String,
    metric: j['metric'] as String,
    note: j['note'] as String? ?? '',
    mirror: j['mirror'] as String? ?? '',
  );
}

class ReferenceResultRow {
  const ReferenceResultRow({
    required this.source,
    required this.university,
    required this.year,
    required this.sourceTrack,
    required this.tracks,
    required this.department,
    required this.value,
    required this.metric,
    this.quota,
  });

  final String source, university, sourceTrack, department, metric;
  final int year;

  /// 이 결과를 참고로 붙일 2028 전형명(같은 기준인지는 검증하지 않음).
  final List<String> tracks;
  final int? quota;

  /// 교과 등급(지표는 [metric]).
  final double value;

  factory ReferenceResultRow.fromJson(Map<String, dynamic> j) =>
      ReferenceResultRow(
        source: j['source'] as String,
        university: j['university'] as String,
        year: j['year'] as int,
        sourceTrack: j['sourceTrack'] as String,
        tracks: [for (final t in j['tracks'] as List) t as String],
        department: j['department'] as String,
        value: (j['value'] as num).toDouble(),
        metric: j['metric'] as String,
        quota: j['quota'] as int?,
      );
}

/// 한 판단 보류 전형에 붙일 참고 입결 묶음(같은 해·같은 원본 전형).
class ReferenceGroup {
  const ReferenceGroup({required this.source, required this.rows});
  final ReferenceSource source;
  final List<ReferenceResultRow> rows;

  /// 화면·복사용 한 줄. 학과가 많으면 앞의 [limit]개만 쓰고 나머지 수를 밝힌다.
  String describe({int limit = 8}) {
    final first = rows.first;
    final shown = rows
        .take(limit)
        .map((r) => '${r.department} ${r.value.toStringAsFixed(2)}')
        .join(', ');
    final more = rows.length > limit ? ' 외 ${rows.length - limit}개' : '';
    final note = source.note.isEmpty ? '' : ' · ${source.note}';
    return '참고(예측에 쓰지 않음) · ${first.year} ${first.sourceTrack} · '
        '${source.metric}: $shown$more · 출처 ${source.title}(${source.mirror})$note';
  }
}

class ReferenceResults {
  const ReferenceResults({
    required this.sources,
    required this.rows,
    this.checkedAt = '',
  });

  final List<ReferenceSource> sources;
  final List<ReferenceResultRow> rows;
  final String checkedAt;

  factory ReferenceResults.fromJson(Map<String, dynamic> j) => ReferenceResults(
    checkedAt: j['checkedAt'] as String? ?? '',
    sources: [
      for (final s in j['sources'] as List? ?? const [])
        ReferenceSource.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
    rows: [
      for (final r in j['rows'] as List? ?? const [])
        ReferenceResultRow.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
  );

  /// [university]의 2028 [track]에 붙일 참고 입결을 해·원본 전형별로 묶는다(최근 해 먼저).
  /// [departmentMatches]로 관심 분야 학과만 남긴다.
  List<ReferenceGroup> forTrack(
    String university,
    String track,
    bool Function(String department) departmentMatches,
  ) {
    final groups = <String, List<ReferenceResultRow>>{};
    for (final r in rows) {
      if (r.university != university || !r.tracks.contains(track)) continue;
      if (!departmentMatches(r.department)) continue;
      (groups['${r.source}|${r.sourceTrack}'] ??= []).add(r);
    }
    final out = [
      for (final e in groups.entries)
        if (sources.where((s) => s.id == e.value.first.source).firstOrNull
            case final s?)
          ReferenceGroup(source: s, rows: e.value),
    ];
    out.sort((a, b) => b.source.year.compareTo(a.source.year));
    return out;
  }
}
