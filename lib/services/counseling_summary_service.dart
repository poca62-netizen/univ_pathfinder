import 'package:univ_pathfinder/models/counseling_summary.dart';
import 'package:univ_pathfinder/models/grade_record.dart';
import 'package:univ_pathfinder/models/mock_exam_record.dart';
import 'package:univ_pathfinder/models/school_record_evidence.dart';
import 'package:univ_pathfinder/services/grade_service.dart';
import 'package:univ_pathfinder/services/mock_exam_service.dart';
import 'package:univ_pathfinder/services/school_record_service.dart';

class CounselingSummaryService {
  CounselingSummaryService({
    Future<List<GradeRecord>> Function()? loadGrades,
    Future<List<MockExamRecord>> Function()? loadMockExams,
    Future<List<SchoolRecordEvidence>> Function()? loadActivities,
  }) : _grades = loadGrades ?? GradeService.instance.fetchMyGrades,
       _mocks = loadMockExams ?? MockExamService.instance.fetch,
       _activities = loadActivities ?? SchoolRecordService.instance.fetch;
  final Future<List<GradeRecord>> Function() _grades;
  final Future<List<MockExamRecord>> Function() _mocks;
  final Future<List<SchoolRecordEvidence>> Function() _activities;
  Future<SummarySection<T>> _load<T>(Future<List<T>> Function() loader) async {
    try {
      return SummarySection(await loader());
    } catch (_) {
      return SummarySection([], failed: true);
    }
  }

  Future<CounselingSummary> fetch() async {
    // Each source retains its own failure state; a failed query is not an empty source.
    final grades = _load(_grades),
        mocks = _load(_mocks),
        activities = _load(_activities);
    return CounselingSummary(
      grades: await grades,
      mockExams: await mocks,
      activities: await activities,
    );
  }
}
