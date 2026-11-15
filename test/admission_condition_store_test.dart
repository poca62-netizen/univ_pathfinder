import 'package:flutter_test/flutter_test.dart';
import 'package:univ_pathfinder/services/admission_condition_store.dart';
import 'package:univ_pathfinder/models/admission_catalog.dart';

import 'university_recommendation_test.dart' as fixtures;

void main() {
  test('재생성 후 표시 복원·계정 분리·해제 상태 유지', () async {
    final storage = <String, String>{};
    AdmissionConditionStore store(String uid) => AdmissionConditionStore(
      uid,
      read: (k) async => storage[k],
      write: (k, v) async {
        storage[k] = v;
      },
    );
    final key = AdmissionConditionStore.checkKey(fixtures.track('가상대'), '지원자격');
    await store('alice').save({key: true});
    expect(await store('alice').load(), {key: true});
    expect(await store('bob').load(), isEmpty);
    await store('alice').save({key: false});
    expect(await store('alice').load(), {key: false});
    expect(await store('').load(), isEmpty);
    await expectLater(store('').save({key: true}), throwsStateError);
  });
  test('전형 원문 변경·다른 조건은 기존 확인을 재사용하지 않음', () {
    final original = fixtures.track('가상대');
    final changed = AdmissionTrack(
      university: original.university,
      department: original.department,
      type: original.type,
      name: original.name,
      quota: original.quota,
      eligibility: '졸업예정자만',
      recommendation: original.recommendation,
      recommender: original.recommender,
      selection: original.selection,
      minimum: original.minimum,
      section: original.section,
    );
    expect(
      AdmissionConditionStore.checkKey(original, '지원자격'),
      isNot(AdmissionConditionStore.checkKey(changed, '지원자격')),
    );
    expect(
      AdmissionConditionStore.checkKey(original, '지원자격'),
      isNot(AdmissionConditionStore.checkKey(original, '학교장 추천')),
    );
  });
  test('깨진 저장 값과 쓰기 실패를 성공으로 취급하지 않음', () async {
    final corrupted = AdmissionConditionStore(
      'alice',
      read: (_) async => '[true]',
    );
    await expectLater(corrupted.load(), throwsFormatException);
    final invalid = AdmissionConditionStore(
      'alice',
      read: (_) async => '{"key":"true"}',
    );
    await expectLater(invalid.load(), throwsFormatException);
    final failed = AdmissionConditionStore(
      'alice',
      write: (_, _) async => throw StateError('storage denied'),
    );
    await expectLater(failed.save({'key': true}), throwsStateError);
  });
}
