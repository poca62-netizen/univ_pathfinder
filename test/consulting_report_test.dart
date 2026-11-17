import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/reference_results.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';
import 'package:univ_pathfinder/screens/consulting_report_screen.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';

// 가상 학생·가상 대학만 쓴다.
AdmissionTrack _track(String name, String type, {String minimum = '없음'}) =>
    AdmissionTrack(
      university: '가상대',
      department: '',
      type: type,
      name: name,
      quota: '10명',
      eligibility: '',
      recommendation: '',
      recommender: '',
      selection: '',
      minimum: minimum,
      section: '서울',
    );

// 2026년 고2 9월 가상 모의고사, 전 영역 3등급.
final _mock = [
  for (final (i, subject) in ['국어', '수학', '영어', '통합사회', '통합과학', '한국사'].indexed)
    MockExamRecord(
      id: 'm$i',
      calendarYear: 2026,
      schoolYear: 2,
      examMonth: 9,
      subject: subject,
      institution: '교육청',
      gradeRank: 3,
    ),
];

SusiResult _susi(int year, String track, double c50, double c70) => SusiResult(
  university: '가상대',
  year: year,
  type: '미상',
  track: track,
  department: '컴퓨터공학과',
  quota: 20,
  cut50: c50,
  cut70: c70,
  metric: '50%컷',
);

CounselingSummary _summary({
  bool confirmed = true,
  bool mock = false,
  List<SchoolRecordEvidence> records = const [],
}) => CounselingSummary(
  grades: SummarySection([
    GradeRecord(
      id: 'g',
      userId: 'fake',
      schoolYear: 2,
      semester: 1,
      subjectName: '수학',
      credit: 4,
      gradeRank: 2,
      calendarYear: 2026,
      examKind: 'semesterSummary',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      sourceConfirmedAt: confirmed ? DateTime.utc(2026) : null,
    ),
  ]),
  mockExams: SummarySection(mock ? _mock : const <MockExamRecord>[]),
  activities: SummarySection(records),
);

Widget _app({
  bool confirmed = true,
  bool mock = false,
  List<SchoolRecordEvidence> records = const [],
  List<AdmissionTrack> extraTracks = const [],
  ReferenceResults reference = const ReferenceResults(sources: [], rows: []),
}) => MaterialApp(
  home: ConsultingReportScreen(
    loadAliases: () async => const AdmissionAliases(),
    loadReference: () async => reference,
    loadSummary: () async =>
        _summary(confirmed: confirmed, mock: mock, records: records),
    loadResults: () async => AdmissionResults(
      source: '',
      susi: [
        // 5등급 2.0 → 9등급 3.0 (가상 대응표). 교과 70%컷 3.5 → 안정, 종합 70%컷 2.6 → 상향.
        _susi(2024, '학생부교과(지역균형전형)', 3.2, 3.5),
        _susi(2025, '학생부교과(지역균형전형)', 3.2, 3.5),
        _susi(2025, '학생부종합(탐구형전형)', 2.4, 2.6),
      ],
      regular: const [],
    ),
    loadCatalog: () async => AdmissionCatalog(
      year: 2028,
      source: '',
      status: '',
      tracks: [
        _track('지역균형전형', '학생부교과', minimum: '국,수,영,통사/통과(상위 1과목) 중 2개 합 4 이내'),
        _track(
          '학생부종합(탐구형)',
          '학생부종합',
          minimum: '인문: 국,수,영,통사 중 2개 합 7 이내\n자연: 국,수,영,통과 중 2개 합 5 이내',
        ),
        ...extraTracks,
      ],
    ),
    loadComparison: () async => {
      'bridge': {'nineGradeByRankSum': List.generate(25, (i) => 1.0 + i / 3)},
    },
    loadTuition: () async => const TuitionCatalog(
      source: '',
      sourceUrl: '',
      note: '',
      rows: [
        TuitionRecord(
          university: '가상대',
          officialName: '가상대학교',
          campus: '본교',
          region: '서울',
          year: 2026,
          asOf: '2026-04',
          annualWon: 8000000,
          scope: '평균',
        ),
      ],
    ),
  ),
);

Future<void> _runReport(WidgetTester tester, String interest) async {
  await tester.enterText(find.byKey(const Key('report-interest')), interest);
  await tester.tap(find.byKey(const Key('report-run')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('관심 분야로 전형별 안정·상향 리포트와 근거·등록금을 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');

    expect(find.byKey(const Key('report-kind-subject')), findsOneWidget);
    expect(find.byKey(const Key('report-kind-comprehensive')), findsOneWidget);
    expect(find.byKey(const Key('report-subject-safe')), findsOneWidget);
    expect(find.byKey(const Key('report-comprehensive-reach')), findsOneWidget);
    expect(find.textContaining('합격을 보장하지 않습니다'), findsOneWidget);
    expect(find.textContaining('학기 종합'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-subject-safe')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('가상대 · 컴퓨터공학과').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('800만원'), findsOneWidget);
    expect(find.textContaining('2024학년도'), findsWidgets);
  });

  testWidgets('관심 분야가 없으면 안내하고, 확인된 내신이 없으면 판단 보류', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(confirmed: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-run')));
    await tester.pump();
    expect(find.text('관심 학과·분야를 입력하세요.'), findsOneWidget);

    await _runReport(tester, '컴퓨터');
    expect(find.textContaining('수시는 판단 보류'), findsOneWidget);
    expect(find.byKey(const Key('report-subject-unknown')), findsOneWidget);
  });

  testWidgets('같은 모의고사로 수능 최저를 판정하고, 계열별 기준은 고른 계열로만 적용한다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(mock: true));
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');

    // 교과: 3+3=6 > 4 → 미달 수준(학업 비교는 안정이어도 경고).
    expect(
      tester.widget<Text>(find.byKey(const Key('report-minimum-subject'))).data,
      contains('미달 수준 1'),
    );
    // 종합: 인문·자연으로 나뉘어 계열을 고르기 전에는 원문 확인 필요.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('report-minimum-comprehensive')))
          .data,
      contains('원문 확인 필요 1'),
    );
    await tester.tap(find.byKey(const Key('report-subject-safe')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('· 최저 미달 수준'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-field-자연')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('report-minimum-comprehensive')))
          .data,
      contains('미달 수준 1'), // 자연: 3+3=6 > 5
    );
    await tester.tap(find.byKey(const Key('report-field-인문')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('report-minimum-comprehensive')))
          .data,
      contains('충족 수준 1'), // 인문: 3+3=6 ≤ 7
    );

    await tester.tap(find.byKey(const Key('report-comprehensive-reach')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('가상대 · 컴퓨터공학과').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('고른 계열로 적용'), findsOneWidget);
  });

  testWidgets('지원 조합 예시: 같은 대학은 한 번, 빈 자리와 최저 미달 제외를 밝힌다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');

    final card = find.byKey(const Key('report-portfolio'));
    expect(card, findsOneWidget);
    String text() => tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .join('\n');
    // 교과 안정과 종합 상향이 같은 가상대라 안정 한 장만 들어간다.
    expect(text(), contains('지역균형전형 · 신뢰도'));
    expect(text(), isNot(contains('학생부종합(탐구형) · 신뢰도')));
    expect(text(), contains('수시 상향 2자리를 채울 후보가 없습니다'));

    await tester.tap(find.byKey(const Key('report-split-cautious')));
    await tester.pumpAndSettle();
    expect(text(), contains('수시 안정 2자리'));
  });

  testWidgets('지원 조합 예시: 최저 미달 수준이면 빼고 같은 대학의 다른 전형이 자리를 쓴다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(mock: true));
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');
    final card = find.byKey(const Key('report-portfolio'));
    final text = tester
        .widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .join('\n');
    expect(text, contains('최저가 미달 수준인 수시 1건'));
    expect(text, contains('학생부종합(탐구형) · 신뢰도'));
    expect(text, contains('최저를 원문에서 확인해야 합니다'));
  });

  testWidgets('맞는 모집단위가 없으면 다른 표현을 권한다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _runReport(tester, '해양');
    expect(find.textContaining('다른 표현'), findsOneWidget);
  });

  testWidgets('생기부 근거: 관심 분야와 연결된 건수·위치를 보여 주고 학종은 점수화하지 않는다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        records: [
          SchoolRecordEvidence(
            id: 'e1',
            calendarYear: 2026,
            schoolYear: 2,
            category: '세특',
            evidence: '정보 시간에 컴퓨터 정렬 알고리즘을 구현함.',
            sourceLocation: '5쪽',
            confirmedAt: DateTime.utc(2026),
          ),
          SchoolRecordEvidence(
            id: 'e2',
            calendarYear: 2025,
            schoolYear: 1,
            category: '동아리',
            evidence: '문학 동아리 활동.',
            sourceLocation: '3쪽',
            confirmedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');

    final line = tester.widget<Text>(find.byKey(const Key('report-records')));
    expect(line.data, contains('연결된 생기부 근거 1건'));
    expect(line.data, contains('2학년 1'));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('report-comprehensive-records')))
          .data,
      allOf(contains('점수로 바꾸지 않습니다'), contains('1건')),
    );
    await tester.tap(find.byKey(const Key('report-records-list')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2학년 · 세특 · 5쪽'), findsOneWidget);
    expect(find.textContaining('문학 동아리'), findsNothing);
  });

  testWidgets('생기부 근거가 없으면 등록·확인을 안내한다', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');
    expect(
      tester.widget<Text>(find.byKey(const Key('report-records'))).data,
      contains('등록·확인하세요'),
    );
    expect(find.byKey(const Key('report-records-list')), findsNothing);
  });

  testWidgets('리포트 복사: 판정·조합·근거를 담고 생기부 원문은 넣지 않으며, 실패하면 다시 시도', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          if (fail) throw PlatformException(code: 'denied');
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        records: [
          SchoolRecordEvidence(
            id: 'e1',
            calendarYear: 2026,
            schoolYear: 2,
            category: '세특',
            evidence: '가상학생이 컴퓨터 정렬 알고리즘을 구현함.',
            sourceLocation: '5쪽',
            confirmedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-copy')), findsNothing);
    await _runReport(tester, '컴퓨터');

    await tester.tap(find.byKey(const Key('report-copy')));
    await tester.pumpAndSettle();
    expect(find.text('복사하지 못했습니다.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, contains('관심 분야: 컴퓨터'));
    expect(copied, contains('합격을 보장하지 않습니다'));
    expect(copied, contains('[지원 조합 예시 · 수시 균형]'));
    expect(copied, contains('[학생부교과 1건] 안정 1'));
    expect(copied, contains('〈안정〉'));
    expect(copied, contains('2024학년도'));
    expect(copied, contains('연결된 생기부 근거 1건'));
    expect(copied, isNot(contains('정렬 알고리즘')));
  });

  testWidgets('인쇄: 인쇄용 문서를 넘기고, 창이 막히면 팝업 해제·복사를 안내', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? printed;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ConsultingReportScreen(
          loadAliases: () async => const AdmissionAliases(),
          loadReference: () async =>
              const ReferenceResults(sources: [], rows: []),
          loadSummary: () async => _summary(),
          loadResults: () async => AdmissionResults(
            source: '',
            susi: [
              _susi(2024, '학생부교과(지역균형전형)', 3.2, 3.5),
              _susi(2025, '학생부교과(지역균형전형)', 3.2, 3.5),
            ],
            regular: const [],
          ),
          loadCatalog: () async => AdmissionCatalog(
            year: 2028,
            source: '',
            status: '',
            tracks: [_track('지역균형전형', '학생부교과')],
          ),
          loadComparison: () async => {
            'bridge': {
              'nineGradeByRankSum': List.generate(25, (i) => 1.0 + i / 3),
            },
          },
          loadTuition: () async => const TuitionCatalog(
            source: '',
            sourceUrl: '',
            note: '',
            rows: [],
          ),
          printHtml: (html) {
            printed = html;
            return opened;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-print')), findsNothing);
    await _runReport(tester, '컴퓨터');
    await tester.tap(find.byKey(const Key('report-print')));
    await tester.pumpAndSettle();
    expect(printed, contains('<!doctype html>'));
    expect(printed, contains('<h3>〈안정〉</h3>'));
    expect(find.textContaining('팝업 차단을 해제'), findsOneWidget);
  });

  testWidgets('과거 입결과 이어지지 않는 2028 전형은 판단 보류로 따로 보여 주고 복사에도 넣는다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      _app(
        extraTracks: [
          _track('학업형전형', '학생부종합'),
          _track('농어촌학생전형', '학생부종합'), // 특별전형은 기본 제외
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');
    final tile = find.byKey(const Key('report-untracked'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('과거 입결과 비교하지 못한 2028 전형 (1)'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('가상대: 학업형전형(종합)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('[과거 입결과 비교하지 못한 2028 전형 1건] 판단 보류'));
    expect(copied, contains('- 가상대: 학업형전형(종합)'));
  });

  testWidgets('판단 보류 전형에 대학 공개 입결을 참고로만 붙이고(관심 분야 학과만) 복사에도 넣는다', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    ReferenceResultRow row(String dept, double v) => ReferenceResultRow(
      source: 's1',
      university: '가상대',
      year: 2025,
      sourceTrack: '학업형 전형',
      tracks: const ['학업형전형'],
      department: dept,
      value: v,
      metric: '합격자 평균(최초+충원)',
    );
    await tester.pumpWidget(
      _app(
        extraTracks: [_track('학업형전형', '학생부종합')],
        reference: ReferenceResults(
          sources: const [
            ReferenceSource(
              id: 's1',
              university: '가상대',
              year: 2025,
              title: '가상대 2025 수시 결과',
              url: 'https://example.invalid',
              metric: '합격자 평균(최초+충원)',
              mirror: '재게시본',
            ),
          ],
          rows: [row('컴퓨터공학과', 2.41), row('국어국문학과', 2.10)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _runReport(tester, '컴퓨터');
    final tile = find.byKey(const Key('report-untracked'));
    await tester.scrollUntilVisible(
      tile,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-reference-note')), findsOneWidget);
    final line = find.textContaining('참고(예측에 쓰지 않음) · 2025 학업형 전형');
    expect(line, findsOneWidget);
    final text = tester.widget<Text>(line).data!;
    expect(text, contains('컴퓨터공학과 2.41'));
    expect(text, isNot(contains('국어국문학과'))); // 관심 분야 밖 학과는 빼기
    expect(text, contains('합격자 평균(최초+충원)'));
    // 예측(안정·적정 등) 목록에는 들어가지 않는다.
    expect(find.text('과거 입결과 비교하지 못한 2028 전형 (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('대학 공개 입결(참고)'));
    expect(copied, contains('가상대 학업형전형 → 참고(예측에 쓰지 않음)'));
  });
}
