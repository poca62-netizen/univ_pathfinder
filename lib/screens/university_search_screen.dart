import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/example_university.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class UniversitySearchScreen extends StatefulWidget {
  const UniversitySearchScreen({super.key});

  @override
  State<UniversitySearchScreen> createState() => _UniversitySearchScreenState();
}

class _UniversitySearchScreenState extends State<UniversitySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCareer = '전체';

  final List<String> careers = ['전체', '공학', '인문사회', '자연과학'];

  @override
  Widget build(BuildContext context) {
    final filtered = exampleUniversities.where((u) {
      final matchesSearch = u.name.contains(_searchController.text) || u.department.contains(_searchController.text);
      final matchesCareer = _selectedCareer == '전체' || u.careerCategory == _selectedCareer;
      return matchesSearch && matchesCareer;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('대학 탐색')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SupportBanner(),
              const SizedBox(height: 12),
              const ExampleBadge(),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: '대학명·학과명 검색',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: careers.map((c) {
                  final selected = _selectedCareer == c;
                  return ChoiceChip(
                    label: Text(c),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCareer = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text('진로 분야 선택 UI', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final u = filtered[index];
                    return Card(
                      child: ListTile(
                        title: Text(u.name),
                        subtitle: Text('${u.department} • ${u.careerCategory}'),
                        trailing: Text('등록금 ${u.tuition ~/ 10000}만원'),
                      ),
                    );
                  },
                ),
              ),
              const Text('모집요강은 2028학년도부터 지원됩니다', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
