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
