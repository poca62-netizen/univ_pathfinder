import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/home_screen.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const AppTitle(title: 'Univ Pathfinder'),
              const SizedBox(height: 8),
              const SupportBanner(),
              const SizedBox(height: 32),
              const Text(
                '대입 수험생을 위한 AI 기반 대학 진학 정보 분석 앱',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text(
                '성적표 업로드, 대학 모집요강 검색, 등록금 비교, 통학 거리 비교를 단계적으로 지원합니다.',
                style: TextStyle(fontSize: 14),
              ),
              const Spacer(),
              const Text('닉네임 입력', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  hintText: '닉네임을 입력하세요',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '개인정보 최소 수집 안내: 닉네임은 화면 표시용이며 인증 수단으로 사용하지 않습니다. 성적표 업로드 전 식별정보 제거를 안내합니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final nickname = _nicknameController.text.trim();
                          if (nickname.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('닉네임을 입력해주세요')),
                            );
                            return;
                          }
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          try {
                            final supabase = Supabase.instance.client;
                            if (supabase.auth.currentUser == null) {
                              await supabase.auth.signInAnonymously();
                            }
                            final userId = supabase.auth.currentUser?.id;
                            if (userId == null) {
                              throw Exception('사용자 인증 정보를 가져올 수 없습니다.');
                            }
                            // 개발 확인용: 사용자 ID만 표시, 토큰은 출력하지 않음
                            debugPrint('Auth success, userId=$userId');

                            // 닉네임 저장: 기존 프로필 있으면 업데이트, 없으면 생성
                            await supabase.from('profiles').upsert(
                              {
                                'id': userId,
                                'nickname': nickname,
                              },
                              onConflict: 'id',
                            );

                            if (!mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HomeScreen(nickname: nickname),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            final message = '닉네임 저장에 실패했습니다. 잠시 후 다시 시도해 주세요.';
                            debugPrint('Save profile error: $e');
                            setState(() {
                              _errorMessage = message;
                              _isLoading = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(message)),
                            );
                          } finally {
                            if (mounted && _isLoading) {
                              // 네비게이션 발생 시 상태 갱신 방지
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('시작하기'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
