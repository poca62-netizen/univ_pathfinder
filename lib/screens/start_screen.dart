import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:univ_pathfinder/services/nickname_auth_service.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/home_screen.dart';
import 'package:univ_pathfinder/widgets/common_widgets.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.authenticate});
  final Future<String> Function(String, String, bool)? authenticate;
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _form = GlobalKey<FormState>();
  final _nickname = TextEditingController(), _pin = TextEditingController();
  bool _busy = false, _register = false;
  String? _error;
  @override
  void dispose() {
    _nickname.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nickname =
          await (widget.authenticate ??
              NicknameAuthService.instance.authenticate)(
            _nickname.text,
            _pin.text,
            _register,
          );
      _pin.clear();
      if (!mounted) return;
      CounselingSession.instance.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(nickname: nickname)),
      );
    } on NicknameAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '로그인하지 못했습니다. 잠시 후 다시 시도하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 40),
            const AppTitle(title: 'Univ Pathfinder'),
            const SizedBox(height: 8),
            const SupportBanner(),
            const SizedBox(height: 28),
            Text(
              _register ? '회원가입' : '닉네임으로 로그인',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text('같은 닉네임과 비밀번호로 로그인하면 앱을 다시 실행해도 저장한 성적을 불러옵니다.'),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nickname,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '닉네임',
                border: OutlineInputBorder(),
                helperText: '한글·영문·숫자·밑줄 2~20자 · 영문 대소문자 구분 없음',
              ),
              validator: (v) => NicknameAuthService.validateNickname(v ?? ''),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pin,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: '비밀번호 (숫자 4자리)',
                border: OutlineInputBorder(),
              ),
              validator: (v) => NicknameAuthService.validatePin(v ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_register)
              const Text(
                '닉네임은 중복 등록할 수 없습니다. 비밀번호를 잊었을 때 자동 복구하는 기능은 아직 없습니다.',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? '인증 중...'
                    : _register
                    ? '가입하고 시작하기'
                    : '로그인',
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _error = null;
                      _pin.clear();
                    }),
              child: Text(_register ? '이미 계정이 있어요 · 로그인' : '처음 사용하나요? 회원가입'),
            ),
            const SizedBox(height: 16),
            const Text(
              '비밀번호 5회 오류 시 15분 동안 로그인이 제한됩니다. 비밀번호는 화면에 표시하거나 기기에 따로 저장하지 않습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
