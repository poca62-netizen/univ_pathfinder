import 'package:univ_pathfinder/services/admission_prediction_service.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// 수시 6장 배분 방식. 숫자는 상향·적정·안정 장 수.
enum SusiSplit {
  aggressive('상향 중심', 3, 2, 1),
  balanced('균형', 2, 2, 2),
  cautious('안정 중심', 1, 2, 3);

  const SusiSplit(this.label, this.reach, this.fit, this.safe);
  final String label;
  final int reach, fit, safe;
  int count(PredictionLevel l) => switch (l) {
    PredictionLevel.reach => reach,
    PredictionLevel.fit => fit,
    PredictionLevel.safe => safe,
    _ => 0,
  };
}

class PortfolioPick {
  const PortfolioPick(this.prediction, this.slot, {this.minimum, this.note});
  final AdmissionPrediction prediction;

  /// 수시: 상향·적정·안정, 정시: 가군·나군·다군.
  final String slot;
  final MinimumCheck? minimum;
  final String? note;
}

class ApplicationPortfolio {
  const ApplicationPortfolio({
    required this.susi,
    required this.regular,
    required this.notes,
  });
  final List<PortfolioPick> susi, regular;

  /// 빈 자리·제외 사유 등 조합을 읽을 때 알아야 할 점.
  final List<String> notes;
}

/// 예측 결과만으로 지원 조합 "예시"를 만든다. 새 수치를 추정하지 않고, 고른 이유를 함께 남긴다.
///
/// 규칙
/// - 어려움·판단 보류는 넣지 않는다. 수시는 수능 최저 미달 수준도 넣지 않는다.
/// - 한 조합 안에서 같은 대학은 한 번만(수시) / 군별 한 곳(정시).
/// - 같은 단계 안에서는 신뢰도 → 최저 상태(없음·충족 > 원문 확인 > 자료 부족) → 대학 검토 순서로 고른다.
/// - 자리가 모자라면 다른 단계로 채우지 않고 빈 자리로 밝힌다.
class ApplicationPortfolioService {
  static const _confidence = {'높음': 0, '보통': 1, '낮음': 2};
  static const _levels = [
    PredictionLevel.reach,
    PredictionLevel.fit,
    PredictionLevel.safe,
  ];

  int _minimumRank(MinimumCheck? c) => switch (c?.result.status) {
    MinimumStatus.none || MinimumStatus.met || null => 0,
    MinimumStatus.manual => 1,
    MinimumStatus.insufficient => 2,
    MinimumStatus.below => 3,
  };

  ApplicationPortfolio build({
    required List<AdmissionPrediction> predictions,
    required Map<AdmissionPrediction, MinimumCheck> minimums,
    required int Function(String university) universityRank,
    SusiSplit split = SusiSplit.balanced,
  }) {
    int compare(AdmissionPrediction a, AdmissionPrediction b) {
      final c = (_confidence[a.confidence] ?? 3).compareTo(
        _confidence[b.confidence] ?? 3,
      );
      if (c != 0) return c;
      final m = _minimumRank(minimums[a]).compareTo(_minimumRank(minimums[b]));
      if (m != 0) return m;
      final u = universityRank(a.university)
          .compareTo(universityRank(b.university));
      return u != 0
          ? u
          : '${a.university}${a.department}'.compareTo(
              '${b.university}${b.department}',
            );
    }

    final notes = <String>[];

    // 수시
    final susiPool = predictions
        .where((p) => p.kind != PredictionKind.regular)
        .toList();
    final belowCount = susiPool
        .where((p) => minimums[p]?.result.status == MinimumStatus.below)
        .length;
    final susi = <PortfolioPick>[];
    final usedUniversities = <String>{};
    // 대학 중복을 막을 때 안정 자리가 먼저 대학을 차지하도록 안정 → 적정 → 상향 순으로 채운다.
    for (final level in _levels.reversed) {
      final want = split.count(level);
      final candidates =
          susiPool
              .where(
                (p) =>
                    p.level == level &&
                    minimums[p]?.result.status != MinimumStatus.below,
              )
              .toList()
            ..sort(compare);
      var got = 0;
      for (final p in candidates) {
        if (got == want) break;
        if (!usedUniversities.add(p.university)) continue;
        final m = minimums[p];
        susi.add(
          PortfolioPick(
            p,
            level.label,
            minimum: m,
            note: m?.result.status == MinimumStatus.manual
                ? '수능 최저를 원문에서 확인해야 합니다.'
                : m?.result.status == MinimumStatus.insufficient
                ? '수능 최저를 판정할 모의고사 자료가 부족합니다.'
                : null,
          ),
        );
        got++;
      }
      if (got < want) {
        notes.add(
          '수시 ${level.label} ${want - got}자리를 채울 후보가 없습니다. 관심 분야를 넓히거나 성적 자료를 보완하세요.',
        );
      }
    }
    susi.sort(
      (a, b) => _levels
          .indexOf(a.prediction.level)
          .compareTo(_levels.indexOf(b.prediction.level)),
    );
    if (belowCount > 0) {
      notes.add('수능 최저가 미달 수준인 수시 $belowCount건은 조합에서 뺐습니다.');
    }
    if (!susi.any((p) => p.prediction.level == PredictionLevel.safe) &&
        susiPool.isNotEmpty) {
      notes.add('수시 안정 지원이 없습니다. 정시 계획과 함께 검토하세요.');
    }

    // 정시: 가·나·다군에 상향·적정·안정을 하나씩 나누는 배치 중 가장 많이 채워지는 것을 고른다.
    const groups = ['가군', '나군', '다군'];
    final best = <String, Map<PredictionLevel, AdmissionPrediction>>{};
    for (final g in groups) {
      for (final level in _levels) {
        final c =
            predictions
                .where(
                  (p) =>
                      p.kind == PredictionKind.regular &&
                      p.group == g &&
                      p.level == level,
                )
                .toList()
              ..sort(compare);
        if (c.isNotEmpty) (best[g] ??= {})[level] = c.first;
      }
    }
    List<PredictionLevel?> chosen = const [null, null, null];
    var chosenScore = -1;
    // 같은 단계를 두 군에 둘 수도 있게 3^3 배치를 모두 본다. 단계가 고루 퍼진 배치를 우선한다.
    for (final a in _levels) {
      for (final b in _levels) {
        for (final c in _levels) {
          final plan = [a, b, c];
          var filled = 0;
          final unis = <String>{};
          var dup = false;
          for (var i = 0; i < 3; i++) {
            final p = best[groups[i]]?[plan[i]];
            if (p == null) continue;
            filled++;
            if (!unis.add(p.university)) dup = true;
          }
          if (dup) continue;
          final spread = plan
              .asMap()
              .entries
              .where((e) => best[groups[e.key]]?[e.value] != null)
              .map((e) => e.value)
              .toSet()
              .length;
          final hasSafe = [
            for (var i = 0; i < 3; i++)
              if (best[groups[i]]?[plan[i]] != null) plan[i],
          ].contains(PredictionLevel.safe);
          final score = filled * 100 + spread * 10 + (hasSafe ? 1 : 0);
          if (score > chosenScore) {
            chosenScore = score;
            chosen = plan;
          }
        }
      }
    }
    final regular = <PortfolioPick>[];
    if (best.isEmpty) {
      if (predictions.any((p) => p.kind == PredictionKind.regular)) {
        notes.add('정시 후보가 모두 어려움·판단 보류라 정시 조합을 만들지 않았습니다.');
      }
      return ApplicationPortfolio(susi: susi, regular: regular, notes: notes);
    }
    for (var i = 0; i < 3; i++) {
      final level = chosen[i];
      final p = level == null ? null : best[groups[i]]?[level];
      if (p == null) {
        notes.add('정시 ${groups[i]}에 넣을 안정·적정·상향 후보가 없습니다.');
        continue;
      }
      regular.add(PortfolioPick(p, groups[i]));
    }
    if (regular.isNotEmpty &&
        !regular.any((p) => p.prediction.level == PredictionLevel.safe)) {
      notes.add('정시 안정 지원이 없습니다.');
    }
    return ApplicationPortfolio(susi: susi, regular: regular, notes: notes);
  }
}
