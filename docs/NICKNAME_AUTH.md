# 닉네임·4자리 비밀번호 인증

적용일: 2026-11-04

## 사용

- 시작 화면에서 닉네임과 숫자 4자리 비밀번호로 로그인한다. 처음 사용하는 닉네임은 회원가입에서 등록한다.
- 닉네임은 한글·영문·숫자·밑줄 2~20자다. 앞뒤 공백을 제거하고 서버에서 NFKC 정규화 후 영문 소문자로 저장한다. 영문 대소문자를 달리해도 같은 닉네임이다.
- 기존 익명 계정에 입력했던 표시용 닉네임만으로 과거 자료를 자동 연결하지 않는다. 기존 계정 전환·자료 통합은 소유자 확인 후 관리자 작업으로 수행한다.
- 세션이나 개발 브라우저가 바뀌어도 같은 자격으로 다시 로그인하면 같은 사용자 ID로 연결된다. 홈에서 로그아웃할 수 있다.
- 자동 비밀번호 복구·재설정과 닉네임 변경은 아직 제공하지 않는다.

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
