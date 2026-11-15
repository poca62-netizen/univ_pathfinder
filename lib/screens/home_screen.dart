import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/start_screen.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/counseling_summary_screen.dart';
import 'package:univ_pathfinder/screens/consulting_screen.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';
import 'package:univ_pathfinder/screens/grade_upload_selector_screen.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/screens/university_compare_screen.dart';
import 'package:univ_pathfinder/screens/favorites_settings_screen.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';
import 'package:univ_pathfinder/screens/counseling_documents_screen.dart';

class HomeScreen extends StatelessWidget {
  final String nickname;
  final bool demoMode;
  const HomeScreen({super.key, required this.nickname, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Univ Pathfinder'),
        actions: [
          if (!demoMode)
            IconButton(
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                try {
                  await Supabase.instance.client.auth.signOut(
                    scope: SignOutScope.local,
                  );
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
              },
            ),
          if (!demoMode)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FavoritesSettingsScreen(nickname: nickname),
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '안녕하세요, $nickname 님',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('내신·모의고사·생활기록부를 모아 관심 분야의 대학을 비교하세요.'),
              const ExampleBadge(text: '대학 후보: 2028 참고자료 · 탐색/비교: 가상 예시'),
              if (demoMode) const Text('무료 체험 모드 · 로그인과 서버 저장 없이 둘러볼 수 있습니다.'),
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) => GridView.count(
                    crossAxisCount: bounds.maxWidth >= 1000
                        ? 4
                        : bounds.maxWidth >= 700
                        ? 3
                        : 2,
                    childAspectRatio: bounds.maxWidth >= 700 ? 1.3 : .95,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      if (!demoMode)
                        _menuCard(
                          context,
                          title: '성적·생기부 대학 후보',
                          icon: Icons.school_outlined,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const UniversityRecommendationScreen(),
                            ),
                          ),
                        ),
                      if (!demoMode)
                        _menuCard(
                          context,
                          title: '생기부 컨설팅',
                          icon: Icons.forum_outlined,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConsultingScreen(),
                            ),
                          ),
                        ),
                      _menuCard(
                        context,
                        title: '상담 자료',
                        icon: Icons.folder_copy_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CounselingDocumentsScreen(),
                          ),
                        ),
                      ),
                      _menuCard(
                        context,
                        title: '상담 요약',
                        icon: Icons.summarize_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CounselingSummaryScreen(),
                          ),
                        ),
                      ),
                      if (!demoMode)
                        _menuCard(
                          context,
                          title: '성적표 등록',
                          icon: Icons.upload_file,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GradeUploadSelectorScreen(),
                            ),
                          ),
                        ),
                      if (!demoMode)
                        _menuCard(
                          context,
                          title: '성적 분석',
                          icon: Icons.analytics,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GradeAnalysisScreen(),
                            ),
                          ),
                        ),
                      _menuCard(
                        context,
                        title: '대학 탐색',
                        icon: Icons.search,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UniversitySearchScreen(),
                          ),
                        ),
                      ),
                      _menuCard(
                        context,
                        title: '대학 비교',
                        icon: Icons.compare,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UniversityCompareScreen(),
                          ),
                        ),
                      ),
                      _menuCard(
                        context,
                        title: '출발지·대학 지도',
                        icon: Icons.map_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UniversityMapScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
