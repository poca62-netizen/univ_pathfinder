import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/services/kakao_map.dart';
import 'package:univ_pathfinder/widgets/official_admission_source.dart';

/// Counts derived from the bundled data so the page never drifts from the data.
class DataSourceSummary {
  const DataSourceSummary({
    required this.admissionSource,
    required this.totalTracks,
    required this.universities,
    required this.reviewed,
    required this.matched,
    required this.partial,
    required this.needsCheck,
    required this.mirrorBased,
    required this.comparisonSources,
    required this.comparisonBridges,
    required this.tuitionSource,
    required this.tuitionUrl,
    required this.tuitionNote,
    required this.tuitionRows,
    this.resultSource = '',
    this.resultPages = const [],
    this.susiRows = 0,
    this.regularRows = 0,
    this.aliases = const [],
    this.aliasesCheckedAt = '',
  });

  final String admissionSource;
  final int totalTracks, universities, reviewed, matched, partial, needsCheck;
  final int mirrorBased;
  final List<Map<String, dynamic>> comparisonSources;
  final List<Map<String, dynamic>> comparisonBridges;
  final String tuitionSource, tuitionUrl, tuitionNote;
  final int tuitionRows;

  /// 진학 컨설팅 리포트가 쓰는 어디가 대학별 전형결과(페이지 단위 출처).
  final String resultSource;
  final List<Map<String, dynamic>> resultPages;
  final int susiRows, regularRows;

  /// 과거 입결의 전형명·학과명 변경 대응표(admission_aliases.json) 항목.
  final List<Map<String, dynamic>> aliases;
  final String aliasesCheckedAt;

  static DataSourceSummary fromJson({
    required Map<String, dynamic> admissions,
    required Map<String, dynamic> comparison,
    required Map<String, dynamic> tuition,
    Map<String, dynamic>? results,
    Map<String, dynamic>? aliases,
  }) {
    final rows = (admissions['rows'] as List).cast<Map<String, dynamic>>();
    final reviews = rows
        .map((r) => r['officialReview'])
        .whereType<Map>()
        .toList();
    int count(bool Function(String) test) =>
        reviews.where((r) => test('${r['모집인원'] ?? ''}')).length;
    return DataSourceSummary(
      admissionSource: '${admissions['source'] ?? ''}',
      totalTracks: rows.length,
      universities: rows.map((r) => r['university']).toSet().length,
      reviewed: reviews.length,
      matched: count((s) => s.startsWith('일치') || s.startsWith('정정')),
      partial: count((s) => s.startsWith('부분')),
      needsCheck: count((s) => s.startsWith('불일치')),
      mirrorBased: reviews.where((r) => '${r['근거']}'.contains('재게시본')).length,
      comparisonSources: (comparison['sources'] as List? ?? const [])
          .cast<Map<String, dynamic>>(),
      comparisonBridges: [
        for (final key in ['bridge', 'cumulativeBridge'])
          if (comparison[key] is Map)
            (comparison[key] as Map).cast<String, dynamic>(),
      ],
      tuitionSource: '${tuition['source'] ?? ''}',
      tuitionUrl: '${tuition['sourceUrl'] ?? ''}',
      tuitionNote: '${tuition['note'] ?? ''}',
      tuitionRows: (tuition['rows'] as List? ?? const []).length,
      resultSource: '${results?['source'] ?? ''}',
      resultPages: (results?['sources'] as List? ?? const [])
          .cast<Map<String, dynamic>>(),
      susiRows: (results?['susi'] as List? ?? const []).length,
      regularRows: (results?['jeongsi'] as List? ?? const []).length,
      aliases: [
        for (final key in ['tracks', 'departments'])
          ...(aliases?[key] as List? ?? const []).cast<Map<String, dynamic>>(),
      ],
      aliasesCheckedAt: '${aliases?['checkedAt'] ?? ''}',
    );
  }

  static Future<DataSourceSummary> load(AssetBundle bundle) async {
    Future<Map<String, dynamic>> read(String name) async =>
        jsonDecode(await bundle.loadString('assets/data/$name.json'))
            as Map<String, dynamic>;
    return fromJson(
      admissions: await read('admissions_2028'),
      comparison: await read('admission_comparison'),
      tuition: await read('tuition'),
      results: await read('admission_results')
          .then<Map<String, dynamic>?>((v) => v, onError: (_) => null),
      aliases: await read('admission_aliases')
          .then<Map<String, dynamic>?>((v) => v, onError: (_) => null),
    );
  }
}

class DataSourcesScreen extends StatefulWidget {
  const DataSourcesScreen({super.key, this.bundle});

  /// Injected in tests; defaults to the app bundle.
  final AssetBundle? bundle;

  @override
  State<DataSourcesScreen> createState() => _DataSourcesScreenState();
}

class _DataSourcesScreenState extends State<DataSourcesScreen> {
  late Future<DataSourceSummary> _summary;

  @override
  void initState() {
    super.initState();
    _summary = DataSourceSummary.load(widget.bundle ?? rootBundle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('자료 출처')),
      body: SafeArea(
        child: FutureBuilder<DataSourceSummary>(
          future: _summary,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('자료 출처 정보를 불러오지 못했습니다.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _summary = DataSourceSummary.load(
                          widget.bundle ?? rootBundle,
                        );
                      }),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }
            final s = snapshot.data;
            if (s == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _sections(context, s),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, DataSourceSummary s) {
    final unreviewed = s.totalTracks - s.reviewed;
    return [
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '이 앱의 대학·전형·입결·등록금 정보는 아래 출처를 정리한 참고 자료입니다. '
            '합격 가능성을 판정하지 않으며, 지원 전에는 반드시 각 대학의 최종 모집요강을 확인하세요. '
            '학생의 성적·생활기록부는 출처 자료에 포함되지 않습니다.',
          ),
        ),
      ),
      _Section(
        title: '2028학년도 대학별 전형계획',
        icon: Icons.menu_book_outlined,
        children: [
          Text(
            '수도권 ${s.universities}개 대학 · ${s.totalTracks}개 전형 행. '
            '기초 자료는 사용자 제공 정리본(${s.admissionSource})이며, 작성자 정보는 데이터에 포함하지 않았습니다.',
          ),
          const SizedBox(height: 8),
          Text(
            '공식 원문 대조 ${s.reviewed}건 · 일치 ${s.matched} · 부분 일치 ${s.partial} · '
            '확인 필요 ${s.needsCheck} · 대조 전 $unreviewed',
            key: const Key('review-counts'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Text(
            '대학 탐색·비교·후보 화면에서 각 전형의 "공식 시행계획 대조 근거"를 펼치면 쪽 번호와 판정을 볼 수 있습니다. '
            '"확인 필요"는 원문과 차이가 있으나 원인을 특정하지 못해 값을 바꾸지 않은 항목입니다.',
          ),
          const SizedBox(height: 12),
          const Text('대학 입학처 공식 시행계획(링크 확인일 2026-11-06)'),
          for (final entry in officialPlanLinks2028.entries)
            _SourceLink(label: entry.key, url: entry.value),
          const _SourceLink(
            label: '서울대 시행계획 교육청 재게시본(입학처 첨부 링크 오류 시 사용)',
            url: 'https://jinhak.jje.go.kr/board.do?act=read&bbsid=030500&bbsidx=3394&page=1&searchType=TITLE',
          ),
          const _SourceLink(
            label: '한국대학교육협의회 2028학년도 대학입학전형시행계획 주요사항',
            url: 'https://www.kcue.or.kr/_upload/news/2026/04/30/application_ea0382f8ef4d92cda46a7e015aec3fef.pdf',
          ),
          const SizedBox(height: 8),
          Text(
            '그 밖의 대학 ${s.mirrorBased}건은 각 대학이 작성한 2028 대학입학전형계획 PDF의 재게시본'
            '(cdn013.negagea.net)으로 대조했습니다. 대학 공식 도메인이 아니므로 근거에 '
            '"재게시본, 대학 공식 링크 미확인"으로 표시했습니다.',
          ),
        ],
      ),
      _Section(
        title: '과거 입결 비교(약·중·강)',
        icon: Icons.insights_outlined,
        children: [
          const Text('대학별 2024·2025학년도 결과는 대입정보포털 어디가 공개 자료입니다.'),
          for (final src in s.comparisonSources)
            _SourceLink(
              label:
                  '${src['university']} ${src['year']}학년도 · ${src['note'] ?? ''}',
              url: '${src['url']}',
            ),
          const SizedBox(height: 8),
          const Text('내신 등급 대응표(근사 비교용)'),
          for (final bridge in s.comparisonBridges)
            _SourceLink(label: '${bridge['source']}', url: '${bridge['url']}'),
          const Text(
            '지역 표본을 이용한 근사 대응이며 대학별 환산식이나 개인의 정확한 백분위가 아닙니다.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      if (s.resultPages.isNotEmpty)
        _Section(
          title: '진학 컨설팅 리포트 입결',
          icon: Icons.analytics_outlined,
          children: [
            Text(
              '${s.resultSource}. '
              '${s.resultPages.map((p) => p['university']).toSet().length}개 대학 '
              '${s.resultPages.length}개 페이지에서 수시 ${s.susiRows}행·정시 ${s.regularRows}행을 '
              '표 머리글 기준으로 자동 추출했습니다. 대학마다 공개 지표(50%·70%·80%·90% 컷, 평균, 환산점수)가 다르며, '
              '형식이 달라 추출하지 못한 표는 비워 두었습니다.',
            ),
            ExpansionTile(
              key: const Key('result-pages'),
              tilePadding: EdgeInsets.zero,
              title: const Text('대학별 원문 페이지'),
              children: [
                for (final p in s.resultPages)
                  _SourceLink(
                    label:
                        '${p['university']} ${p['resultYear']}학년도 결과 '
                        '(수시 ${p['susiRows']}·정시 ${p['jeongsiRows']}행)',
                    url: '${p['url']}',
                  ),
              ],
            ),
            if (s.aliases.isNotEmpty)
              ExpansionTile(
                key: const Key('result-aliases'),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '전형명·학과명 변경 대응 (${s.aliasesCheckedAt} 확인 · '
                  '묶음 ${s.aliases.where((a) => a['apply'] == true).length} · '
                  '묶지 않음 ${s.aliases.where((a) => a['apply'] != true).length})',
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '대학이 공개한 전년대비 변경사항으로 이름만 바뀌고 선발 방법이 같다고 확인한 경우만 두 해 입결을 같은 전형으로 묶습니다.',
                    style: TextStyle(fontSize: 13),
                  ),
                  for (final a in s.aliases)
                    _SourceLink(
                      label:
                          '${a['university']} · ${a['apply'] == true ? '묶음' : '묶지 않음'} · '
                          '${a['from'] ?? '학과 ${(a['pairs'] as List).length}쌍'}'
                          '${a['to'] != null ? ' → ${a['to']}' : ''} · ${a['change']}',
                      url: '${a['url']}',
                    ),
                ],
              ),
          ],
        ),
      _Section(
        title: '등록금',
        icon: Icons.payments_outlined,
        children: [
          Text('${s.tuitionSource} · ${s.tuitionRows}개 캠퍼스 행'),
          _SourceLink(label: '공공데이터포털 원자료', url: s.tuitionUrl),
          Text(s.tuitionNote, style: const TextStyle(fontSize: 13)),
        ],
      ),
      const _Section(
        title: '지도·통학 거리',
        icon: Icons.map_outlined,
        children: [
          Text(
            '장소 검색과 지도는 카카오맵(Kakao Maps JavaScript SDK), 자동차 통학시간은 카카오모빌리티 길찾기 API의 '
            '조회 시점 예상값입니다. 대중교통·도보 경로는 카카오맵 길찾기로 연결합니다. 출발지는 저장하지 않습니다.',
          ),
        ],
      ),
      const _Section(
        title: '오류를 발견했다면',
        icon: Icons.report_outlined,
        children: [
          Text(
            '대학의 최종 모집요강이 우선합니다. 앱의 정보와 다르면 모집요강을 기준으로 판단하고, '
            '근거에 적힌 쪽 번호로 원문을 함께 확인하세요.',
          ),
        ],
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const Divider(),
          ...children.map(
            (c) => Padding(padding: const EdgeInsets.only(bottom: 4), child: c),
          ),
        ],
      ),
    );
  }
}

/// Opens an allow-listed https source in a new tab; otherwise shows it for copying.
class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.label, required this.url});
  final String label, url;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(label, textAlign: TextAlign.left),
        onPressed: () {
          final uri = Uri.tryParse(url);
          if (uri != null && openAdmissionSource(uri)) return;
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(label),
              content: SelectableText(url),
              actions: [
                TextButton(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      // The selectable URL stays available for manual copying.
                    }
                  },
                  child: const Text('링크 복사'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
