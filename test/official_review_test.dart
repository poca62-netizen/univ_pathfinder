import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/csat_minimum_service.dart';

/// Guards the hand-entered official-plan review records in the admissions bundle.
void main() {
  final data =
      jsonDecode(File('assets/data/admissions_2028.json').readAsStringSync())
          as Map<String, dynamic>;
  final rows = (data['rows'] as List).cast<Map<String, dynamic>>();
  final reviewed = rows.where((r) => r['officialReview'] != null).toList();
  const fields = [
    '확인일',
    '모집단위',
    '근거',
    '모집인원',
    '지원자격',
    '추천',
    '선발방법',
    '수능최저',
    '일정',
  ];

  test('상단 상태 문구의 대조 건수가 실제 대조 행 수와 같다', () {
    expect(data['status'], '공식 시행계획 대조 근거 ${reviewed.length}건 반영');
  });

  test('모든 대조 기록에 필수 항목·확인일·쪽 근거가 있다', () {
    for (final row in reviewed) {
      final review = (row['officialReview'] as Map).cast<String, dynamic>();
      final label = '${row['university']} ${row['name']} ${row['department']}';
      for (final field in fields) {
        expect(
          (review[field] as String?)?.trim(),
          isNotEmpty,
          reason: '$label: $field',
        );
      }
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(review['확인일'] as String),
        isTrue,
        reason: '$label: 확인일',
      );
      expect(review['근거'] as String, contains('쪽'), reason: '$label: 근거');
    }
  });

  test('모집인원이 "일치"인 대조 기록은 번들 인원 숫자를 근거에 포함한다', () {
    for (final row in reviewed) {
      final review = (row['officialReview'] as Map).cast<String, dynamic>();
      final count = review['모집인원'] as String;
      if (!count.startsWith('일치')) continue;
      final quota = RegExp(r'\d[\d,]*').firstMatch(row['quota'] as String);
      if (quota == null) continue;
      expect(
        count,
        contains(quota.group(0)),
        reason: '${row['university']} ${row['name']}: ${row['quota']} vs $count',
      );
    }
  });

  test('경희대 논술 수능 최저 3개 기준(체육 포함)을 자동 비교가 해석한다', () {
    final row = rows.singleWhere(
      (r) =>
          r['university'] == '경희대' &&
          r['name'] == '논술우수자전형' &&
          (r['department'] as String).isEmpty,
    );
    final service = CsatMinimumService();
    final branches = service.branches(row['minimum'] as String);
    expect(branches.map((b) => b.label), [
      '인문/자연/자유',
      '의예/한의예/치의예/약학',
      '체육',
    ]);
    for (final branch in branches) {
      expect(service.parse(branch.text), isNotNull, reason: branch.label);
    }
    final pe = service.parse(branches.last.text)!;
    expect(pe.count, 1);
    expect(pe.limit, 3);
    expect(pe.each, isTrue);
    expect(pe.historyLimit, isNull);
  });

  test('5개 공식 대조 대학의 번들 행(전형 요약·모집단위)은 모두 대조됐다', () {
    const universities = ['서울대', '연세대(서울)', '고려대(서울)', '경희대', '숭실대'];
    final target = rows.where((r) => universities.contains(r['university']));
    expect(target.length, 152);
    final missing = target
        .where((r) => r['officialReview'] == null)
        .map((r) => '${r['university']} ${r['name']} ${r['department']}')
        .toList();
    expect(missing, isEmpty);
  });

  test('전체 번들의 의·치·한·약·수의 모집단위 행은 모두 대조됐다', () {
    final medical = RegExp('의예|의학|치의|한의|약학|수의');
    final missing = rows
        .where(
          (r) =>
              medical.hasMatch(r['department'] as String) &&
              r['officialReview'] == null,
        )
        .map((r) => '${r['university']} ${r['department']} ${r['name']}')
        .toList();
    expect(missing, isEmpty);
  });

  test('동국대 약학과 기초생활수급자 정시는 원문 모집단위표대로 나군이다', () {
    final row = rows.singleWhere(
      (r) =>
          r['university'] == '동국대(서울)' &&
          r['department'] == '약학과' &&
          (r['name'] as String).contains('기초생활수급자'),
    );
    expect(row['name'], contains('나군'));
  });

  test('경희대 의예·한의예·치의예·약학 정시는 원문 모집단위표대로 나군이다', () {
    const units = ['의예과', '한의예과(자연)', '한의예과(인문)', '치의예과', '약학과'];
    final jeongsi = rows.where(
      (r) =>
          r['university'] == '경희대' &&
          units.contains(r['department']) &&
          (r['name'] as String).startsWith('수능'),
    );
    expect(jeongsi.length, 16);
    for (final r in jeongsi) {
      expect(r['name'], contains('나군'), reason: '${r['department']} ${r['name']}');
    }
  });
}
