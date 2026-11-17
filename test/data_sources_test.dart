import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/data_sources_screen.dart';

/// Serves the real bundled JSON files from disk.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('assets/data/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('출처 요약 수치는 번들 데이터에서 계산한다', () {
    final admissions = _read('admissions_2028');
    final s = DataSourceSummary.fromJson(
      admissions: admissions,
      comparison: _read('admission_comparison'),
      tuition: _read('tuition'),
    );
    final rows = (admissions['rows'] as List);
    expect(s.totalTracks, rows.length);
    expect(
      s.reviewed,
      rows.where((r) => (r as Map)['officialReview'] != null).length,
    );
    expect(s.matched + s.partial + s.needsCheck, lessThanOrEqualTo(s.reviewed));
    expect(s.needsCheck, greaterThan(0));
    expect(s.mirrorBased, greaterThan(0));
    expect(s.comparisonSources, isNotEmpty);
    expect(s.comparisonBridges.length, 2);
    expect(s.tuitionSource, contains('한국장학재단'));
    expect(admissions['status'], contains('${s.reviewed}건'));
  });

  test('리포트 입결 출처는 페이지마다 학년도·원문 주소·추출 행 수를 갖는다', () {
    final results = _read('admission_results');
    final s = DataSourceSummary.fromJson(
      admissions: _read('admissions_2028'),
      comparison: _read('admission_comparison'),
      tuition: _read('tuition'),
      results: results,
    );
    expect(s.resultSource, contains('어디가'));
    expect(s.susiRows, (results['susi'] as List).length);
    expect(s.regularRows, (results['jeongsi'] as List).length);
    for (final p in s.resultPages) {
      expect(p['url'], startsWith('https://www.adiga.kr/'));
      expect(p['resultYear'], p['pageYear'] - 1);
    }
    final perPage = s.resultPages.fold<int>(
      0,
      (a, p) => a + (p['susiRows'] as int),
    );
    expect(perPage, s.susiRows);
  });

  test('전형명·학과명 변경 대응표를 묶음/묶지 않음과 확인일로 요약한다', () {
    final s = DataSourceSummary.fromJson(
      admissions: _read('admissions_2028'),
      comparison: _read('admission_comparison'),
      tuition: _read('tuition'),
      aliases: _read('admission_aliases'),
    );
    expect(s.aliasesCheckedAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(s.aliases.where((a) => a['apply'] == true), isNotEmpty);
    expect(s.aliases.where((a) => a['apply'] == false), isNotEmpty);
    expect(s.aliases.where((a) => a['block'] == true), isNotEmpty);
    expect(s.aliases.where((a) => a['caution'] == true), isNotEmpty);
  });

  test('참고 입결(예측에 쓰지 않음)은 자료마다 제목·지표·재게시본 표시·주소를 갖는다', () {
    final s = DataSourceSummary.fromJson(
      admissions: _read('admissions_2028'),
      comparison: _read('admission_comparison'),
      tuition: _read('tuition'),
      reference: _read('admission_reference_results'),
    );
    expect(s.referenceSources, isNotEmpty);
    expect(s.referenceRows, greaterThan(100));
    for (final r in s.referenceSources) {
      expect('${r['title']}', isNotEmpty);
      expect('${r['metric']}', isNotEmpty);
      expect('${r['mirror']}', contains('재게시본'));
      expect('${r['url']}', startsWith('https://'));
    }
  });

  testWidgets('자료 출처 화면: 안내·전형계획 대조 현황·입결·등록금·지도 출처 표시', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: DataSourcesScreen(bundle: _DiskBundle())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('자료 출처'), findsOneWidget);
    expect(find.textContaining('최종 모집요강을 확인하세요'), findsOneWidget);
    expect(find.byKey(const Key('review-counts')), findsOneWidget);
    expect(find.textContaining('공식 원문 대조'), findsWidgets);
    expect(find.text('고려대(서울)'), findsOneWidget);
    expect(find.textContaining('재게시본'), findsWidgets);
    expect(find.textContaining('어디가'), findsNWidgets(2));
    expect(find.text('진학 컨설팅 리포트 입결'), findsOneWidget);
    expect(find.textContaining('한국장학재단'), findsOneWidget);
    expect(find.textContaining('카카오모빌리티'), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-pages')));
    await tester.pumpAndSettle();
    expect(find.textContaining('서울대 2025학년도 결과'), findsOneWidget);
  });

  testWidgets('허용되지 않은 환경에서는 링크를 복사할 수 있게 보여준다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: DataSourcesScreen(bundle: _DiskBundle())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('고려대(서울)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('oku.korea.ac.kr'), findsOneWidget);
    expect(find.text('링크 복사'), findsOneWidget);
  });
}
