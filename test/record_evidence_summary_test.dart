import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/record_evidence_summary.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';

// 가상 생기부 근거만 쓴다.
SchoolRecordEvidence _r(
  String id,
  int year,
  String category,
  String evidence, {
  String? memo,
  bool enabled = true,
}) => SchoolRecordEvidence(
  id: id,
  calendarYear: 2024 + year,
  schoolYear: year,
  category: category,
  evidence: evidence,
  sourceLocation: '$year쪽',
  confirmedAt: DateTime.utc(2026),
  careerInterest: memo,
  careerEvidenceEnabled: enabled,
);

final _matches = UniversityRecommendationService().matches;

void main() {
  test('진로 메모 또는 원문 단어로 연결하고 학년·영역별로 센다', () {
    final s = RecordEvidenceSummary.build(
      [
        _r('a', 2, '세특', '정보 시간에 정렬 알고리즘을 구현함.', memo: '컴퓨터공학'),
        _r('b', 1, '동아리', '컴퓨터 동아리에서 웹 페이지를 만듦.'),
        _r('c', 1, '세특', '문학 작품을 비평함.'),
        _r('d', 2, '진로', '컴퓨터 관련 진로 탐색.', enabled: false),
      ],
      '컴퓨터',
      _matches,
    );
    expect(s.usable, 3);
    expect(s.matched.map((r) => r.id), ['b', 'a']); // 학년순
    expect(s.byMemo, 1);
    expect(s.byText, 1);
    expect(s.byYear, {1: 1, 2: 1});
    expect(s.byCategory, {'동아리': 1, '세특': 1});
    expect(s.describe(), contains('연결된 생기부 근거 2건'));
    expect(s.describe(), contains('1학년 1·2학년 1'));
  });

  test('근거가 없거나 연결된 근거가 없으면 다음 행동을 안내한다', () {
    expect(
      RecordEvidenceSummary.build(const [], '경영', _matches).describe(),
      contains('등록·확인하세요'),
    );
    final none = RecordEvidenceSummary.build(
      [_r('c', 1, '세특', '문학 작품을 비평함.', memo: '국어국문')],
      '경영',
      _matches,
    );
    expect(none.matched, isEmpty);
    expect(none.describe(), contains('연결된 근거가 없습니다'));
  });
}
