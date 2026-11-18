import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/start_screen.dart';
import 'package:univ_pathfinder/screens/app_help_screen.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/counseling_summary_screen.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';
import 'package:univ_pathfinder/screens/data_sources_screen.dart';
import 'package:univ_pathfinder/screens/consulting_report_screen.dart';
import 'package:univ_pathfinder/screens/grade_upload_selector_screen.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/screens/university_compare_screen.dart';
import 'package:univ_pathfinder/screens/favorites_settings_screen.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';
import 'package:univ_pathfinder/widgets/ui_kit.dart';

/// 홈: 핵심 기능(진학 컨설팅 리포트)을 맨 위에 두고, 나머지는 쓰임새별로 묶는다.
class HomeScreen extends StatelessWidget {
  final String nickname;
  final bool demoMode;
  const HomeScreen({super.key, required this.nickname, this.demoMode = false});

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final myData = <_MenuItem>[
      _MenuItem(
        '상담 자료',
        '내신·모의고사·생활기록부 등록과 확인',
        Icons.folder_copy_outlined,
        () => _open(context, const CounselingDocumentsScreen()),
      ),
      if (!demoMode)
        _MenuItem(
          '성적표 등록',
          '내신 성적표 파일을 올려 성적 읽기',
          Icons.upload_file_outlined,
          () => _open(context, const GradeUploadSelectorScreen()),
        ),
      if (!demoMode)
        _MenuItem(
          '성적 분석',
          '학기별 등급 흐름과 과목별 성적',
          Icons.insights_outlined,
          () => _open(context, const GradeAnalysisScreen()),
        ),
      _MenuItem(
        '상담 요약',
        '저장한 성적·활동 근거를 한눈에',
        Icons.summarize_outlined,
        () => _open(context, const CounselingSummaryScreen()),
      ),
      if (!demoMode)
        _MenuItem(
          '생기부 컨설팅',
          '활동 근거로 상담 질문 정리·AI 상담',
          Icons.forum_outlined,
          () => _open(context, const ConsultingScreen()),
        ),
    ];
    final universities = <_MenuItem>[
      if (!demoMode)
        _MenuItem(
          '성적·생기부 대학 후보',
          '내 자료로 지원 검토 대학 고르기',
          Icons.school_outlined,
          () => _open(context, const UniversityRecommendationScreen()),
        ),
      _MenuItem(
        '대학 탐색',
        '수도권 대학의 2028 전형·등록금 검색',
        Icons.search,
        () => _open(context, const UniversitySearchScreen()),
      ),
      _MenuItem(
        '대학 비교',
        '관심 대학의 모집정보·등록금 나란히 보기',
        Icons.compare_outlined,
        () => _open(context, const UniversityCompareScreen()),
      ),
      _MenuItem(
        '출발지·대학 지도',
        '집에서 대학까지 거리와 통학 시간',
        Icons.map_outlined,
        () => _open(context, const UniversityMapScreen()),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Univ Pathfinder'),
        actions: [
          IconButton(
            tooltip: '앱 도움말',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _open(context, AppHelpScreen(demoMode: demoMode)),
          ),
          if (!demoMode)
            IconButton(
              tooltip: '설정',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () =>
                  _open(context, FavoritesSettingsScreen(nickname: nickname)),
            ),
          if (!demoMode)
            IconButton(
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              onPressed: () => _signOut(context),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final wide = bounds.maxWidth >= 720;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 20,
                vertical: wide ? 32 : 20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('안녕하세요, $nickname 님', style: text.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        '내신·모의고사·생활기록부로 지원할 대학을 찾고, 근거와 함께 합격 가능성을 살펴보세요.',
                        style: text.bodyLarge?.copyWith(
                          color: PathfinderTheme.muted,
                        ),
                      ),
                      if (demoMode) ...[
                        const SizedBox(height: 16),
                        const InfoNote(
                          '체험 모드입니다. 로그인 없이 대학 탐색·비교·지도를 둘러볼 수 있고, 입력한 내용은 저장되지 않습니다.',
                          icon: Icons.visibility_outlined,
                        ),
                      ],
                      SizedBox(height: wide ? 28 : 20),
                      _HeroCard(
                        wide: wide,
                        demoMode: demoMode,
                        onPrimary: demoMode
                            ? () =>
                                  _open(context, const UniversitySearchScreen())
                            : () => _open(
                                context,
                                const ConsultingReportScreen(),
                              ),
                      ),
                      SizedBox(height: wide ? 36 : 28),
                      _Section(title: '내 자료', items: myData),
                      SizedBox(height: wide ? 32 : 24),
                      _Section(title: '대학 찾기·비교', items: universities),
                      SizedBox(height: wide ? 32 : 24),
                      _Section(
                        title: '참고',
                        items: [
                          _MenuItem(
                            '자료 출처',
                            '전형·입결·등록금의 출처와 원문 대조 현황',
                            Icons.fact_check_outlined,
                            () => _open(context, const DataSourcesScreen()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '대학·전형 정보는 2028학년도 대학별 전형계획을 대학 시행계획 원문과 대조한 참고 자료입니다. '
                        '지원 전에는 각 대학의 최종 모집요강을 확인하세요.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (!context.mounted) return;
      CounselingSession.instance.clear();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (_) => false,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그아웃하지 못했습니다. 다시 시도하세요.')),
        );
      }
    }
  }
}

class _MenuItem {
  const _MenuItem(this.title, this.description, this.icon, this.onTap);
  final String title, description;
  final IconData icon;
  final VoidCallback onTap;
}

/// 맨 위 핵심 기능 카드. 로그인하면 진학 컨설팅 리포트, 체험 모드에서는 대학 탐색으로 안내한다.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.wide,
    required this.demoMode,
    required this.onPrimary,
  });
  final bool wide, demoMode;
  final VoidCallback onPrimary;

  static const _steps = ['상담 자료 등록', '대학 후보 확인', '리포트로 비교'];

  @override
  Widget build(BuildContext context) {
    const onHero = Colors.white;
    final title = demoMode ? '먼저 대학 자료를 둘러보세요' : '진학 컨설팅 리포트';
    final body = demoMode
        ? '수도권 대학의 2028학년도 전형과 등록금을 검색할 수 있어요. 로그인하면 내 성적으로 지원 가능한 대학과 합격 가능성을 근거와 함께 보여 드립니다.'
        : '내 내신·모의고사로 지원 가능한 대학을 고르고, 비교한 과거 입결과 신뢰도를 함께 보여 줍니다. 합격을 보장하지는 않아요.';
    final steps = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, s) in _steps.indexed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: Text(
              '${i + 1}  $s',
              style: const TextStyle(
                color: onHero,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
    final button = FilledButton.icon(
      onPressed: onPrimary,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: PathfinderTheme.accent,
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
      icon: Icon(demoMode ? Icons.search : Icons.analytics_outlined, size: 20),
      label: Text(demoMode ? '대학 탐색 시작' : '리포트 보기'),
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          demoMode ? '체험하기' : '핵심 기능',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .78),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            color: onHero,
            fontSize: wide ? 26 : 22,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .88),
            fontSize: 14.5,
            height: 1.6,
          ),
        ),
        if (!demoMode) ...[const SizedBox(height: 16), steps],
      ],
    );
    return Container(
      padding: EdgeInsets.all(wide ? 32 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B8A76), Color(0xFF0F5A4D)],
        ),
        boxShadow: [
          BoxShadow(
            color: PathfinderTheme.accent.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 32),
                button,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 20), button],
            ),
    );
  }
}

/// 제목과 카드 묶음. 폭에 따라 1~3열.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 900
                ? 3
                : bounds.maxWidth >= 560
                ? 2
                : 1;
            const gap = 12.0;
            final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: ActionCard(
                      title: item.title,
                      subtitle: item.description,
                      icon: item.icon,
                      onTap: item.onTap,
                      minHeight: 84,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
