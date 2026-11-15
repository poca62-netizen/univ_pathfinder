import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';

class ConsultingPoint {
  const ConsultingPoint(this.title, this.question, this.action);
  final String title, question, action;
}

class EvidenceConsultation {
  EvidenceConsultation(this.source, this.points);
  final SchoolRecordEvidence source;
  final List<ConsultingPoint> points;
}

/// Local discussion prompts, never an aptitude or admissions assessment.
class ConsultingService {
  String memo(CounselingSummary summary, Set<String> selected, String goal) {
    final records = build(summary).where((c) => selected.contains(c.source.id));
    if (records.isEmpty) return '';
    return [
      '생기부 상담 메모 · 원문 키워드 기반 질문 제안',
      '상담 목표: ${goal.trim().isEmpty ? "미작성" : goal.trim()}',
      'AI 평가가 아닙니다. 실제 경험과 원문 문맥을 확인하세요.',
      for (final c in records) ...[
        '',
        '${c.source.calendarYear}년 ${c.source.schoolYear}학년 · ${c.source.category}',
        '출처: ${c.source.sourceLocation}',
        '근거 ID: ${c.source.id}',
        '원문: ${c.source.evidence}',
        for (final p in c.points) ...[
          '${p.title} — 상담 질문: ${p.question}',
          '다음 행동 제안: ${p.action}',
        ],
      ],
    ].join('\n');
  }

  List<EvidenceConsultation> build(CounselingSummary summary) {
    if (summary.activities.failed) return [];
    final records = summary.activitiesFor(null).toList()
      ..sort((a, b) {
        final year = b.calendarYear.compareTo(a.calendarYear);
        return year != 0 ? year : a.id.compareTo(b.id);
      });
    return [
      for (final r in records)
        EvidenceConsultation(r, [
          if (RegExp('탐구|실험|분석|조사|연구|가설').hasMatch(r.evidence))
            const ConsultingPoint(
              '탐구 과정 확인',
              '어떤 질문에서 출발했고, 방법을 선택한 이유와 결과의 한계는 무엇인가요?',
              '기록 속 탐구 하나를 골라 질문·방법·결과·한계를 한 장으로 정리하고, 다음에 확인할 질문을 적어보세요.',
            ),
          if (RegExp('협업|협력|모둠|공동|팀|역할').hasMatch(r.evidence))
            const ConsultingPoint(
              '협업에서의 기여 확인',
              '함께한 활동에서 본인이 맡은 일과 의견 차이를 해결한 사례는 무엇인가요?',
              '공동 결과와 본인의 기여를 구분하고, 협의 과정에서 바뀐 선택을 구체적인 사례로 정리해보세요.',
            ),
          if (RegExp('발표|토론|설명|글쓰기|보고서').hasMatch(r.evidence))
            const ConsultingPoint(
              '근거를 전달한 경험 확인',
              '누구에게 무엇을 전달했고, 어떤 근거와 피드백으로 설명을 다듬었나요?',
              '설명이나 발표의 핵심 주장과 근거를 정리하고, 받은 질문 하나에 답을 보완해보세요.',
            ),
          if (RegExp('성찰|개선|수정|피드백|시행착오').hasMatch(r.evidence))
            const ConsultingPoint(
              '변화와 성찰 확인',
              '처음과 비교해 생각이나 방법이 어떻게 달라졌고, 변화의 계기는 무엇인가요?',
              '시도 전후를 비교하고, 다음 활동에서 유지할 점과 바꿀 점을 하나씩 적어보세요.',
            ),
          const ConsultingPoint(
            '진로 연결 탐색',
            '이 활동에서 더 알고 싶은 문제는 무엇이며, 관심 분야와 어떤 연결을 직접 설명할 수 있나요?',
            '활동에서 생긴 질문 하나를 관심 분야의 책·수업·작은 탐구로 이어가고, 실제로 수행한 과정만 기록하세요.',
          ),
        ]),
    ];
  }
}
