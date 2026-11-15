import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/screens/university_recommendation_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';
import 'package:univ_pathfinder/services/university_recommendation_service.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';
import 'package:univ_pathfinder/models/university_outlook.dart';

import '../test/admission_comparison_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final korean = FontLoader('PreviewKorean');
    korean.addFont(
      Future.value(
        ByteData.sublistView(
          await File('C:/Windows/Fonts/malgun.ttf').readAsBytes(),
        ),
      ),
    );
    await korean.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes(),
        ),
      ),
    );
    await icons.load();
  });
  for (final entry in {
    'desktop': const Size(1440, 1100),
    'mobile': const Size(390, 844),
    'large-text': const Size(390, 900),
  }.entries) {
    testWidgets('candidate visual ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = PathfinderTheme.light;
      final service = UniversityRecommendationService();
      final loaded = await tester.runAsync(
        () => Future.wait<Object>([
          service.loadCatalog(),
          service.loadTuition(),
          service.loadComparison(),
        ]),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: 'PreviewKorean'),
              appBarTheme: base.appBarTheme.copyWith(
                titleTextStyle: base.appBarTheme.titleTextStyle!.copyWith(
                  fontFamily: 'PreviewKorean',
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: base.filledButtonTheme.style!.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    base.filledButtonTheme.style!.textStyle!
                        .resolve({})!
                        .copyWith(fontFamily: 'PreviewKorean'),
                  ),
                ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  entry.key == 'large-text' ? 1.4 : 1,
                ),
              ),
              child: child!,
            ),
            home: UniversityRecommendationScreen(
              loadSummary: () async => fixtures.profile([1, 1, 1, 1, 1, 1]),
              loadCatalog: () async => loaded![0] as AdmissionCatalog,
              loadTuition: () async => loaded![1] as TuitionCatalog,
              loadComparison: () async => loaded![2] as Map<String, dynamic>,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '관심 학과·분야'),
        '컴퓨터공학',
      );
      final button = find.widgetWithText(FilledButton, '등록 자료로 10개 대학 보기');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      if (entry.key == 'desktop') {
        final scrollable = find.byType(Scrollable).first;
        final state = tester.state<ScrollableState>(scrollable);
        state.position.jumpTo(0);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('preview')),
        matchesGoldenFile('ocr/test-output/design/candidates-${entry.key}.png'),
      );
    });
  }
}
