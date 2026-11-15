import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';

class UniversityComparisonMemo {
  String build({
    required AdmissionCatalog catalog,
    required Set<String> selected,
    TuitionCatalog? tuition,
    String query = '',
    String type = '전체',
    bool includeSpecial = false,
  }) {
    if (selected.isEmpty) return '';
    final names = selected.toList()..sort();
    final q = query.trim().toLowerCase();
    String field(String value) => value.trim().isEmpty ? '자료 미기재' : value;
    final out = StringBuffer()
      ..writeln('${catalog.year}학년도 관심 대학 비교 메모')
      ..writeln('선택 대학 ${names.length}개 · 가나다순이며 추천 순위가 아닙니다.')
      ..writeln(
        '검색어: ${query.trim().isEmpty ? "없음" : query.trim()} · 전형: $type · 특별 지원자격: ${includeSpecial ? "포함" : "제외"}',
      )
      ..writeln('확인 상태: ${catalog.status}')
      ..writeln('전형은 현재 검색·필터에 맞는 항목만 포함합니다. 조건에 맞지 않는 선택 대학도 아래에 표시합니다.')
      ..writeln('지원자격·추천·수능 최저 충족 및 합격을 판정한 결과가 아닙니다. 최종 모집요강을 확인하세요.')
      ..writeln(
        '등록금은 과거 연간 평균 공시이며 학과별 고지액·2028 확정액·장학금 차감 실부담액이 아닙니다. 통학 경로는 미연결입니다.',
      )
      ..writeln('이 메모에는 학생 성적·생기부 원문·계정 정보를 포함하지 않습니다.');
    if (tuition == null) {
      out.writeln('등록금: 조회 실패 또는 자료 미확보');
    } else {
      out
        ..writeln('등록금 출처: ${tuition.source}')
        ..writeln(tuition.sourceUrl)
        ..writeln(tuition.note);
    }
    for (final name in names) {
      final all = catalog.tracks.where((t) => t.university == name).toList();
      final tracks = all.where(
        (t) =>
            (type == '전체' || t.type == type) &&
            (includeSpecial || !t.requiresSpecialEligibility) &&
            (q.isEmpty ||
                '${t.university} ${t.department} ${t.name}'
                    .toLowerCase()
                    .contains(q)),
      );
      out
        ..writeln()
        ..writeln('=== $name ===');
      if (tuition != null) {
        out.writeln(tuition.labelFor(name));
        for (final r in tuition.forUniversity(name)) {
          out.writeln(
            '${r.officialName} · ${r.campus} · ${r.year}년 연간 평균 ${r.amountLabel} · 기준일 ${r.asOf} · ${r.scope}',
          );
        }
      }
      if (all.isEmpty) {
        out.writeln('현재 전형 자료에 없는 대학입니다. 저장한 대학명을 확인하세요.');
      } else if (tracks.isEmpty) {
        out.writeln('현재 검색·전형 조건에 맞는 전형이 없습니다.');
      } else {
        out.writeln('조건에 맞는 전형 ${tracks.length}개');
        for (final t in tracks) {
          out
            ..writeln('- ${t.type} · ${t.name}')
            ..writeln(
              '  모집단위: ${field(t.department)} · 모집 인원 원문: ${field(t.quota)}',
            )
            ..writeln('  지원자격: ${field(t.eligibility)}')
            ..writeln(
              '  추천: ${field(t.recommendation)} · 추천 주체: ${field(t.recommender)}',
            )
            ..writeln('  선발 방법: ${field(t.selection)}')
            ..writeln('  수능 최저: ${field(t.minimum)}')
            ..writeln('  자료 구역: ${field(t.section)}');
          if (t.requiresSpecialEligibility) out.writeln('  특별 지원자격 확인이 필요합니다.');
        }
      }
    }
    return out.toString();
  }
}
