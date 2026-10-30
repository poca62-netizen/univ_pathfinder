import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/example_university.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class FavoritesSettingsScreen extends StatefulWidget {
  const FavoritesSettingsScreen({super.key});

  @override
  State<FavoritesSettingsScreen> createState() => _FavoritesSettingsScreenState();
}

class _FavoritesSettingsScreenState extends State<FavoritesSettingsScreen> {
  final TextEditingController _nicknameController = TextEditingController(text: '익명사용자');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 및 설정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const ExampleBadge(),
              const SizedBox(height: 16),
              const Text('관심 대학 목록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...exampleUniversities.take(3).map((u) => Card(
                    child: ListTile(
                      title: Text(u.name),
                      subtitle: Text(u.department),
                      trailing: const Icon(Icons.favorite_border),
                    ),
                  )),
              const SizedBox(height: 24),
              const Text('닉네임 변경', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('닉네임 변경은 UI 프로토타입입니다')),
                  );
                },
                child: const Text('변경 저장'),
              ),
              const SizedBox(height: 24),
              const Text('데이터 삭제 안내', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '실제 DB 삭제 기능은 아직 구현하지 않았습니다. 프로토타입에서는 안내만 제공합니다.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('삭제 안내만 표시됩니다')),
                  );
                },
                child: const Text('데이터 삭제'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
