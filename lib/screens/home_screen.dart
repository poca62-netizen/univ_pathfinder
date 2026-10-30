import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/grade_upload_selector_screen.dart';
import 'package:univ_pathfinder/screens/grade_analysis_screen.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';
import 'package:univ_pathfinder/screens/university_compare_screen.dart';
import 'package:univ_pathfinder/screens/favorites_settings_screen.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  final String nickname;
  const HomeScreen({super.key, required this.nickname});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Univ Pathfinder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FavoritesSettingsScreen()),
              );
            },
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('안녕하세요, $nickname 님', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const ExampleBadge(text: '현재 예시 데이터입니다'),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _menuCard(
                      context,
                      title: '성적표 등록',
                      icon: Icons.upload_file,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GradeUploadSelectorScreen()),
                      ),
                    ),
                    _menuCard(
                      context,
                      title: '성적 분석',
                      icon: Icons.analytics,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GradeAnalysisScreen()),
                      ),
                    ),
                    _menuCard(
                      context,
                      title: '대학 탐색',
                      icon: Icons.search,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UniversitySearchScreen()),
                      ),
                    ),
                    _menuCard(
                      context,
                      title: '대학 비교',
                      icon: Icons.compare,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UniversityCompareScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard(BuildContext context, {required String title, required IconData icon, required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: const Color(0xFF0D47A1)),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
