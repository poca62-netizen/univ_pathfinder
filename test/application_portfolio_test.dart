import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/services/application_portfolio_service.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

// 가상 대학(가대·나대…)과 가상 예측만 쓴다.
AdmissionPrediction _p(
  String u,
  PredictionLevel level, {
  PredictionKind kind = PredictionKind.subject,
  String confidence = '보통',
  String? group,
  String dept = '컴퓨터공학과',
}) => AdmissionPrediction(
  university: u,
  kind: kind,
  track: '교과전형',
  department: dept,
  level: level,
  confidence: confidence,
  reason: '',
  evidence: const [],
  group: group,
);

MinimumCheck _m(MinimumStatus s) => MinimumCheck(MinimumResult(s, ''));

ApplicationPortfolio _build(
  List<AdmissionPrediction> ps, {
  Map<AdmissionPrediction, MinimumCheck> minimums = const {},
  SusiSplit split = SusiSplit.balanced,
  List<String> priority = const [],
}) => ApplicationPortfolioService().build(
  predictions: ps,
  minimums: minimums,
  universityRank: (u) {
    final i = priority.indexOf(u);
    return i < 0 ? 99 : i;
  },
  split: split,
);

void main() {
  const safe = PredictionLevel.safe,
      fit = PredictionLevel.fit,
      reach = PredictionLevel.reach;
  final many = [
    for (final (i, l) in [
      reach,
      reach,
      reach,
      fit,
      fit,
      fit,
      safe,
      safe,
      safe,
    ].indexed)
      _p('대$i', l),
  ];

  test('균형형은 상향·적정·안정 2장씩, 상향부터 정렬', () {
    final r = _build(many);
    expect(r.susi.map((p) => p.slot), ['상향', '상향', '적정', '적정', '안정', '안정']);
    expect(r.notes, isEmpty);
  });

  test('배분 방식을 바꾸면 장 수가 바뀐다', () {
    expect(
      _build(
        many,
        split: SusiSplit.aggressive,
      ).susi.where((p) => p.slot == '상향'),
      hasLength(3),
    );
    expect(
      _build(many, split: SusiSplit.cautious).susi.where((p) => p.slot == '안정'),
      hasLength(3),
    );
  });

  test('어려움·판단 보류·최저 미달은 넣지 않고, 모자란 자리는 다른 단계로 채우지 않는다', () {
    final below = _p('미달대', safe);
    final r = _build(
      [
        _p('가대', reach),
        _p('나대', PredictionLevel.hard),
        _p('다대', PredictionLevel.unknown),
        below,
      ],
      minimums: {below: _m(MinimumStatus.below)},
    );
    expect(r.susi.map((p) => p.prediction.university), ['가대']);
    expect(r.notes.join(), contains('최저가 미달 수준인 수시 1건'));
    expect(r.notes.join(), contains('안정 2자리'));
    expect(r.notes.join(), contains('안정 지원이 없습니다'));
  });

  test('같은 대학은 한 번만, 안정 자리가 먼저 대학을 차지한다', () {
    final r = _build([
      _p('가대', reach, dept: 'A'),
      _p('가대', safe, dept: 'B'),
      _p('나대', reach),
    ], split: SusiSplit.cautious);
    expect(
      r.susi.where((p) => p.prediction.university == '가대').single.slot,
      '안정',
    );
    expect(r.susi.map((p) => p.prediction.university).toSet(), {'가대', '나대'});
  });

  test('같은 단계에서는 신뢰도 → 최저 상태 → 대학 검토 순서로 고른다', () {
    final low = _p('가대', fit, confidence: '낮음');
    final manual = _p('나대', fit);
    final met = _p('다대', fit);
    final later = _p('라대', fit);
    final r = _build(
      [low, manual, met, later],
      minimums: {manual: _m(MinimumStatus.manual), met: _m(MinimumStatus.met)},
      priority: ['라대', '다대'],
      split: SusiSplit.cautious, // 적정 2장
    );
    expect(r.susi.map((p) => p.prediction.university), ['라대', '다대']);
    final withManual = _build([manual], split: SusiSplit.cautious);
    expect(withManual.susi, hasLength(1));
  });

  test('원문 확인 필요 최저는 넣되 주의를 붙인다', () {
    final manual = _p('나대', fit);
    final r = _build([manual], minimums: {manual: _m(MinimumStatus.manual)});
    expect(r.susi.single.note, contains('원문에서 확인'));
  });

  test('정시는 가·나·다군에 한 곳씩, 단계가 고루 퍼진 배치를 고른다', () {
    final r = _build([
      _p('가대', safe, kind: PredictionKind.regular, group: '가군'),
      _p('나대', fit, kind: PredictionKind.regular, group: '가군'),
      _p('다대', safe, kind: PredictionKind.regular, group: '나군'),
      _p('라대', reach, kind: PredictionKind.regular, group: '다군'),
      _p('마대', PredictionLevel.hard, kind: PredictionKind.regular, group: '다군'),
    ]);
    expect(
      {for (final p in r.regular) p.slot: p.prediction.university},
      {
        '가군': '나대', // 나군이 안정뿐이라 가군은 적정
        '나군': '다대',
        '다군': '라대',
      },
    );
    expect(r.notes.where((n) => n.contains('정시')), isEmpty);
  });

  test('정시 군에 후보가 없으면 빈 군을 알린다', () {
    final r = _build([
      _p('가대', fit, kind: PredictionKind.regular, group: '가군'),
    ]);
    expect(r.regular.single.slot, '가군');
    expect(
      r.notes.join(),
      allOf(contains('나군'), contains('다군'), contains('정시 안정 지원이 없습니다')),
    );
  });
}
