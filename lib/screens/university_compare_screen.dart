import 'package:flutter/material.dart';
import 'package:univ_pathfinder/screens/university_search_screen.dart';

class UniversityCompareScreen extends StatelessWidget {
  const UniversityCompareScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const UniversitySearchScreen(compare: true);
}
