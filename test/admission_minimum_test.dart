import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

// 가상 대학·가상 학생만 쓴다.
AdmissionTrack _track(String name, String minimum, {String dept = ''}) =>
    AdmissionTrack(
      university: '가대',
      department: dept,
      type: '학생부교과',
      name: name,
      quota: '10명',
      eligibility: '',
      recommendation: '',
      recommender: '',
      selection: '',
      minimum: minimum,
      section: '서울',
    );

SusiResult _s(String dept, {String track = '학생부교과(지역균형전형)'}) => SusiResult(
  university: '가대',
  year: 2025,
  type: '미상',
  track: track,
  department: dept,
  quota: 20,
  cut50: 2.5,
  cut70: 2.8,
  metric: '50%컷',
);

MockExamSession _mock(List<int> grades) => MockExamSession([
  for (var i = 0; i < grades.length; i++)
    MockExamRecord(
      id: '$i',
      calendarYear: 2026,
      schoolYear: 2,
      examMonth: 9,
      subject: ['국어', '수학', '영어', '통합사회', '통합과학', '한국사'][i],
      institution: '교육청',
      gradeRank: grades[i],
    ),
]);

const _sum = '국,수,영,통사/통과(상위 1과목) 중 2개 합 5 이내';
const _student = StudentProfile(grade9Optimistic: 2.4, grade9Conservative: 2.6);
final _service = AdmissionPredictionService();

AdmissionPrediction _predict(List<AdmissionTrack> tracks, String dept) =>
    _service
        .predict(
          results: AdmissionResults(
            source: '',
            susi: [_s(dept)],
            regular: const [],
          ),
          catalog: AdmissionCatalog(
            year: 2028,
            source: '',
            status: '',
            tracks: tracks,
          ),
          student: _student,
          interest: '',
          matches: (_, _) => true,
          conversions: const {},
        )
        .single;

void main() {
  test('수시 예측에 2028 전형 최저 원문을 붙이고 같은 모의고사로 판정한다', () {
    final p = _predict([_track('지역균형전형', _sum)], '컴퓨터공학과');
    expect(p.minimum, _sum);
    expect(
      _service.checkMinimum(p, _mock([2, 3, 4, 4, 4, 3])).result.status,
      MinimumStatus.met,
    );
    final below = _service.checkMinimum(p, _mock([3, 3, 4, 4, 4, 3])).result;
    expect(below.status, MinimumStatus.below);
    expect(
      _service.checkMinimum(p, null).result.status,
      MinimumStatus.insufficient,
    );
  });

  test('모집단위별 행(의약계열)이 있으면 그 행의 최저를 쓴다', () {
    final p = _predict([
      _track('지역균형전형', '인문/자연: $_sum\n의예과: 국,수,영,통과 중 3개 합 4 이내'),
      _track('지역균형전형', '국,수,영,통과 중 3개 합 4 이내', dept: '의예과'),
    ], '의예과');
    expect(p.minimum, '국,수,영,통과 중 3개 합 4 이내');
  });

  test('계열별로 나뉜 기준은 학과명 앞부분 → 고른 계열 → 그 외 순으로 한 기준만 정해질 때 적용', () {
    const split = '인문/자연: $_sum\n의예/약학: 국,수,영,통과 중 3개 합 4 이내';
    final track = [_track('지역균형전형', split)];
    final mock = _mock([2, 3, 2, 2, 2, 3]);

    final pharm = _service.checkMinimum(_predict(track, '약학과'), mock);
    expect(pharm.branch, '의예/약학');
    expect(pharm.result.status, MinimumStatus.below); // 2+2+2=6 > 4

    final cs = _predict(track, '컴퓨터공학과');
    final unknown = _service.checkMinimum(cs, mock);
    expect(unknown.result.status, MinimumStatus.manual);
    expect(unknown.result.reason, contains('계열을 선택'));
    final science = _service.checkMinimum(cs, mock, field: '자연');
    expect(science.branch, '인문/자연');
    expect(science.result.status, MinimumStatus.met);

    const other = '간호학과: 국,수,영,통과 중 3개 합 6 이내\n그 외: $_sum';
    final rest = _service.checkMinimum(
      _predict([_track('지역균형전형', other)], '컴퓨터공학과'),
      mock,
    );
    expect(rest.branch, '그 외');
    expect(rest.result.status, MinimumStatus.met);
  });

  test('최저 없음·원문 없음·해석 불가를 구분한다', () {
    expect(
      _service
          .checkMinimum(_predict([_track('지역균형전형', '없음')], '경영학과'), null)
          .result
          .status,
      MinimumStatus.none,
    );
    expect(
      _service
          .checkMinimum(_predict([_track('지역균형전형', '')], '경영학과'), null)
          .result
          .status,
      MinimumStatus.manual,
    );
    expect(
      _service
          .checkMinimum(
            _predict([
              _track('지역균형전형', '국,수 중 1개 3등급 이내(제2외국어 대체 가능)'),
            ], '경영학과'),
            _mock([1, 1, 1, 1, 1, 1]),
          )
          .result
          .status,
      MinimumStatus.manual,
    );
  });
}
