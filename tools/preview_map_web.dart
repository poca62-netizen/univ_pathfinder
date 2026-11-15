import 'package:flutter/material.dart';
import 'package:univ_pathfinder/models/counseling_session.dart';
import 'package:univ_pathfinder/screens/university_map_screen.dart';
import 'package:univ_pathfinder/theme/app_theme.dart';

void main() {
  CounselingSession.instance.toggleCatalogUniversity('서울대');
  CounselingSession.instance.toggleCatalogUniversity('연세대(서울)');
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PathfinderTheme.light,
      home: const UniversityMapScreen(),
    ),
  );
}
