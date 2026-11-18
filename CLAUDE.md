# Univ Pathfinder — Claude 작업 지침

고등학생의 내신·모의고사·생활기록부를 바탕으로 대학·학과 상담을 제공하고, 관심 대학 5~10개의 모집정보·등록금·통학 거리를 비교하는 Flutter(웹 우선) 앱.
스택: Flutter/Dart, Supabase(Auth·PostgreSQL·RLS·Edge Functions), Kakao Maps JS SDK, PDF.js + Tesseract.js(브라우저 로컬 OCR), NVIDIA Nemotron OCR(서버 경유).
(옛 `.clinerules/01-project-rules.md`를 옮겨 현재 상태에 맞게 고침. 원본은 git 기록 `v0.1.0-dev.2`에 있음)
제품 요구사항과 구현 현황: `PRD.md`, 다음 순서: `docs/NEXT_STEPS.md`, 단계별 기록: `DEVELOPMENT_LOG.md`.

## 앱의 목적 (우선순위 판단 기준)
학생의 성적·생기부로 **지원 가능한 대학을 찾고**, **전형별 정보·등록금**과 **근거를 밝힌 합격 가능성 예측**을 제공한다. 다음 작업을 고를 때 이 목적(특히 성적 기반 후보 판정과 예측)에 가장 가까운 일을 우선한다. 데이터 정확도 작업은 예측에 쓰이는 데이터부터 한다.

## 절대 규칙
- **`성적표/` 폴더는 실제 학생 개인정보다. 내용을 읽거나 출력하거나 외부로 보내지 않는다.** (.gitignore 처리됨)
- **`lib/test/rls_verification_test.dart`는 원격 DB에 실제로 쓰므로 실행하지 않는다.** `tools/live_*`·`tools/ocr/live_*` 테스트(예: `live_account_deletion_test.mjs`, `ocr/live_report_browser.mjs`)도 원격 DB·외부 API를 쓰므로 사용자 승인 없이 실행하지 않는다.
- `.env.dev.json`, `supabase/.env.local`의 키 값은 출력·로그·소스·문서·커밋에 넣지 않는다.
- nearby_school_finder 프로젝트와 작업 공간 밖의 파일은 수정·이동·삭제하지 않는다.

## 개인정보·보안
- 이름, 생년월일, 학번, 학교명, 상세 집 주소를 필수로 수집하지 않는다.
- 인증은 **닉네임 + 숫자 4자리 비밀번호**(Edge Function `nickname-auth`)다. 자세한 내용은 `docs/NICKNAME_AUTH.md`.
- 성적표 업로드 전 식별정보 제거를 안내한다. 원본은 DB·Storage에 영구 저장하지 않는다.
- 성적 데이터 접근은 사용자별 RLS로 제한한다.
- AI/OCR 비밀키는 클라이언트에 넣지 않고 서버(Supabase Secret)에서 관리한다.
- 집 위치(출발지)는 서버에 저장하지 않는다.
- AI·OCR 추출 결과는 사용자가 원본과 대조·수정한 뒤 저장한다.

## 개발 절차
- 기능은 작은 단계로 나눠 하나씩 구현한다. 각 단계마다 변경 파일, 구현 내용, 테스트 결과를 한국어로 보고한다.
- 다음 작업 전에는 사용자 승인을 받는다: 패키지 설치, 외부 API 호출, DB 스키마 변경·원격 DB 쓰기, 파일 삭제, push, 배포.
- 테스트 데이터는 가상 학생·가상 성적표만 쓴다.
- 성적 계산은 검증 가능한 공식으로 구현한다. AI가 수치를 추정하지 않는다. 원본에 없는 값은 null로 둔다.
- 모의고사 지표(표준점수·백분위·등급)를 내신 석차등급과 섞어 평균하지 않는다.
- 모집요강·등록금에는 공식 출처, 학년도, 확인일, 검증 상태를 함께 기록한다.
- 합격 가능성은 예측하되 보장·단정하지 않는다. 예측마다 비교한 과거 입결(학년도·지표·인원)·신뢰도·한계를 함께 보여 준다. 자료가 부족하면 "판단 불가·자료 부족"으로 표시한다.
- 단계를 마치면 `DEVELOPMENT_LOG.md`에 다음 번호(현재 98 다음)로 기록하고, 필요하면 `docs/NEXT_STEPS.md`를 갱신한다.

## 실행·검증 명령
```powershell
# 앱 실행 (Windows): .env.dev.json 있으면 개발 DB 모드, 없으면 체험 모드. 주소 http://localhost:8080 고정(카카오 도메인 등록)
run_app.bat

# 체험 모드 직접 실행
flutter run -d chrome --web-hostname=localhost --web-port=8080 --dart-define=DEMO_MODE=true

# 정적 분석
# ⚠ flutter analyze --no-pub 는 이 환경에서 분석 서버가 크래시(exit 255)한다.
#   원인: 프로젝트 경로의 한글("26년2학기", "AI 기반 코딩") → LSP JSON 길이 계산 오류(FormatException: Unterminated string).
#   대신 아래 명령을 쓴다 (같은 분석기·같은 analysis_options.yaml 적용).
dart analyze lib test

# 로컬 테스트 (원격 DB 쓰지 않음)
flutter test --no-pub test lib/models/extraction_result_test.dart

# 웹 빌드 확인
flutter build web --no-pub --dart-define=DEMO_MODE=true

# 진학 컨설팅 리포트 브라우저 점검 (가상 학생, DB·외부 호출 없음, 실제 번들 데이터 사용)
flutter build web --no-pub -t tools/preview_report_web.dart -o build/report-preview
node tools/ocr/report_smoke.mjs   # 스크린샷·인쇄 PDF: tools/ocr/test-output/design/report-*

# ⚠ 로그인 경로 실제 점검: 개발 DB에 가상 계정·가상 성적을 쓰고 끝에 삭제한다. 사용자 승인 후에만 실행.
flutter build web --no-pub --dart-define-from-file=.env.dev.json -o build/dev-check
node tools/ocr/live_report_browser.mjs
```

## 폴더 구조
```
lib/
  main.dart              앱 진입점
  models/                성적·모의고사·생기부·대학 카탈로그 등 데이터 모델
  screens/               화면 (일부 *_v2 중복 존재 — 정리는 후속 과제)
  services/              Supabase 연동, OCR 파서, 추천·비교·수능최저 계산, 카카오 브리지
                         (*_web.dart / *_stub.dart = 웹/비웹 조건부 import 쌍)
  theme/app_theme.dart   공통 테마
  widgets/               공통 위젯
  test/                  ⚠ rls_verification_test.dart (원격 DB 쓰기, 실행 금지)
test/                    로컬 단위·위젯 테스트, fixtures/ = 가상 OCR 결과
assets/data/             2028 전형계획·입결 비교·등록금 JSON 번들
assets/samples/          가상 성적표 PDF
web/                     index.html, grade_ocr.js·kakao_map.js 등 JS 브리지, vendor/ocr(PDF.js·Tesseract 정적 파일)
supabase/sql/            DB 마이그레이션 001~008 (순서대로 적용)
supabase/functions/      Edge Functions: nickname-auth, nemotron-ocr, commute-times, delete-account, app-help(도움말 챗봇, 지식 베이스는 node tools/build_help_kb.mjs로 생성)
tools/                   데이터 빌드 스크립트(*.mjs), live_* 원격 검증, ocr/ 브라우저 스모크 테스트
docs/                    기능별 설계·제한 문서 (NEXT_STEPS.md = 다음 개발 순서)
성적표/                  ⛔ 실제 개인정보 — 접근 금지
```

## 알려진 후속 과제 (사용자가 나중에 진행)
- `_v2` 화면 중복 정리, `lib/` 안의 테스트 파일(`lib/models/extraction_result_test.dart`, `lib/services/extraction_service_test.dart`, `lib/test/`) 정리.
- 프로젝트를 영문 경로로 옮기면 `flutter analyze` 크래시가 해소될 것으로 예상.

## Git
- `main`에서 작업하거나 `feature/기능명` 브랜치를 쓴다. 커밋 메시지는 한국어, 기능 단위로 나눈다.
- 개발 태그는 `v0.1.0-dev.N`으로 올린다. 현재 `v0.1.0-dev.3`.
- push는 사용자 승인 후에만 한다.
