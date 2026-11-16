import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('assets/data/$name.json').readAsStringSync())
        as Map<String, dynamic>;

// 가상 대학의 가상 입결.
SusiResult _s(int year, String track) => SusiResult(
  university: '가대',
  year: year,
  type: '미상',
  track: track,
  department: '컴퓨터공학과',
  quota: 20,
  cut50: 2.7,
  cut70: 3.0,
  metric: '50%컷',
);

List<AdmissionPrediction> _run(bool apply) =>
    AdmissionPredictionService().predict(
      results: AdmissionResults(
        source: '',
        susi: [_s(2024, '학생부종합(일반)'), _s(2025, '학생부종합(서류형)')],
        regular: const [],
      ),
      catalog: AdmissionCatalog(
        year: 2028,
        source: '',
        status: '',
        tracks: [
          AdmissionTrack(
            university: '가대',
            department: '',
            type: '학생부종합',
            name: '학생부종합(서류형)',
            quota: '10명',
            eligibility: '',
            recommendation: '',
            recommender: '',
            selection: '',
            minimum: '없음',
            section: '서울',
          ),
        ],
      ),
      student: const StudentProfile(
        grade9Optimistic: 2.4,
        grade9Conservative: 2.6,
      ),
      interest: '컴퓨터',
      matches: (t, i) => t.contains(i),
      aliases: AdmissionAliases(
        tracks: [
          TrackAlias(
            university: '가대',
            fromYear: 2024,
            from: '학생부종합(일반)',
            toYear: 2025,
            to: '학생부종합(서류형)',
            apply: apply,
            change: '없음',
          ),
        ],
      ),
    );

void main() {
  test('apply=true인 전형명 변경만 같은 전형으로 묶고 사유를 밝힌다', () {
    final merged = _run(true).single;
    expect(merged.evidence, hasLength(2));
    expect(
      merged.reason,
      contains('2024 전형명 "학생부종합(일반)"을 2025 "학생부종합(서류형)"와 같은 전형으로 묶음'),
    );
    expect(merged.reason, isNot(contains('한 해 입결만')));

    final kept = _run(false);
    expect(kept, hasLength(1)); // 2024 전형은 2028에 없어 빠지고 2025만 남는다
    expect(kept.single.reason, contains('한 해 입결만'));
  });

  test('대응표: 모든 항목에 근거·공식 출처가 있고, 묶는 항목의 이전·새 전형명은 실제 입결에 있다', () {
    final aliases = _read('admission_aliases');
    final results = AdmissionResults.fromJson(_read('admission_results'));
    final catalog = AdmissionCatalog.fromJson(_read('admissions_2028'));
    final s = AdmissionPredictionService();
    expect(aliases['checkedAt'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final entries = [
      ...(aliases['tracks'] as List).cast<Map<String, dynamic>>(),
      ...(aliases['departments'] as List).cast<Map<String, dynamic>>(),
    ];
    for (final e in entries) {
      expect(e['apply'], isA<bool>(), reason: '$e');
      expect((e['evidence'] as String).length, greaterThan(20), reason: '$e');
      expect(e['url'], startsWith('https://'), reason: '$e');
      final official = (e['url'] as String).startsWith('https://www.adiga.kr/');
      // 묶는 항목은 대학 공개 자료(어디가)만 근거로 인정한다. 묶지 않는 기록은 보도도 되지만 출처 종류를 밝힌다.
      if (e['apply'] == true) expect(official, isTrue, reason: '$e');
      if (!official) expect(e['source'], isNotNull, reason: '$e');
    }
    for (final a in AdmissionAliases.fromJson(
      aliases,
    ).tracks.where((a) => a.apply)) {
      expect(
        results.susi.any(
          (r) =>
              r.university == a.university &&
              r.year == a.fromYear &&
              r.track == a.from,
        ),
        isTrue,
        reason: '입결에 없는 이전 전형명: ${a.from}',
      );
      // 새 이름은 그해 입결에 있거나(2025까지), 2028로 잇는 경우 2028 전형계획에 있어야 한다.
      final found = a.toYear == 2028
          ? catalog.tracks.any(
              (t) =>
                  t.university == a.university &&
                  s.trackKey(t.name) == s.trackKey(a.to),
            )
          : results.susi.any(
              (r) =>
                  r.university == a.university &&
                  r.year == a.toYear &&
                  s.trackKey(r.track) == s.trackKey(a.to),
            );
      expect(found, isTrue, reason: '찾을 수 없는 새 전형명: ${a.to}');
    }
    // 끊거나(block) 경고하는(caution) 항목은 그 해까지의 입결과 2028 전형이 실제로 있어야 한다.
    for (final a in AdmissionAliases.fromJson(
      aliases,
    ).tracks.where((a) => a.block || a.caution)) {
      expect(a.block && a.caution, isFalse, reason: a.from);
      expect(
        results.susi.any(
          (r) =>
              r.university == a.university &&
              r.year <= a.fromYear &&
              s.trackKey(r.track) == s.trackKey(a.from),
        ),
        isTrue,
        reason: '입결에 없는 전형: ${a.university} ${a.from}',
      );
      expect(
        catalog.tracks.any(
          (t) =>
              t.university == a.university &&
              s.trackKey(t.name) == s.trackKey(a.to),
        ),
        isTrue,
        reason: '2028 전형계획에 없는 전형: ${a.university} ${a.to}',
      );
    }
  });

  test('실제 번들: 결과표 제목 대신 열 이름이 전형명으로 들어간 행이 없다', () {
    final results = AdmissionResults.fromJson(_read('admission_results'));
    final bad = RegExp(r'^(계열|구분|모집단위|모집인원|경쟁률|평가에반영된교과목)$');
    expect(results.susi.where((r) => bad.hasMatch(r.track)), isEmpty);
    expect(
      results.susi.where(
        (r) => r.university == '이화여대' && r.track.contains('미래인재'),
      ),
      isNotEmpty,
    );
  });

  test('실제 번들: 을지대 지역균형 → 학교장추천은 의예과만 빼고 잇는다', () {
    final results = AdmissionResults.fromJson(_read('admission_results'));
    final catalog = AdmissionCatalog.fromJson(_read('admissions_2028'));
    final aliases = AdmissionAliases.fromJson(_read('admission_aliases'));
    final ps = AdmissionPredictionService().predict(
      results: results,
      catalog: catalog,
      student: const StudentProfile(
        grade9Optimistic: 2.4,
        grade9Conservative: 2.7,
      ),
      interest: '',
      matches: (_, _) => true,
      aliases: aliases,
    );
    final eulji = ps.where(
      (p) => p.university == '을지대' && p.track == '학교장추천전형',
    );
    expect(eulji.map((p) => p.department), contains('방사선학과'));
    expect(eulji.where((p) => p.department.startsWith('의예')), isEmpty);
    expect(eulji.first.reason, contains('"지역균형"을 2028 "학교장추천전형"와 같은 전형으로 묶음'));

    // 서울여대: 두 전형을 합친 결과표를 교과우수자로 잇되 체육(스포츠운동과학과)은 뺀다.
    final swu = ps.where((p) => p.university == '서울여대' && p.track == '교과우수자전형');
    expect(swu, isNotEmpty);
    expect(swu.where((p) => p.department == '스포츠운동과학과'), isEmpty);
    expect(swu.first.reason, contains('신뢰도 한 단계 낮춤')); // 2024 반영방법 변경
  });

  test('caution=true면 입결을 잇되 사유를 밝히고 신뢰도를 한 단계 낮춘다', () {
    AdmissionPredictionService s() => AdmissionPredictionService();
    final results = AdmissionResults(
      source: '',
      susi: [_s(2024, '학생부교과(지역균형)'), _s(2025, '학생부교과(지역균형)')],
      regular: const [],
    );
    final catalog = AdmissionCatalog(
      year: 2028,
      source: '',
      status: '',
      tracks: [
        AdmissionTrack(
          university: '가대',
          department: '',
          type: '학생부교과',
          name: '지역균형전형',
          quota: '10명',
          eligibility: '',
          recommendation: '',
          recommender: '',
          selection: '',
          minimum: '없음',
          section: '서울',
        ),
      ],
    );
    const student = StudentProfile(
      grade9Optimistic: 2.4,
      grade9Conservative: 2.6,
    );
    List<AdmissionPrediction> run([AdmissionAliases? aliases]) => s().predict(
      results: results,
      catalog: catalog,
      student: student,
      interest: '컴퓨터',
      matches: (t, i) => t.contains(i),
      aliases: aliases,
    );
    final plain = run().single;
    final warned = run(
      const AdmissionAliases(
        tracks: [
          TrackAlias(
            university: '가대',
            fromYear: 2025,
            from: '학생부교과(지역균형)',
            toYear: 2028,
            to: '지역균형전형',
            apply: false,
            caution: true,
            change: '2026 진로선택 반영 방법 변경',
          ),
        ],
      ),
    ).single;
    expect(warned.evidence, hasLength(2)); // 입결은 그대로 잇는다
    expect(warned.level, plain.level);
    const levels = ['낮음', '보통', '높음'];
    expect(
      levels.indexOf(warned.confidence),
      (levels.indexOf(plain.confidence) - 1).clamp(0, 2),
    );
    expect(warned.reason, contains('2025학년도까지 입결 뒤 2026 진로선택 반영 방법 변경'));
  });

  test('이름 변경으로 묶인 옛 입결도 새 이름 기준 block에 함께 끊긴다', () {
    final ps = AdmissionPredictionService().predict(
      results: AdmissionResults(
        source: '',
        susi: [_s(2024, '학생부종합(옛면접형)'), _s(2025, '학생부종합(새면접형)')],
        regular: const [],
      ),
      catalog: AdmissionCatalog(
        year: 2028,
        source: '',
        status: '',
        tracks: [
          AdmissionTrack(
            university: '가대',
            department: '',
            type: '학생부종합',
            name: '새면접형전형',
            quota: '10명',
            eligibility: '',
            recommendation: '',
            recommender: '',
            selection: '',
            minimum: '없음',
            section: '서울',
          ),
        ],
      ),
      student: const StudentProfile(
        grade9Optimistic: 2.4,
        grade9Conservative: 2.6,
      ),
      interest: '컴퓨터',
      matches: (t, i) => t.contains(i),
      aliases: const AdmissionAliases(
        tracks: [
          TrackAlias(
            university: '가대',
            fromYear: 2024,
            from: '학생부종합(옛면접형)',
            toYear: 2025,
            to: '학생부종합(새면접형)',
            apply: true,
          ),
          TrackAlias(
            university: '가대',
            fromYear: 2025,
            from: '학생부종합(새면접형)',
            toYear: 2028,
            to: '새면접형전형',
            apply: false,
            block: true,
          ),
        ],
      ),
    );
    expect(ps, isEmpty);
  });

  test('실제 번들: 점검으로 끊은 고려대 학교추천전형은 판단 보류에 변경 사유와 함께 나온다', () {
    final results = AdmissionResults.fromJson(_read('admission_results'));
    final catalog = AdmissionCatalog.fromJson(_read('admissions_2028'));
    final aliases = AdmissionAliases.fromJson(_read('admission_aliases'));
    final s = AdmissionPredictionService();
    bool matches(String t, String i) => t.contains(i);
    const student = StudentProfile(
      grade9Optimistic: 2.4,
      grade9Conservative: 2.7,
    );
    final ps = s.predict(
      results: results,
      catalog: catalog,
      student: student,
      interest: '컴퓨터',
      matches: matches,
      aliases: aliases,
    );
    expect(
      ps.where((p) => p.university == '고려대(서울)' && p.track == '학교추천전형'),
      isEmpty,
    );
    final u = s.untrackedTracks(
      predictions: ps,
      results: results,
      catalog: catalog,
      interest: '컴퓨터',
      matches: matches,
      aliases: aliases,
    );
    expect(
      u
          .singleWhere((t) => t.university == '고려대(서울)' && t.track == '학교추천전형')
          .note,
      contains('반영비율 변경'),
    );
    // 경고 항목: 가톨릭대 지역균형은 예측에 남되 사유가 붙는다.
    final ck = ps.where((p) => p.university == '가톨릭대' && p.track == '지역균형전형');
    expect(ck, isNotEmpty);
    expect(ck.first.reason, contains('신뢰도 한 단계 낮춤'));
  });

  test('실제 번들: 한양대 2028 학업형은 판단 보류 목록에 통합 사유와 함께 나온다', () {
    final results = AdmissionResults.fromJson(_read('admission_results'));
    final catalog = AdmissionCatalog.fromJson(_read('admissions_2028'));
    final aliases = AdmissionAliases.fromJson(_read('admission_aliases'));
    final s = AdmissionPredictionService();
    bool matches(String t, String i) => t.contains(i);
    final predictions = s.predict(
      results: results,
      catalog: catalog,
      student: const StudentProfile(
        grade9Optimistic: 2.4,
        grade9Conservative: 2.7,
      ),
      interest: '컴퓨터',
      matches: matches,
      aliases: aliases,
    );
    final untracked = s.untrackedTracks(
      predictions: predictions,
      results: results,
      catalog: catalog,
      interest: '컴퓨터',
      matches: matches,
      aliases: aliases,
    );
    final hanyang = untracked.where(
      (t) => t.university == '한양대(서울)' && t.track == '학업형전형',
    );
    expect(hanyang.single.note, contains('통합'));
    // 예측에 이미 있는 전형과 특별전형은 판단 보류 목록에 넣지 않는다.
    final predicted = {
      for (final p in predictions) '${p.university}|${s.trackKey(p.track)}',
    };
    for (final t in untracked) {
      expect(
        predicted,
        isNot(contains('${t.university}|${s.trackKey(t.track)}')),
      );
      expect(t.track, isNot(contains('농어촌')));
    }
  });

  test('exceptDepartments에 든 학과는 묶지 않는다', () {
    SusiResult r(int year, String track, String dept) => SusiResult(
      university: '가대',
      year: year,
      type: '미상',
      track: track,
      department: dept,
      quota: 20,
      cut50: 2.7,
      cut70: 3.0,
      metric: '50%컷',
    );
    final ps = AdmissionPredictionService().predict(
      results: AdmissionResults(
        source: '',
        susi: [r(2025, '학생부종합(옛전형)', '컴퓨터공학과'), r(2025, '학생부종합(옛전형)', '의예과')],
        regular: const [],
      ),
      catalog: AdmissionCatalog(
        year: 2028,
        source: '',
        status: '',
        tracks: [
          AdmissionTrack(
            university: '가대',
            department: '',
            type: '학생부종합',
            name: '새전형(면접형)',
            quota: '10명',
            eligibility: '',
            recommendation: '',
            recommender: '',
            selection: '',
            minimum: '없음',
            section: '서울',
          ),
        ],
      ),
      student: const StudentProfile(
        grade9Optimistic: 2.4,
        grade9Conservative: 2.6,
      ),
      interest: '',
      matches: (_, _) => true,
      aliases: const AdmissionAliases(
        tracks: [
          TrackAlias(
            university: '가대',
            fromYear: 2025,
            from: '학생부종합(옛전형)',
            toYear: 2028,
            to: '새전형(면접형)',
            apply: true,
            exceptDepartments: ['의예과'],
          ),
        ],
      ),
    );
    expect(ps.map((p) => p.department), ['컴퓨터공학과']);
    expect(ps.single.track, '새전형(면접형)');
  });

  test('block=true면 이름이 같아도 그 해 이전 입결을 잇지 않고 판단 보류로 돌린다', () {
    final s = AdmissionPredictionService();
    SusiResult r(int year) => SusiResult(
      university: '가대',
      year: year,
      type: '미상',
      track: '참인재전형',
      department: '컴퓨터공학과',
      quota: 20,
      cut50: 2.7,
      cut70: 3.0,
      metric: '50%컷',
    );
    final results = AdmissionResults(
      source: '',
      susi: [r(2024), r(2025)],
      regular: const [],
    );
    final catalog = AdmissionCatalog(
      year: 2028,
      source: '',
      status: '',
      tracks: [
        AdmissionTrack(
          university: '가대',
          department: '',
          type: '학생부교과',
          name: '참인재전형',
          quota: '10명',
          eligibility: '',
          recommendation: '',
          recommender: '',
          selection: '',
          minimum: '없음',
          section: '서울',
        ),
      ],
    );
    const aliases = AdmissionAliases(
      tracks: [
        TrackAlias(
          university: '가대',
          fromYear: 2025,
          from: '참인재전형',
          toYear: 2028,
          to: '참인재전형',
          apply: false,
          block: true,
          change: '학생부종합 → 학생부교과',
        ),
      ],
    );
    bool m(String t, String i) => true;
    const student = StudentProfile(
      grade9Optimistic: 2.4,
      grade9Conservative: 2.6,
    );
    expect(
      s.predict(
        results: results,
        catalog: catalog,
        student: student,
        interest: '',
        matches: m,
      ),
      hasLength(1),
    );
    final ps = s.predict(
      results: results,
      catalog: catalog,
      student: student,
      interest: '',
      matches: m,
      aliases: aliases,
    );
    expect(ps, isEmpty);
    final u = s.untrackedTracks(
      predictions: ps,
      results: results,
      catalog: catalog,
      interest: '',
      matches: m,
      aliases: aliases,
    );
    expect(u.single.track, '참인재전형');
    expect(u.single.note, '학생부종합 → 학생부교과');
  });
}
