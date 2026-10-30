# Supabase RLS 보안 검증 계획

## 목적
profiles, grade_records 테이블 RLS 정책이 사용자별 데이터 격리를 보장하는지 검증

## 전제
- Supabase 프로젝트 univ-pathfinder-kr 서울 리전
- 인증된 사용자 A, B 생성, 익명 인증 사용
- SQL Editor 관리자 권한 실행 결과만으로 검증하지 않음, 클라이언트 JWT 기반 요청 사용

## 테스트 절차

### 1. 사용자 A 자신의 프로필 및 성적 저장 가능 여부
- 인증: 사용자 A JWT로 Supabase 클라이언트 초기화
- 요청: profiles INSERT where id = auth.uid(), nickname = 'test'
- grade_records INSERT where user_id = auth.uid()
- 기대 결과: 201 성공

### 2. 사용자 A 자신의 성적 조회·수정·삭제 가능 여부
- SELECT grade_records where user_id = auth.uid()
- UPDATE grade_records SET achievement = 'A' WHERE id = own_id
- DELETE grade_records WHERE id = own_id
- 기대 결과: 모두 성공

### 3. 사용자 B가 사용자 A 성적 조회·수정·삭제 불가 확인
- 인증: 사용자 B JWT
- 요청: SELECT * FROM grade_records WHERE user_id = userA_id
- 기대 결과: 0건 반환, 접근 차단
- UPDATE/DELETE 시도 시 권한 거부

### 4. 사용자 B가 사용자 A user_id로 성적 삽입 불가 확인
- 인증: 사용자 B JWT
- 요청: INSERT INTO grade_records(user_id, ...) VALUES ('userA_id', ...)
- 기대 결과: RLS with check 실패, 403/permission denied

### 5. 비인증 요청 차단 확인
- 인증 토큰 없이 Supabase 클라이언트 요청
- profiles SELECT, grade_records INSERT 시도
- 기대 결과: 401 Unauthorized

### 6. CHECK 제약조건 검증
- raw_score = -5 또는 150 INSERT 시도 → 실패
- subject_average = 200 INSERT 시도 → 실패
- grade_rank = 0 또는 6 INSERT 시도 → 실패
- school_year = 0 또는 4 INSERT 시도 → 실패
- semester = 3 INSERT 시도 → 실패
- credit < 0 INSERT 시도 → 실패
- 기대 결과: PostgreSQL check violation

## 검증 방법
- Flutter 앱에서 Supabase.instance.client 사용, 실제 JWT 전달
- 또는 PostgREST를 통한 curl 요청에 Authorization: Bearer <access_token> 헤더 포함
- SQL Editor는 service_role 키 사용이므로 RLS 우회, 사용 금지

## 주의
- 실제 성적표 원본, 이름, 학교명, 생년월일, 학번 저장 금지
- service_role 키는 절대 클라이언트에서 사용하지 않음
- 반복 익명 사용자 생성 방지를 위해 세션 재사용 확인
