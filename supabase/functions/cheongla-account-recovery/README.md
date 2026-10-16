# 청라 계정 찾기 문자 인증

현재 발송 서비스는 미연결이다. 준비 상태를 실제 발송으로 표시하지 않는다.

1. 046/047 SQL 설치, Custom Access Token hook에 `public.cheongla_account_access_hook` 설정. 다른 훅이 있으면 덮어쓰지 않고 통합한다.
2. Edge Function `cheongla-account-recovery` 배포, config.toml의 verify_jwt=false 적용. 함수는 자체 OTP 인증·DB 서비스 권한 검사를 사용한다.
3. SOLAPI 계정/사전 등록 발신번호/잔액 준비 후 Supabase Edge Function Secrets에 `SOLAPI_API_KEY`, `SOLAPI_API_SECRET`, `SOLAPI_SENDER`, 32자 이상 무작위 `RECOVERY_OTP_SECRET` 설정. 키를 앱 config.js/GitHub/로그/채팅에 넣지 않는다. `RECOVERY_ALLOWED_ORIGINS` 기본값은 운영 GitHub Pages origin이다.
4. status ready=true, 가입 당시 번호로 실제 수신을 사용자가 확인한다. 아이디 찾기와 비밀번호 변경은 실제 계정 소유자가 직접 수행한다. 코드 작성/모의 테스트는 실제 수신이나 실제 비밀번호 변경의 증거가 아니다.

인증번호: 암호학적 난수 6자리, 5분 유효, 5회 오류 제한, 재발급 시 이전 인증 무효. 번호당 60초 간격/하루5회, IP당 하루20회, 전체 하루200회. RPC는 service_role 전용이다. 비밀번호 재설정 증명은 메모리에만 보관하는 256비트 일회용 토큰으로 5분간 유효하다. 서버가 가입 상태를 재확인하고 Admin API로 비밀번호만 변경한다. 실패 시 토큰 재사용을 허용하지 않는다.

가입 당시 번호는 별도 비공개 테이블에 보관한다. 기존 가입자는 signup metadata의 번호를 우선 보완하며, 없으면 기존 연락처를 사용한다. 연락처 수정이 계정 복구 번호를 임의 변경하지 않는다. 같은 번호로 여러 계정이 가입한 경우 인증 후 해당 이메일들을 표시한다. 탈퇴·이용정지·가입거절 계정은 복구하지 않는다. SQL 인증 기록은 48시간 뒤 다음 요청에서 제거한다.

실제 연동 후 발신번호 불일치/잔액 부족/통신사 수신 실패를 포함해 점검한다. 발송 접수와 휴대전화 실제 수신은 구분한다. 키·인증번호·비밀번호·개인정보를 로그에 기록하지 않는다. provider 설정만으로 서비스 이용 계약을 대신 체결하거나 요금을 결제하지 않는다.

공식 문서: https://solapi.com/developers/api/messages , https://solapi.com/developers/api/authentication-api-key , https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid , https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook

## v1.7.8 신규 가입 문자 인증

048 설치 후 Auth > Hooks > Before User Created에 `public.cheongla_signup_access_hook`을 활성화한다. 기존 Custom Access Token hook은 유지한다. 가입은 SMS 인증을 완료한 이메일과 전화번호에 묶인 5분짜리 일회용 증명만 허용한다. 가입 메타데이터에서 증명을 제거하며 인증한 가입 번호의 시각을 별도 기록한다. 기존 가입자에게 재가입을 요구하지 않는다. 문자 서비스 미연결 동안 신규 가입은 대기 상태이며 기존 회원 로그인에는 영향이 없다.

서비스 준비 순서: 청라 운영 주체의 SOLAPI 가입·본인확인 → 사업자 정보 등록 → 발신번호 사전 등록(명의/소유 관계에 맞는 증빙 확인) → API Key/Secret 발급 → Supabase Edge Secrets에 키와 발신번호·OTP secret 입력 → 가입·아이디 찾기·비밀번호 변경의 실제 문자 수신을 계정 소유자가 검증. 계정 가입 약관 동의, 명의 인증 및 결제는 운영자가 직접 수행한다. 비용은 공급자의 현재 요금표와 실제 사용량에 따른다. 인증키와 개인정보 증빙은 채팅이나 Git 저장소에 올리지 않는다.
