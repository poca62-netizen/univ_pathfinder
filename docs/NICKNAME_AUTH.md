# 닉네임·4자리 비밀번호 인증

적용일: 2026-11-04

## 사용

- 시작 화면에서 닉네임과 숫자 4자리 비밀번호로 로그인한다. 처음 사용하는 닉네임은 회원가입에서 등록한다.
- 닉네임은 한글·영문·숫자·밑줄 2~20자다. 앞뒤 공백을 제거하고 서버에서 NFKC 정규화 후 영문 소문자로 저장한다. 영문 대소문자를 달리해도 같은 닉네임이다.
- 기존 익명 계정에 입력했던 표시용 닉네임만으로 과거 자료를 자동 연결하지 않는다. 기존 계정 전환·자료 통합은 소유자 확인 후 관리자 작업으로 수행한다.
- 세션이나 개발 브라우저가 바뀌어도 같은 자격으로 다시 로그인하면 같은 사용자 ID로 연결된다. 홈에서 로그아웃할 수 있다.
- 자동 비밀번호 복구·재설정과 닉네임 변경은 아직 제공하지 않는다.

## 계정 삭제 (2026-11-15 구현, 원격 배포 전)

- 설정 → **계정 삭제**에서 4자리 비밀번호를 다시 입력하면 계정과 자료를 영구 삭제한다. 열린 브라우저를 다른 사람이 써도 PIN 없이는 지울 수 없다.
- `delete-account` Edge Function 처리 순서:
  1. `/auth/v1/user`로 요청한 세션의 사용자 ID를 확인한다. 요청 본문의 사용자 정보는 신뢰하지 않는다.
  2. IP 해시별 요청 제한을 적용한다(`nickname-auth`와 같은 버킷).
  3. 서버에서 그 사용자 ID의 `nickname_accounts.nickname_key`를 조회한다.
  4. `authenticate_nickname`으로 PIN을 검증한다. 결과 user_id가 세션 사용자와 같아야 한다. 실패는 기존 5회 잠금에 포함된다.
  5. 관리자 API로 Auth 사용자를 삭제한다. `profiles`, `grade_records`, `mock_exam_records`, `school_record_evidence`, `nickname_accounts`가 `on delete cascade`로 함께 삭제된다.
  6. `nickname_login_attempts`의 해당 닉네임 행을 지운다(실패해도 삭제 결과는 유지).
- 오류 코드: `AUTH`(401), `INPUT`(400), `INVALID_CREDENTIALS`(401), `LOCKED`·`RATE_LIMIT`(429), `NO_NICKNAME_ACCOUNT`(409, 닉네임 자격 없는 옛 익명 계정), `UNAVAILABLE`(503).
- 앱은 서버가 `{deleted: true}`를 돌려준 뒤에만 이 브라우저의 계정별 키 4종(`university_selection_v1`, `consulting_draft_v1`, `admission_conditions_v1`, `comparison_history_v1`)을 지우고 로컬 로그아웃 후 시작 화면으로 이동한다. 다른 기기의 브라우저 기록은 지우지 못한다.
- 삭제 후 같은 닉네임은 즉시 다시 가입할 수 있다.
- 배포(승인 후): `npx supabase functions deploy delete-account --project-ref <프로젝트ID> --no-verify-jwt` — 세션 검증은 함수 안에서 한다(`commute-times`와 같은 방식).

## 서버 계약

`005_nickname_auth.sql`과 `nickname-auth` Edge Function을 함께 사용한다. 함수는 인증 전 진입점이므로 게이트웨이 JWT 검사를 끄고 배포하며, 성적 서비스와 RLS는 기존 Supabase Auth 사용자 ID 기준을 유지한다.

- `nickname_accounts`: 정규화된 닉네임 PK, 사용자 ID UNIQUE, bcrypt PIN 해시(cost 12). 일반 클라이언트는 조회·변경할 수 없다.
- 등록·검증 RPC는 service_role만 실행한다. 가입 시 DB UNIQUE 제약으로 동시 중복도 차단한다. 중복 시 생성한 미사용 Auth 계정은 정리한다.
- 닉네임별 실패 5회 시 15분 잠금. IP 해시별 15분 30회 요청 제한. 성공 시 해당 닉네임 실패 횟수를 초기화한다.
- PIN 확인 후 서버에서 내부 Auth 계정의 일회용 링크를 생성·검증해 표준 Supabase 세션을 발급한다. 이메일을 발송하지 않는다. 내부 주소는 사용자 이메일이 아니며 임의로 생성한다.
- 앱은 반환된 refresh token으로 SDK 세션을 설정한다. PIN 원문·해시·관리자 키는 클라이언트에 저장하거나 응답으로 전달하지 않는다. 서버는 요청 본문·키·토큰을 로그로 남기지 않는다.
- 서버 기본 `SUPABASE_SERVICE_ROLE_KEY`는 서버에서만 사용한다. Flutter 설정·Git에 넣지 않는다.

공식 계약 참고: [Supabase Auth REST](https://supabase.github.io/auth/), [세션 설정](https://supabase.com/docs/reference/dart/auth-setsession).

## 배포

```powershell
npx supabase db query --remote=<프로젝트ID> --file supabase/sql/005_nickname_auth.sql --yes
npx supabase functions deploy nickname-auth --remote=<프로젝트ID> --no-verify-jwt --yes
```

현재 앱의 프로젝트에 배포 완료했다. 이 프로젝트는 CLI에서 production으로 표시하므로 후속 변경 전 대상 호스트를 확인한다.

## 검증 및 기존 계정 통합

- `test/nickname_auth_test.dart`: 클라이언트 입력·세션 복원·중복/잠금 메시지·UI 검증.
- `tools/live_nickname_auth_test.mjs`: 명시적 원격 검증. 가상 계정으로 동시 가입·중복·새 로그인·잘못된 PIN·잠금·자격 테이블/RPC 직접 접근 차단을 시험하며 Auth 계정을 정리한다. 관리자 키는 CLI 출력에서 메모리로만 읽고 출력하지 않는다.
- `tools/bootstrap_nickname_account.mjs`: 명시적인 계정 소유권 통합용 관리자 도구. Git 제외 경로의 계획을 입력받고, Auth 전환·닉네임 등록·트랜잭션 내 자료 이동·새 로그인 조회를 확인한다. 기대 행 수가 다르면 중단한다. 사용한 PIN 계획 파일은 작업 후 삭제한다.
- 이번 사용자 요청으로 기존 두 계정의 내신 18개를 한 로그인 계정으로 통합했다. 과목 행 ID·성적 값·시험 구분은 보존했다. 세 기간이 각 6과목으로 새 세션에서 조회되는 것을 확인했다. 기존의 빈 익명 계정은 삭제하지 않았다.
