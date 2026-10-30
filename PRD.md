# Univ Pathfinder PRD

## 1. 제품 개요 및 해결할 문제

### 제품 개요
프로젝트명: Univ Pathfinder  
목적: 대입 수험생이 성적표를 업로드하여 과목별 성적을 자동 입력하고, 희망 진로에 맞는 대학·학과·전형을 탐색하며, 모집요강·등록금·통학 거리를 비교하는 Flutter 앱.

### 해결할 문제
- 수기 성적 입력의 불편함
- 여러 대학 모집요강을 따로 검색해야 하는 문제
- 진로·성적·통학거리·등록금을 함께 비교하기 어려운 문제

## 2. 대상 사용자 및 사용자 시나리오

### 대상 사용자
- 대입 수험생
- 필요 시 보호자 또는 진학 지도교사(향후 확장)

### 주요 사용자 시나리오
닉네임 생성 → 성적표 업로드 → AI 추출 → 사용자 검증 → 진로 분야 선택 → 대학 탐색 → 비교 → 즐겨찾기

상세 흐름:
1. 시작 화면에서 닉네임 설정, Supabase 익명 인증으로 사용자 식별
2. 성적표 JPG/PNG/PDF 업로드
3. AI/OCR로 성적 추출 후 표로 표시, 사용자 수정·확인
4. 확인된 성적 저장
5. 진로 분야 및 관심 학과 선택
6. 대학·학과·전형 검색 및 모집요강·등록금·거리 비교
7. 비교 결과 저장 및 즐겨찾기 등록
8. 설정에서 데이터 삭제

## 3. 핵심 기능 요구사항

F01: 닉네임 설정 및 Supabase 익명 인증 ID 기반 사용자 구분
F02: JPG/PNG/PDF 성적표 업로드
F03: 멀티모달 AI/OCR로 학년, 학기, 과목명, 이수학점/단위수, 원점수, 과목평균, 성취도(A~E 등), 석차등급(1~5, 2028학년도 대입 5등급 체계 기본), 성취도별 분포비율 등 성적표에 실제 기재된 항목 추출
F04: 인식 결과를 표로 표시하고 사용자가 수정·확인한 뒤 저장
F05: 학년도·교육과정·과목에 따라 존재하지 않는 성적 항목은 null로 처리
F06: 진로 분야 및 관심 학과 선택
F07: 대학·학과·전형별 모집요강 검색 및 공식 원문 링크 표시
F08: 모집요강 PDF 수집·추출·검증·갱신을 위한 별도 관리자용 데이터 파이프라인 설계
F09: 대학별 등록금 및 기준연도 표시
F10: 카카오 지도 API를 이용한 출발 위치와 대학 간 거리·이동시간 계산
F11: 대학 2~3곳 비교 및 즐겨찾기
F12: 성적과 전형 요건의 비교 결과 및 근거 표시
F13: 사용자 데이터 삭제 기능

## 4. 데이터 설계 초안

### 테이블 목록 및 주요 필드

profiles
- user_id: Supabase 인증 사용자 고유 ID, PK, FK auth.users
- nickname: 표시용 닉네임
- created_at

grade_records
- id: PK
- user_id: FK profiles
- school_year, semester
- subject_name, credit, raw_score, subject_average, achievement, grade_rank, achievement_distribution_ratio
- verified_at: 사용자 확인 일시
- 제약: user_id 기준 RLS, verified_at이 있을 때만 분석에 사용
- 내신 성적 추출 규칙: 2028학년도 대입 5등급 체계를 기본으로 하되 석차등급만으로 분석하지 않음. 과목별 학년·학기, 과목명, 이수학점, 원점수, 과목평균, 성취도, 석차등급, 성취도별 분포비율을 성적표에 실제 기재된 항목만 추출하여 저장. 성적표에 없는 항목은 null 처리, 원본에 없는 값은 AI가 임의 생성하지 않음

내신 성적 분석 설계
- 과목별 이수학점과 성적 지표 원점수, 과목평균, 성취도, 석차등급, 성취도별 분포비율을 활용한 요약 및 비교 기능 제공
- 석차등급만으로 분석하지 않고 다중 지표 종합 표시
- 대학별 공식 반영 기준이 확인된 경우에만 환산점수 계산. 미확정 시 ‘환산 불가’ 또는 ‘공식 미확인’ 표시
- 환산점수 계산 시 공식 출처, 학년도, 확인일 함께 기록

universities
- id: PK
- name, campus, address, latitude, longitude

departments
- id: PK
- university_id: FK universities
- name, career_category

admission_guides
- id: PK
- university_id: FK universities
- admission_year, admission_type
- source_url, published_at, checked_at, verification_status

admission_requirements
- id: PK
- admission_guide_id: FK admission_guides
- department_id: FK departments
- track_name, eligibility, evaluation_method, csat_minimum, source_page

tuition_records
- id: PK
- university_id: FK universities
- department_id: nullable FK departments
- reference_year, amount_krw, source_url

favorites
- id: PK
- user_id: FK profiles
- university_id: FK universities
- department_id: nullable FK departments

comparison_history
- id: PK
- user_id: FK profiles
- selected_options: JSON 형태 비교 대상
- created_at

관계 요약
- profiles 1:N grade_records, favorites, comparison_history
- universities 1:N departments, admission_guides, tuition_records
- departments N:1 universities, 1:N admission_requirements
- admission_guides 1:N admission_requirements
- 성적표 원본은 기본적으로 영구 저장하지 않는다. 처리 후 삭제 원칙.

## 5. 보안 및 개인정보

- 닉네임만으로 로그인하거나 다른 사용자의 기록을 조회하지 못하도록 한다.
- Supabase 익명 인증과 RLS 사용
- 성적표에 이름·학교명·학번 등이 있으면 업로드 전 가림 처리 안내
- 실제 개인정보가 포함된 원본은 서버에 영구 저장하지 않음
- AI API 비밀키는 서버 측에만 보관
- 사용자가 자신의 성적 및 계정을 삭제할 수 있도록 설계
- 집 주소는 DB에 저장하지 않고, 필요 시 출발 위치를 일시적으로 사용
- 학생 성적 데이터는 민감하게 취급하고 최소 수집 원칙 적용
- API 키, 토큰, 개인정보를 로그나 GitHub에 기록하지 않는다.

## 6. AI 기능의 한계

- AI는 성적표 정보 추출 및 설명에 사용
- 성적 계산은 검증 가능한 코드로 처리
- 모집요강은 공식 원문, 학년도, 검증 상태 표시
- 합격 가능성을 단정하지 않음
- 데이터 부족 시 '판단 불가' 표시
- 대학별 환산점수는 공식 산식이 확인된 경우에만 계산
- AI 추출 결과는 사용자가 확인·수정한 후 저장
- 성적표 원본에 없는 항목은 AI가 임의로 생성하지 않으며, 해당 필드는 null로 저장
- 석차등급만으로 학생 성적을 분석하지 않음. 원점수, 과목평균, 성취도, 이수학점 등 다중 지표 함께 활용

## 7. 주요 화면 5~7개

1. 시작/닉네임
   - 닉네임 입력, 익명 로그인, 안내
   - 이동: 닉네임 설정 → 홈

2. 홈
   - 성적 요약, 즐겨찾기 대학, 최근 비교
   - 이동: 성적표 업로드, 대학 검색, 비교, 설정

3. 성적표 업로드 및 인식 결과 확인
   - 파일 선택, 업로드 전 식별정보 제거 안내
   - AI 추출 표 표시, 수정 UI, 확인 저장
   - 이동: 확인 완료 → 성적 분석

4. 성적 분석
   - 과목별 성적 목록, 학년·학기 필터
   - 이동: 대학 검색으로 진로 기반 탐색

5. 대학·학과 검색
   - 대학명, 학과명, 진로 분야 필터
   - 모집요강 요약, 등록금, 거리 미리보기
   - 이동: 대학 비교

6. 대학 비교(모집요강·등록금·지도)
   - 2~3개 대학 선택 비교, 공식 원문 링크
   - 카카오 지도 거리·이동시간 표시
   - 이동: 즐겨찾기 등록

7. 즐겨찾기 및 설정
   - 즐겨찾기 목록, 데이터 삭제, 닉네임 변경
   - 이동: 홈

## 8. 단계별 개발 우선순위

P0: Flutter 앱 기본 UI, 익명 인증, 가상 성적 데이터 입력·저장, 성적표 AI 인식 및 검증
P1: 대학 5곳의 공식 모집요강·등록금 DB 구축, 대학 검색 및 비교, 카카오 지도 연동
P2: 진로 기반 추천, 대학별 환산점수, 모집요강 갱신 자동화, 대중교통 옵션

## 9. 기술 스택

- Flutter/Dart
- Supabase Auth, PostgreSQL, RLS
- Gemini 등 멀티모달 AI API(서버 측 호출)
- Kakao Maps/Local/Route API(기존 키의 사용 권한과 호출 방식은 추후 검증)
- VS Code + Cline + Git/GitHub

## 10. 수용 기준 및 테스트 시나리오

- 가상 성적표 업로드 후 추출 결과를 확인·수정할 수 있다.
- 확인된 성적이 사용자별 DB에 저장된다.
- 다른 익명 사용자 데이터는 조회할 수 없다.
- 대학 모집요강의 공식 출처를 열 수 있다.
- 등록금 기준연도가 표시된다.
- 출발지에서 대학까지 경로 계산이 가능하다.
- API 실패나 추출 오류가 발생하면 적절한 오류 메시지가 표시된다.
- 테스트 데이터는 가상 학생·가상 성적표만 사용한다.

## 11. 범위 제외 및 위험 요소

범위 제외
- 입학 합격 보장 또는 무근거 합격확률 제공 금지
- 대학 모집요강의 무단 대량 크롤링 금지
- 학생의 실명·주민등록번호·학번 수집 금지
- 초기 버전은 가상 데이터와 대학 5곳으로 제한

위험 요소 및 대응
- 익명 계정의 기기 변경·삭제 시 복구 제한을 명시
- 모집요강 오인식, AI 환각: 공식 원문 링크, 검증 상태, checked_at 표시
- API 비용: 서버 측 호출, 캐싱, 호출 횟수 제한 설계
- 데이터 최신성: 관리자용 파이프라인, 확인일 갱신

## 미확정/추후 검증 사항
- Kakao Maps/Local/Route API 기존 키의 사용 권한과 호출 방식
- 멀티모달 AI API 선정 및 서버 측 호출 아키텍처 상세
- 모집요강 PDF 수집·추출·검증 파이프라인 구현 방식
- 대학별 환산점수 공식 산식 출처 확보 여부
- 출발 위치 처리 방식 및 일시 저장 정책 상세
- 대중교통 옵션 제공 범위

작성 규칙 준수: 한국어 Markdown, 기능 ID와 우선순위 명시, 코드 및 SQL 미작성, PRD.md로 작성 완료.
