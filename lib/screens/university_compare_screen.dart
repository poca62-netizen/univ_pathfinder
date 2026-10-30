import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/example_university.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class UniversityCompareScreen extends StatefulWidget {
  const UniversityCompareScreen({super.key});

  @override
  State<UniversityCompareScreen> createState() => _UniversityCompareScreenState();
}

class _UniversityCompareScreenState extends State<UniversityCompareScreen> {
  final List<ExampleUniversity> _selected = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('대학 비교')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExampleBadge(),
              const SizedBox(height: 8),
              const Text('대학 2~3곳 선택', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: exampleUniversities.length,
                  itemBuilder: (context, index) {
                    final u = exampleUniversities[index];
                    final selected = _selected.contains(u);
                    return CheckboxListTile(
                      title: Text(u.name),
                      subtitle: Text(u.department),
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true && _selected.length < 3) {
                            _selected.add(u);
                          } else if (v == false) {
                            _selected.remove(u);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text('비교 항목 UI', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: _selected.isEmpty
                    ? const Center(child: Text('대학을 2~3곳 선택하세요'))
                    : ListView(
                        children: _selected.map((u) => Card(
                          child: ListTile(
                            title: Text(u.name),
                            subtitle: Text('등록금 ${u.tuition ~/ 10000}만원 • 기준연도 ${u.referenceYear}\n모집요강: 예시 미연동\n통학거리: 예시 미연동'),
                          ),
                        )).toList(),
                      ),
              ),
              const Text('실제 데이터가 없으면 예시로 표시합니다. 실제 기준을 임의로 생성하지 않습니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
