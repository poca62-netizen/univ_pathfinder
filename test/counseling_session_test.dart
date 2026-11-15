import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/models/example_university.dart';

void main() {
  test('대학 선택은 10개로 제한하고 해제 후 교체할 수 있다', () {
    final session = CounselingSession();
    for (final university in exampleUniversities.take(10)) {
      expect(session.toggle(university), isTrue);
    }
    expect(session.toggle(exampleUniversities[10]), isFalse);
    expect(session.selected.length, 10);
    session.toggle(exampleUniversities.first);
    expect(session.toggle(exampleUniversities[10]), isTrue);
    expect(session.selected.length, 10);
  });

  test('연도·시험 종류·학기와 시행 월로 자료를 구별하고 동일 등록을 막는다', () {
    final session = CounselingSession();
    const mid = StudentDocument(
      kind: StudentDocumentKind.midterm,
      schoolYear: 1,
      calendarYear: 2026,
      semester: 1,
      fileName: 'sample.pdf',
    );
    const end = StudentDocument(
      kind: StudentDocumentKind.finalExam,
      schoolYear: 1,
      calendarYear: 2026,
      semester: 1,
      fileName: 'sample.pdf',
    );
    expect(session.addDocument(mid), isTrue);
    expect(session.addDocument(mid), isFalse);
    expect(session.addDocument(end), isTrue);
    expect(
      () => session.addDocument(
        const StudentDocument(
          kind: StudentDocumentKind.mockExam,
          schoolYear: 2,
          calendarYear: 2026,
          examMonth: 13,
          fileName: 'sample.pdf',
        ),
      ),
      throwsArgumentError,
    );
    expect(session.documents.length, 2);
  });

  test('생활기록부는 학기 없이, 모의고사는 시행 월로 기록한다', () {
    const record = StudentDocument(
      kind: StudentDocumentKind.schoolRecord,
      schoolYear: 3,
      calendarYear: 2026,
      fileName: 'record.pdf',
    );
    const mock = StudentDocument(
      kind: StudentDocumentKind.mockExam,
      schoolYear: 3,
      calendarYear: 2026,
      examMonth: 9,
      fileName: 'mock.pdf',
    );
    expect(record.isValid, isTrue);
    expect(mock.isValid, isTrue);
    expect(mock.period, contains('9월'));
  });

  test('직선거리는 같은 지점 0, 적도 경도 1도 약 111.2km이다', () {
    final origin = GeoPoint(0, 0);
    expect(origin.distanceKmTo(GeoPoint(0, 0)), closeTo(0, 0.00001));
    expect(origin.distanceKmTo(GeoPoint(0, 1)), closeTo(111.195, 0.01));
    expect(origin.distanceKmTo(GeoPoint(0, 180)), closeTo(20015.114, 0.01));
  });

  test('비유한 값·범위 밖 좌표 차단과 출발지 초기화', () {
    expect(() => GeoPoint(double.nan, 127), throwsArgumentError);
    expect(() => GeoPoint(37, double.infinity), throwsArgumentError);
    expect(() => GeoPoint(91, 0), throwsArgumentError);
    final session = CounselingSession();
    session.setOrigin(GeoPoint(37, 127));
    session.toggle(exampleUniversities.first);
    session.clear();
    expect(session.origin, isNull);
    expect(session.selected, isEmpty);
  });
}
