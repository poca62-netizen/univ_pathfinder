import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:univ_pathfinder/screens/start_screen.dart';
import 'package:univ_pathfinder/screens/home_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const demoMode = bool.fromEnvironment('DEMO_MODE');

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  if (!demoMode) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  runApp(const UnivPathfinderApp(demoMode: demoMode));
}

class UnivPathfinderApp extends StatelessWidget {
  const UnivPathfinderApp({super.key, this.demoMode = false});
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Univ Pathfinder',
      debugShowCheckedModeBanner: false,
      theme: PathfinderTheme.light,
      home: demoMode
          ? const HomeScreen(nickname: '체험 사용자', demoMode: true)
          : const StartScreen(),
    );
  }
}
