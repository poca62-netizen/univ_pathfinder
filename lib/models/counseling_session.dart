import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:univ_pathfinder/services/university_selection_store.dart';
import 'package:univ_pathfinder/models/example_university.dart';
import 'package:univ_pathfinder/models/map_location.dart';

enum StudentDocumentKind {
  midterm('내신 중간고사'),
  finalExam('내신 기말고사'),
  semesterSummary('내신 학기 종합'),
  mockExam('모의고사'),
  schoolRecord('생활기록부');

  const StudentDocumentKind(this.label);
  final String label;
  bool get isSchoolGrade =>
      this == midterm || this == finalExam || this == semesterSummary;
}

class StudentDocument {
  const StudentDocument({
    required this.kind,
    required this.schoolYear,
    required this.calendarYear,
    required this.fileName,
    this.semester,
    this.examMonth,
  });

  final StudentDocumentKind kind;
  final int schoolYear;
  final int calendarYear;
  final int? semester;
  final int? examMonth;
  final String fileName;

  String get period => switch (kind) {
    StudentDocumentKind.mockExam => '$calendarYear년 $schoolYear학년 $examMonth월',
    StudentDocumentKind.schoolRecord => '$calendarYear년 $schoolYear학년',
    _ => '$calendarYear년 $schoolYear학년 $semester학기',
  };

  bool get isValid =>
      schoolYear >= 1 &&
      schoolYear <= 3 &&
      calendarYear >= 2000 &&
      calendarYear <= 2100 &&
      fileName.trim().isNotEmpty &&
      switch (kind) {
        StudentDocumentKind.mockExam =>
          examMonth != null && examMonth! >= 1 && examMonth! <= 12,
        StudentDocumentKind.schoolRecord => true,
        _ => semester == 1 || semester == 2,
      };
}

class GeoPoint {
  GeoPoint(this.latitude, this.longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('올바른 위도·경도를 입력하세요.');
    }
  }
  final double latitude;
  final double longitude;

  double distanceKmTo(GeoPoint other) {
    double radians(double degrees) => degrees * math.pi / 180;
    final lat = radians(other.latitude - latitude);
    final lon = radians(other.longitude - longitude);
    final a =
        math.pow(math.sin(lat / 2), 2) +
        math.cos(radians(latitude)) *
            math.cos(radians(other.latitude)) *
            math.pow(math.sin(lon / 2), 2);
    return 6371.0088 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

/// 파일 목록은 세션 전용이다. 실제 대학 선택만 명시적으로 기기에 저장한다.
/// 주소·문서를 서버에 저장하지 않는다.
class CounselingSession extends ChangeNotifier {
  static final instance = CounselingSession();
  final List<StudentDocument> _documents = [];
  final List<ExampleUniversity> _selected = [];
  final Set<String> _catalogSelection = {};
  Set<String> get catalogSelection => Set.unmodifiable(_catalogSelection);
  UniversitySelectionStore? _selectionStore;
  int _selectionEpoch = 0;
  bool selectionBusy = false;
  bool selectionDirty = false;
  String? selectionError;
  String? selectionStatus;
  bool _selectionRestored = false;

  Future<void> restoreSelection(
    UniversitySelectionStore store, {
    bool retry = false,
  }) async {
    if (_selectionStore?.userId == store.userId &&
        !retry &&
        (selectionBusy || _selectionRestored || selectionError != null)) {
      return;
    }
    if (_selectionStore?.userId != store.userId) {
      _catalogSelection.clear();
      selectionDirty = false;
    }
    _selectionStore = store;
    final epoch = ++_selectionEpoch;
    selectionBusy = true;
    selectionError = null;
    selectionStatus = null;
    notifyListeners();
    try {
      final names = await store.load();
      if (epoch != _selectionEpoch) return;
      _catalogSelection
        ..clear()
        ..addAll(names);
      _selectionRestored = true;
      selectionDirty = false;
    } catch (_) {
      if (epoch != _selectionEpoch) return;
      selectionError = '관심 대학을 복원하지 못했습니다. 다시 불러온 뒤 변경하세요.';
    } finally {
      if (epoch == _selectionEpoch) {
        selectionBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveSelection() async {
    final store = _selectionStore;
    if (store == null || selectionBusy || selectionError != null) return;
    final epoch = _selectionEpoch;
    selectionBusy = true;
    selectionStatus = null;
    notifyListeners();
    try {
      await store.save(catalogSelection);
      if (epoch != _selectionEpoch) return;
      selectionDirty = false;
      selectionStatus = '이 기기에 관심 대학을 저장했습니다.';
    } catch (_) {
      if (epoch != _selectionEpoch) return;
      selectionStatus = '저장하지 못했습니다. 선택을 유지했으니 다시 시도하세요.';
    } finally {
      if (epoch == _selectionEpoch) {
        selectionBusy = false;
        notifyListeners();
      }
    }
  }

  bool toggleCatalogUniversity(String name) {
    if (selectionBusy || selectionError != null) return false;
    if (_catalogSelection.contains(name)) {
      _catalogSelection.remove(name);
    } else {
      if (_catalogSelection.length >= 10) return false;
      _catalogSelection.add(name);
    }
    selectionDirty = true;
    selectionStatus = null;
    notifyListeners();
    return true;
  }

  GeoPoint? _origin;
  MapLocation? mapOrigin;
  final mapDestinations = <String, MapDestination>{};

  List<StudentDocument> get documents => List.unmodifiable(_documents);
  List<ExampleUniversity> get selected => List.unmodifiable(_selected);
  GeoPoint? get origin => _origin;

  bool addDocument(StudentDocument document) {
    if (!document.isValid) throw ArgumentError('자료의 학년·시기 정보를 확인하세요.');
    if (_documents.any(
      (d) =>
          d.kind == document.kind &&
          d.schoolYear == document.schoolYear &&
          d.calendarYear == document.calendarYear &&
          d.semester == document.semester &&
          d.examMonth == document.examMonth &&
          d.fileName == document.fileName,
    )) {
      return false;
    }
    _documents.add(document);
    notifyListeners();
    return true;
  }

  void removeDocument(StudentDocument document) {
    _documents.remove(document);
    notifyListeners();
  }

  void clearAcademicDocuments() {
    _documents.clear();
    notifyListeners();
  }

  bool contains(ExampleUniversity university) =>
      _selected.any((u) => u.name == university.name);

  bool toggle(ExampleUniversity university) {
    if (contains(university)) {
      _selected.removeWhere((u) => u.name == university.name);
    } else {
      if (_selected.length >= 10) return false;
      _selected.add(university);
    }
    notifyListeners();
    return true;
  }

  void setOrigin(GeoPoint? point) {
    _origin = point;
    notifyListeners();
  }

  void clear() {
    _selectionEpoch++;
    _selectionStore = null;
    _selectionRestored = false;
    selectionBusy = false;
    selectionDirty = false;
    selectionError = null;
    selectionStatus = null;
    _documents.clear();
    _selected.clear();
    _catalogSelection.clear();
    mapOrigin = null;
    mapDestinations.clear();
    _origin = null;
    notifyListeners();
  }
}
