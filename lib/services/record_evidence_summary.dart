import 'package:univ_pathfinder/models/school_record_evidence.dart';

/// 관심 분야와 연결된 생기부 근거의 양과 위치. 학생부종합 서류평가는 대학별 정성 평가라
/// 점수·등급으로 바꾸지 않고, 어떤 근거가 어디에 몇 건 있는지만 보여 준다.
class RecordEvidenceSummary {
  const RecordEvidenceSummary({
    required this.interest,
    required this.usable,
    required this.matched,
    required this.byMemo,
  });

  final String interest;

  /// 상담 활용으로 켜 둔(원문 대조 확인된) 근거 수.
  final int usable;
  final List<SchoolRecordEvidence> matched;

  /// matched 중 학생이 적은 진로 메모로 연결된 건수(나머지는 원문 단어 일치).
  final int byMemo;

  int get byText => matched.length - byMemo;

  Map<int, int> get byYear => _count(matched.map((r) => r.schoolYear));
  Map<String, int> get byCategory => _count(matched.map((r) => r.category));

  static Map<K, int> _count<K extends Comparable<Object>>(Iterable<K> keys) {
    final out = <K, int>{};
    for (final k in keys) {
      out[k] = (out[k] ?? 0) + 1;
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// [matches]는 대학 후보와 같은 분야 일치 규칙(text, interest)을 받는다.
  static RecordEvidenceSummary build(
    Iterable<SchoolRecordEvidence> records,
    String interest,
    bool Function(String text, String interest) matches,
  ) {
    final usable = records.where((r) => r.careerEvidenceEnabled).toList();
    final matched = <SchoolRecordEvidence>[];
    var byMemo = 0;
    for (final r in usable) {
      final memo = r.careerInterest?.trim() ?? '';
      final viaMemo =
          memo.isNotEmpty &&
          (matches(memo, interest) || matches(interest, memo));
      if (viaMemo || matches(r.evidence, interest)) {
        matched.add(r);
        if (viaMemo) byMemo++;
      }
    }
    matched.sort((a, b) {
      final y = a.schoolYear.compareTo(b.schoolYear);
      return y != 0 ? y : a.category.compareTo(b.category);
    });
    return RecordEvidenceSummary(
      interest: interest,
      usable: usable.length,
      matched: matched,
      byMemo: byMemo,
    );
  }

  /// 화면에 그대로 쓰는 한 줄 요약.
  String describe() {
    if (usable == 0) {
      return '상담에 쓰도록 확인한 생기부 근거가 없습니다. 학생부종합은 서류 평가 비중이 커서 생기부 근거를 먼저 등록·확인하세요.';
    }
    if (matched.isEmpty) {
      return '확인된 생기부 근거 $usable건 중 관심 분야 "$interest"와 연결된 근거가 없습니다. 진로 메모를 적거나 관련 활동을 확인하세요.';
    }
    final years = byYear.entries.map((e) => '${e.key}학년 ${e.value}').join('·');
    final cats = byCategory.entries.map((e) => '${e.key} ${e.value}').join('·');
    return '관심 분야 "$interest"와 연결된 생기부 근거 ${matched.length}건'
        '(확인된 근거 $usable건 중) — $years / $cats. '
        '진로 메모로 연결 $byMemo건, 원문 단어 일치 $byText건.';
  }
}
