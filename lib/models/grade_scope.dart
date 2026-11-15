/// Scope of school grades used by this app. Document section headings take
/// precedence; known excluded subject names also protect manual/legacy records.
class GradeScope {
  static String compact(String value) => value.replaceAll(RegExp(r'\s'), '');
  static bool isExcludedSubject(String value) =>
      RegExp(r'^(체육|음악|미술|과학탐구실험|교양교과|운동과건강|스포츠생활)').hasMatch(compact(value));
  static bool isExcludedSection(String value) =>
      RegExp(r'체육[·ㆍ/·\s]*예술과목|체육.*예술.*과목|교양교과|과학탐구실험$')
          .hasMatch(compact(value));
  static bool isIncludedSection(String value) =>
      RegExp(r'보통교과|전문교과').hasMatch(compact(value));
}
