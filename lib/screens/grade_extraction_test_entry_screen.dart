import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/extraction_result.dart';
import 'package:univ_pathfinder/services/extraction_service_test.dart';
import 'package:univ_pathfinder/screens/grade_extraction_review_screen_v2.dart';

class GradeExtractionTestEntryScreen extends StatelessWidget {
  const GradeExtractionTestEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('추출 테스트')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('이 화면은 개발 테스트용입니다. 실제 파일 인식 결과가 아닙니다. 저장 시에도 테스트 데이터가 사용되며, 실수로 실제 성적처럼 저장되지 않도록 주의하세요.', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final sample = ExtractionServiceTest.virtualSample();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => GradeExtractionReviewScreenV2(result: sample, isTest: true)),
                  );
                },
                child: const Text('가상 추출 결과 확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
