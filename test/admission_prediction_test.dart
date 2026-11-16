import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

AdmissionTrack _track(String u, String name, String type) => AdmissionTrack(
  university: u,
  department: '',
  type: type,
  name: name,
  quota: '10명',
  eligibility: '',
  recommendation: '',
  recommender: '',
  selection: '',
  minimum: '없음',
  section: '서울',
);

SusiResult _s(
  int year, {
  String track = '학생부교과(지역균형전형)',
  String dept = '컴퓨터공학과',
  double? c50,
  double? c70,
  double? c90,
  num quota = 20,
}) => SusiResult(
  university: '가대',
  year: year,
  type: '미상',
  track: track,
  department: dept,
  quota: quota,
  cut50: c50,
  cut70: c70,
  cut90: c90,
  metric: c50 == null ? null : '50%컷',
);

RegularResult _r(
  int year, {
  double? pct,
  int? eng,
  double? conv70,
  double? conv50,
  double? total,
}) => RegularResult(
  university: '가대',
  year: year,
  group: '가군',
  department: '컴퓨터공학과',
  quota: 30,
  pctAvg70: pct,
  english70: eng,
  convert70: conv70,
  convert50: conv50,
  convertTotal: total,
);

final _catalog = AdmissionCatalog(
  year: 2028,
  source: '',
  status: '',
  tracks: [
    _track('가대', '지역균형전형', '학생부교과'),
    _track('가대', '학생부종합(탐구형)', '학생부종합'),
  ],
);

bool _matches(String text, String interest) => text.contains(interest);

List<AdmissionPrediction> _run(
  List<SusiResult> susi,
  StudentProfile student, {
  List<RegularResult> regular = const [],
  Map<String, ConversionFor> conversions = const {},
}) => AdmissionPredictionService().predict(
  results: AdmissionResults(source: '', susi: susi, regular: regular),
  catalog: _catalog,
  student: student,
  interest: '컴퓨터',
  matches: _matches,
  conversions: conversions,
);

const _grades = StudentProfile(grade9Optimistic: 2.4, grade9Conservative: 2.6);

void main() {
  group('수시 판정 (컨설팅 관행형)', () {
    PredictionLevel level(
      double c50,
      double c70, {
      StudentProfile s = _grades,
    }) => _run([
      _s(2024, c50: c50, c70: c70),
      _s(2025, c50: c50, c70: c70),
    ], s).single.level;

    test('보수값이 50%컷 이내면 안정, 70%컷 이내면 적정', () {
      expect(level(2.7, 3.0), PredictionLevel.safe);
      expect(level(2.5, 2.7), PredictionLevel.fit);
    });

    test('낙관값이 70%컷+0.3 이내면 상향(교과), 넘으면 어려움', () {
      expect(level(2.0, 2.2), PredictionLevel.reach); // 2.4 ≤ 2.5
      expect(level(1.8, 2.0), PredictionLevel.hard); // 2.4 > 2.3
    });

    test('2028 번들의 전형명으로 표시하고 두 해 평균 컷과 해별 근거를 보여준다', () {
      final p = _run([
        _s(2024, c50: 2.4, c70: 2.6),
        _s(2025, c50: 2.6, c70: 3.0),
      ], _grades).single;
      expect(p.track, '지역균형전형');
      expect(p.kind, PredictionKind.subject);
      expect(p.reason, contains('70%컷 평균 2.80'));
      expect(p.evidence, hasLength(2));
      expect(p.confidence, '높음');
    });

    test('종합전형은 상향 여유 0.5, 신뢰도는 최대 보통', () {
      final p = _run([
        _s(2024, track: '학생부종합(탐구형전형)', c50: 1.8, c70: 2.0),
        _s(2025, track: '학생부종합(탐구형전형)', c50: 1.8, c70: 2.0),
      ], _grades).single;
      expect(p.kind, PredictionKind.comprehensive);
      expect(p.level, PredictionLevel.reach); // 2.4 ≤ 2.5
      expect(p.confidence, '보통');
    });

    test('한 해 자료·소수 모집·역전은 신뢰도를 낮춘다', () {
      expect(
        _run([_s(2025, c50: 2.7, c70: 3.0)], _grades).single.confidence,
        '보통',
      );
      expect(
        _run([
          _s(2025, c50: 2.7, c70: 3.0, quota: 3),
          _s(2024, c50: 2.7, c70: 3.0),
        ], _grades).single.confidence,
        '낮음',
      );
      expect(
        _run([
          _s(2025, c50: 3.2, c70: 3.0),
          _s(2024, c50: 2.7, c70: 3.0),
        ], _grades).single.confidence,
        '낮음',
      );
    });

    test('90%컷만 있으면 상향 여부만 판단, 내신이 없으면 판단 보류', () {
      final loose = _run([_s(2025, c90: 2.9)], _grades).single;
      expect(loose.level, PredictionLevel.reach);
      expect(loose.confidence, '낮음');
      expect(
        _run([_s(2025, c50: 2, c70: 3)], const StudentProfile()).single.level,
        PredictionLevel.unknown,
      );
    });

    test('2028 번들에 없는 전형·특별전형·관심 분야 밖 학과는 제외한다', () {
      expect(
        _run([_s(2025, track: '없어진전형', c50: 2, c70: 3)], _grades),
        isEmpty,
      );
      expect(
        _run([_s(2025, track: '농어촌학생전형', c50: 2, c70: 3)], _grades),
        isEmpty,
      );
      expect(
        _run([_s(2025, dept: '국어국문학과', c50: 2, c70: 3)], _grades),
        isEmpty,
      );
    });
  });

  group('정시 판정', () {
    const mock = StudentProfile(mockPercentile: 85, mockEnglish: 2);

    PredictionLevel level(double pct, {int? eng, StudentProfile s = mock}) =>
        _run(
          const [],
          s,
          regular: [
            _r(2024, pct: pct, eng: eng),
            _r(2025, pct: pct, eng: eng),
          ],
        ).single.level;

    test('70%컷 평균 백분위 기준 +3 안정, 이상 적정, −3 상향, 그 밖 어려움', () {
      expect(level(81), PredictionLevel.safe);
      expect(level(84), PredictionLevel.fit);
      expect(level(87), PredictionLevel.reach);
      expect(level(89), PredictionLevel.hard);
    });

    test('영어 등급이 입결보다 2등급 이상 낮으면 한 단계 낮춘다', () {
      expect(
        level(
          81,
          eng: 1,
          s: const StudentProfile(mockPercentile: 85, mockEnglish: 3),
        ),
        PredictionLevel.fit,
      );
      expect(
        level(
          81,
          eng: 2,
          s: const StudentProfile(mockPercentile: 85, mockEnglish: 3),
        ),
        PredictionLevel.safe,
      );
    });

    test('같은 총점 척도의 환산 산식이 있으면 환산점수로 비교하고 산식 변경 가능성을 밝힌다', () {
      final session = MockExamSession([
        MockExamRecord(
          id: 'k',
          calendarYear: 2027,
          schoolYear: 3,
          examMonth: 6,
          subject: '국어',
          percentile: 80,
        ),
      ]);
      final p = _run(
        const [],
        StudentProfile(
          mockPercentile: 70,
          mockEnglish: 2,
          mockSession: session,
        ),
        regular: [_r(2025, pct: 90, conv70: 800, conv50: 820, total: 1000)],
        conversions: {
          '가대': (_) => {'자연계열 (1,000점)': 810, '인문계열 (1,000점)': 700},
        },
      ).single;
      expect(p.level, PredictionLevel.fit); // 810 ≥ 800, < 820 (백분위로는 어려움)
      expect(p.reason, contains('환산점수'));
      expect(p.reason, contains('산식 변경 가능'));
    });

    test('모의고사 백분위가 없으면 판단 보류', () {
      expect(level(80, s: const StudentProfile()), PredictionLevel.unknown);
    });
  });

  group('입결 변동폭·지표 차이', () {
    AdmissionPrediction susi(double c2024, double c2025, {String? m2024}) =>
        _run([
          SusiResult(
            university: '가대',
            year: 2024,
            type: '미상',
            track: '학생부교과(지역균형전형)',
            department: '컴퓨터공학과',
            quota: 20,
            cut50: c2024 - 0.2,
            cut70: c2024,
            metric: m2024 ?? '50%컷',
          ),
          _s(2025, c50: c2025 - 0.2, c70: c2025),
        ], _grades).single;

    test('수시 70%컷이 0.5등급 이상 움직이면 한 단계, 1.0 이상이면 낮음', () {
      expect(susi(3.0, 3.3).confidence, '높음');
      final mid = susi(3.0, 3.6);
      expect(mid.confidence, '보통');
      expect(mid.reason, contains('2024→2025 70%컷 0.60등급 변동'));
      expect(susi(3.0, 4.2).confidence, '낮음');
    });

    test('해마다 공개 지표(평균·50%컷)가 다르면 밝히고 한 단계 낮춘다', () {
      final p = susi(3.0, 3.1, m2024: '평균');
      expect(p.confidence, '보통');
      expect(p.reason, contains('해마다 공개 지표가 다름'));
    });

    const app = AdmissionPredictionService.appPercentileMethod;
    RegularResult reg(int year, double pct, String method) => RegularResult(
      university: '가대',
      year: year,
      group: '가군',
      department: '컴퓨터공학과',
      quota: 30,
      pctAvg70: pct,
      pctAvgMethod: method,
    );
    const mock = StudentProfile(mockPercentile: 85, mockEnglish: 2);

    test('정시는 학생과 같은 공식(앱 계산) 해만 비교하고, 대학 공개 평균 해는 뺀다', () {
      final p = _run(
        const [],
        mock,
        regular: [reg(2024, 60, '대학 공개 70% cut 평균 백분위'), reg(2025, 84, app)],
      ).single;
      expect(p.level, PredictionLevel.fit); // 84만 비교(60과 평균내면 72 → 안정)
      expect(p.reason, contains('70%컷 평균 백분위 84.0'));
      expect(p.reason, contains('대학 공개 평균 백분위인 해는'));
      expect(p.confidence, '보통'); // 비교한 해가 하나
      expect(p.evidence.last, contains('(대학 공개)'));
      expect(p.evidence.first, contains('(국·수·탐 앱 계산)'));
    });

    test('대학 공개 평균만 있으면 한계를 밝히고 신뢰도를 낮춘다', () {
      final p = _run(
        const [],
        mock,
        regular: [
          reg(2024, 84, '대학 공개 70% cut 평균 백분위'),
          reg(2025, 84, '대학 공개 70% cut 평균 백분위'),
        ],
      ).single;
      expect(p.confidence, '보통');
      expect(p.reason, contains('반영 영역이 앱 계산(국·수·탐)과 다를 수 있음'));
    });

    test('같은 방식 백분위가 5점 이상이면 한 단계, 10점 이상이면 낮음', () {
      String conf(double a, double b) => _run(
        const [],
        mock,
        regular: [reg(2024, a, app), reg(2025, b, app)],
      ).single.confidence;
      expect(conf(82, 84), '높음');
      expect(conf(78, 84), '보통');
      expect(conf(72, 84), '낮음');
    });
  });

  group('같은 이름 전형 잇기 점검', () {
    SusiResult typed(int year, String type, String track) => SusiResult(
      university: '가대',
      year: year,
      type: type,
      track: track,
      department: '컴퓨터공학과',
      quota: 20,
      cut50: 2.7,
      cut70: 3.0,
      metric: '50%컷',
    );

    test('입결 유형이 2028 전형 유형과 다르면(종합→교과) 이름이 같아도 잇지 않는다', () {
      // 2028 '지역균형전형'은 학생부교과다.
      expect(_run([typed(2025, '학생부종합', '학생부종합(지역균형전형)')], _grades), isEmpty);
      // 유형이 같거나 '미상'이면 지금처럼 잇는다.
      expect(
        _run([typed(2025, '학생부교과', '학생부교과(지역균형전형)')], _grades),
        hasLength(1),
      );
      expect(_run([typed(2025, '미상', '지역균형전형')], _grades), hasLength(1));
    });

    test('사회기여자·배려자·정원 외·고운사회 전형은 일반 예측에서 뺀다', () {
      final s = AdmissionPredictionService();
      for (final name in [
        '사회기여자전형',
        '사회기여 및 배려자전형',
        '항공시스템공학특별전형 (정원 외)',
        '고운사회전형',
        '어울림전형',
        '사회공헌통합전형',
        '밝은사회전형',
        '재림교회목회자추천전형',
        '기독교지도자전형',
        '군사학과전형',
      ]) {
        final ps = s.predict(
          results: AdmissionResults(
            source: '',
            susi: [typed(2025, '미상', name)],
            regular: const [],
          ),
          catalog: AdmissionCatalog(
            year: 2028,
            source: '',
            status: '',
            tracks: [_track('가대', name, '학생부교과')],
          ),
          student: _grades,
          interest: '컴퓨터',
          matches: _matches,
        );
        expect(ps, isEmpty, reason: name);
      }
    });
  });

  group('학과명 변경 묶기', () {
    test('학부→학과·가운뎃점·(주) 표기 차이는 같은 모집단위로 묶고 최근 이름·당시 이름을 밝힌다', () {
      final p = _run([
        _s(2024, dept: '컴퓨터공학부', c50: 2.7, c70: 3.0),
        _s(2025, dept: '컴퓨터공학과', c50: 2.7, c70: 3.0),
      ], _grades).single;
      expect(p.department, '컴퓨터공학과');
      expect(p.confidence, '높음'); // 두 해 자료로 인정
      expect(p.evidence.last, contains('당시 컴퓨터공학부'));
      expect(p.evidence.first, isNot(contains('당시')));
      expect(p.reason, contains('학과명 변경(컴퓨터공학부 → 컴퓨터공학과)'));

      final s = AdmissionPredictionService();
      expect(s.departmentKey('정치ㆍ국제학과'), s.departmentKey('정치국제학과'));
      expect(s.departmentKey('컴퓨터공학과(주)'), s.departmentKey('컴퓨터공학과'));
      expect(s.departmentKey('인공지능전공'), s.departmentKey('인공지능학과'));
    });

    test('전형명의 [수시] 접두어·끝 주석은 무시하고, 번호·명칭이 다른 전형은 묶지 않는다', () {
      final s = AdmissionPredictionService();
      expect(
        s.trackKey('[수시]학생부종합(소프트웨어우수인재전형)'),
        s.trackKey('학생부종합(소프트웨어우수인재전형)'),
      );
      expect(
        s.trackKey('학생부종합(첨단융합인재전형)*일부 학과의 경우 2024학년도 첨단융합인재전형에서 선발'),
        s.trackKey('학생부종합(첨단융합인재전형)'),
      );
      expect(
        s.trackKey('[수시]학생부종합(광운참빛인재전형-면접형)'),
        isNot(s.trackKey('학생부종합(광운참빛인재전형Ⅰ-면접형)')),
      );
      expect(s.trackKey('수시지역균형전형'), s.trackKey('지역균형전형'));
      expect(s.trackKey('수시일반전형'), s.trackKey('일반전형'));
      // 단국대처럼 유형과 전형명 사이에 줄표가 있어도 같은 키.
      expect(s.trackKey('학생부종합전형-dku인재(서류형)'), s.trackKey('DKU인재(서류형)전형'));
      expect(s.trackKey('학생부교과전형–지역균형선발'), s.trackKey('지역균형선발전형'));
      // "학생부교과우수자"는 "학생부 + 교과우수자"다(유형 이름 + "우수자"가 아니다).
      expect(s.trackKey('학생부교과우수자전형'), s.trackKey('교과우수자전형'));
      expect(s.trackKey('학생부면접우수자전형'), s.trackKey('면접우수자전형'));
      expect(s.trackKey('학생부교과우수자전형'), isNot(s.trackKey('학생부우수자전형')));
      expect(s.trackKey('학생부교과(지역균형)'), s.trackKey('지역균형전형'));
    });

    test('괄호 안 전공이 다르면 묶지 않는다', () {
      final s = AdmissionPredictionService();
      expect(
        s.departmentKey('디자인학과(시각디자인전공)'),
        isNot(s.departmentKey('디자인학과(산업디자인전공)')),
      );
    });

    test('한 해 안에 같은 키의 학과가 둘이면 묶지 않고 나눈다', () {
      final ps = _run([
        _s(2025, dept: '컴퓨터공학과', c50: 2.7, c70: 3.0),
        _s(2025, dept: '컴퓨터공학부', c50: 2.0, c70: 2.2),
        _s(2024, dept: '컴퓨터공학과', c50: 2.7, c70: 3.0),
      ], _grades);
      expect(ps.map((p) => p.department).toSet(), {'컴퓨터공학과', '컴퓨터공학부'});
      expect(ps.every((p) => !p.reason.contains('학과명 변경')), isTrue);
    });

    test('정시도 같은 군에서 학과명 변경을 묶는다', () {
      RegularResult r(int year, String dept) => RegularResult(
        university: '가대',
        year: year,
        group: '가군',
        department: dept,
        quota: 30,
        pctAvg70: 84,
      );
      final p = _run(
        const [],
        const StudentProfile(mockPercentile: 85, mockEnglish: 2),
        regular: [r(2024, '컴퓨터공학전공'), r(2025, '컴퓨터공학과')],
      ).single;
      expect(p.department, '컴퓨터공학과');
      expect(p.evidence.last, contains('당시 컴퓨터공학전공'));
      expect(p.reason, contains('학과명 변경'));
    });
  });

  group('학생 지표', () {
    GradeRecord g(int rank, double credit, String kind) => GradeRecord(
      id: '$rank$credit$kind',
      userId: 'u',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      schoolYear: 1,
      semester: 1,
      subjectName: '과목$rank$credit',
      credit: credit,
      gradeRank: rank,
      examKind: kind,
    );
    final bridge = {
      'bridge': {'nineGradeByRankSum': List.generate(25, (i) => 1.0 + i / 3)},
    };

    test('학기 종합을 우선 쓰고 학점가중 평균을 9등급 대응 구간으로 바꾼다', () {
      final p = AdmissionPredictionService().profile(
        confirmedGrades: [
          g(1, 4, 'semesterSummary'),
          g(3, 2, 'semesterSummary'),
          g(5, 3, 'midterm'),
        ],
        comparisonData: bridge,
      );
      // (1·4 + 3·2) / 6 = 1.667 → 정확히 노드 4(1 + 4/3) → 낙관·보수 모두 2.333
      expect(p.gradeAverage5, closeTo(1.6667, 1e-3));
      expect(p.grade9Optimistic, closeTo(1 + 4 / 3, 1e-9));
      expect(p.grade9Conservative, closeTo(1 + 4 / 3, 1e-9));
      expect(p.gradeBasis, contains('학기 종합'));
    });

    test('학기 종합이 없으면 기말, 그다음 중간고사를 쓰고 근거에 밝힌다', () {
      final p = AdmissionPredictionService().profile(
        confirmedGrades: [g(2, 3, 'midterm')],
        comparisonData: bridge,
      );
      expect(p.gradeBasis, contains('중간고사'));
      expect(p.hasGrades, isTrue);
    });
  });
}
