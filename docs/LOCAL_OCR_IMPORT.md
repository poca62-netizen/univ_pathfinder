# PDF·이미지에서 내신 성적을 저장하는 방법

구현일: 2026-11-01. 외부 생성형 AI·OCR API 없이 브라우저 안에서 처리한다.

## 사용자 흐름

1. `flutter run -d chrome --dart-define-from-file=.env.dev.json`으로 앱을 다시 실행한다. `web/index.html`과 JS가 추가되어 기존 실행 창의 hot reload만으로는 연결되지 않을 수 있다.
2. 닉네임으로 시작한 뒤 상담 자료에서 내신 중간·기말을 선택한다.
3. 원본의 학년·학기·기록 연도를 확인하고 JPG/JPEG/PNG/PDF를 선택한다.
4. **성적 추출 → 확인·수정**을 누른다. PDF 텍스트가 부족한 페이지는 자동 OCR 처리한다. 텍스트 레이어가 잘못된 PDF는 **PDF를 이미지로 다시 인식**을 사용할 수 있다.
5. 추출 원문·경고를 확인하고 과목명, 학점/단위, 원점수, 평균, 성취도, 석차등급을 원본과 대조한다. 누락 과목은 직접 추가한다. 학점이 없으면 추정하지 않고 사용자가 입력해야 한다.
6. 원본 대조 확인을 체크한 뒤 저장 확인 대화상자에서 저장한다. 본인 `grade_records`에 배치 저장되고 성적 분석 화면에서 재조회한다.

원본 PDF·이미지·추출 원문은 DB에 저장하지 않는다. 현재 DB는 학년·학기·과목별 성적 구조로, 파일 기록 연도·중간/기말 구분·원본 페이지·확인 시각은 별도 영속 저장하지 않는다. 향후 문서 메타데이터 마이그레이션이 필요하다.

## 시험용 자료

- 앱의 **가상 PDF로 인식 시험 · 저장 안 됨**: 키 없이도 실제 JS 추출과 수정 화면을 확인한다. 내장 예시의 DB 저장은 차단한다.
- `assets/samples/sample_grades.pdf`: 가상 2학년 1학기 국어·수학 성적표. 실제 학생 정보는 없다.
- 일반 모드에서 가상 파일을 직접 선택하면 기존 사용자 계정의 DB 저장도 시험할 수 있다. 체험 모드는 로그인·DB 저장을 제공하지 않는다.

## 구현 구조

| 파일 | 역할 |
| --- | --- |
| `web/grade_ocr.js` | PDF.js 텍스트/위치 추출, 스캔 페이지 렌더링, Tesseract OCR, 표 선 전처리·크기 제한·취소·자원 해제 |
| `web/vendor/ocr/` | PDF.js 6.4.299, Tesseract.js 7.0.0, 엔진·한국어/영어 모델·PDF 폰트/문자맵. 총 약 56MB. 원본 파일을 CDN에 보내지 않도록 같은 출처에서 로드 |
| `lib/services/local_ocr*.dart` | Dart JS interop 및 웹 외 플랫폼 안내 |
| `lib/services/grade_file_import_service.dart` | 파일 인식 결과를 성적 파서로 전달 |
| `lib/services/grade_import_parser.dart` | 머리글·열 위치 기준 과목 매핑. 불확실 값은 null·경고로 표시 |
| `lib/screens/grade_upload_file_screen_v2.dart` | 파일·자료 종류 선택, 진행 상태·취소·예시·확인 화면 연결 |
| `lib/screens/grade_extraction_review_screen_v2.dart` | 원문·경고·편집·필수 검증·대조 확인·저장 확인 |
| `lib/services/grade_service.dart` | 인증 UID 주입, 허용 컬럼만 전송, 값 검증 및 안정적인 요청 UUID 기반 upsert |

기존 추상 AI `ExtractionService`와 가상 서비스는 유지한다. 새 로컬 파일 경로는 외부 AI API를 사용하지 않는다.

## 지원 범위와 정확도

- PDF 최대 20MiB·20쪽, 이미지 최대 5MiB. 암호 PDF는 잠금 해제한 사본이 필요하다.
- 표 머리글로 과목·학점/단위·원점수·평균·성취도·등급을 구분한다. 원점수/과목평균(표준편차), 성취도(수강자수) 형태도 지원한다.
- OCR은 원본 품질·회전·글꼴·표 구조에 영향을 받는다. 가상 예시에서도 `A`가 `^`로 읽힌 경우가 있었다. 이를 A로 추측하지 않고 누락·경고를 표시한다. 정확도 100%를 보장하지 않는다.
- 사진 인식 개선: 원본을 고정 폭 1800px로 축소하지 않고 짧은 변·긴 변·총 화소 제한을 함께 사용한다. 원본을 보존한 복사본에서 표 선 제거, 원본 레이아웃, 대비 보정, 90/270/180도 회전을 순서대로 시험한다. 내신 파일은 강화 인식을 사용하며 머리글·인식 신뢰도가 충분한 결과가 나오면 조기에 종료한다. 인식이 어려운 사진은 처리 시간이 더 걸릴 수 있고 취소할 수 있다.
- 처음부터 과목을 찾지 못한 상태와 사용자가 모든 과목을 제외한 상태를 구분한다. 추출 실패 화면에서 파일을 다시 선택할 수 있다. 원본 사진을 확보하지 못한 사례는 해당 사진의 인식 성공을 검증했다고 기록하지 않는다.
- 회색 바탕·흰 글씨 머리글이 있는 통지표는 표 경계를 찾고 칸별 밝기를 정규화해 읽는 경로를 추가했다. 과목·머리글은 한국어, 점수는 숫자 전용 엔진으로 읽는다. 받은점수·합계·석차·수강자수는 내신 원점수·석차등급으로 대체하지 않는다. 알려진 통지표 구조에서 과목명 괄호의 수치를 학점 후보로 표시하며 사용자 대조를 요구한다. 원문에서 학년·학기를 읽었을 때 선택값과 다르면 경고한다.
- 실제 첨부 사진에서 6개 과목 후보를 추출했으나 일부 숫자에 범위 오류가 남았다. 이후 추가 검증 명령 실행이 승인되지 않아 최종 정확도·회귀 검증은 미완료다. 학생 원본의 결과는 가상 시험 자료와 분리해 취급하고 DB에 쓰지 않았다.
- 인식하지 못한 표는 원문 확인과 과목 직접 추가를 제공한다. 성취도별 분포비율은 현재 자동 매핑하지 않으며 원본에서 확인해 입력할 수 있다.
- 모의고사·생기부는 글자 추출만 제공한다. 분류가 내신이어도 표준점수·백분위 등 모의고사 지표나 명시적인 9등급 체계를 감지하면 내신 자동 저장을 막는다. 현재 SQL의 석차등급 범위는 1~5다.
- 학년·학기는 사용자가 지정한 기본값을 사용한다. 표에 명시된 학년/학기 열이 있으면 그 값을 사용하므로 다학기 자료에서는 각 과목의 시기를 확인해야 한다.
- 같은 검토 화면의 재시도는 동일 UUID로 저장해 서버 PK 기준 중복 행 생성을 방지한다. 파일을 새로 열어 별도 검토를 시작한 경우까지 중복 파일을 판별하지는 않는다.
- Supabase 인증·RLS·네트워크 설정이 정상이어야 실제 저장할 수 있다. 서버 스키마는 변경하지 않았다.

## 개발 도구와 재현

```powershell
cd tools/ocr
npm ci --ignore-scripts --no-audit --no-fund
npm run vendor
npm test
```

버전·해시는 `tools/ocr/package-lock.json`에 고정했다. `node_modules`와 브라우저 시험 출력은 Git에서 제외한다. `web/vendor/ocr`은 앱 실행에 필요한 배포 자산으로 포함한다. 원본 라이브러리 LICENSE와 언어 패키지 메타데이터를 보존한다.

```powershell
# 프로젝트 루트에서 네트워크 없는 모델·화면·DB 요청 테스트
flutter test --no-pub test lib/models/extraction_result_test.dart
dart analyze lib test tools/live_grade_import_test.dart

# 체험 빌드와 실제 Chrome 앱 연결 시험
flutter build web --no-pub --no-web-resources-cdn --dart-define=DEMO_MODE=true
cd tools/ocr
node flutter_smoke.mjs
```

브라우저 시험은 현재 PC의 Chrome 경로를 사용한다. 다른 OS는 `browser.test.mjs`, `flutter_smoke.mjs`의 실행 파일 경로를 조정한다.

`tools/live_grade_import_test.dart`는 원격 DB 쓰기가 있는 명시적 통합 검증이다. 기본 `test/` 실행에 포함하지 않는다. 실행 시 검증용 익명 Auth 사용자 1개를 생성하고 가상 성적·프로필 행을 저장·조회·삭제한다. Auth 사용자 자체 삭제는 관리자 권한이 필요하므로 이 도구에서는 수행하지 않는다. 키·토큰·원본 예외를 출력하지 않는다.

## 공식 기술 자료

- [PDF.js API](https://mozilla.github.io/pdf.js/api/draft/module-pdfjsLib-PDFPageProxy.html)
- [PDF.js 렌더링 예제](https://mozilla.github.io/pdf.js/examples/)
- [Tesseract.js API](https://github.com/naptha/tesseract.js/blob/master/docs/api.md)
- [Tesseract.js 로컬 구성](https://github.com/naptha/tesseract.js/blob/master/docs/local-installation.md)


## PDF 용량 제한 변경 (2026-11-04)

PDF는 최대 20MB·20쪽, 이미지는 기존 5MB까지 허용합니다. 파일 선택 화면·인식 서비스·브라우저 JS에서 같은 형식별 제한을 적용합니다. 생활기록부 PDF도 브라우저에서 처리하며 NVIDIA 서버로 보내지 않습니다. 8MB 가상 PDF의 로컬 텍스트 추출과 초과 PDF/이미지 차단을 검증했습니다. 실제 사용자 파일이 암호화되었거나 20쪽을 넘는 경우는 별도로 처리해야 합니다.
