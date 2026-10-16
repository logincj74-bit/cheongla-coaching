# v1.7.7

- 시험 등록과 응시료 관리: 대성 더 프리미엄, 시대인재 서프, 평가원 6월·9월, 기타 구분을 저장한다. 응시료는 시험마다 직접 입력하고, 등록된 시험이 없으면 등록 화면으로 이동한다. 기존 시험·납부 기록은 유지한다.
- 가입: 비밀번호와 확인 비밀번호가 일치해야 가입 API를 호출한다.
- 탈퇴: 프로필 확인 시 탈퇴 계정 세션을 종료하고 계정 화면을 숨긴다. Auth Custom Access Token hook에서 탈퇴 계정의 새 토큰 발급과 갱신을 거부한다. 기존 RLS 승인·탈퇴 제한을 유지한다.
- 계정 찾기: 가입 당시 번호에 6자리 SMS 인증, 인증 후 이메일 확인 또는 5분간 일회용 비밀번호 변경 허용. 비밀번호는 서버와 화면 모두 8~128자 및 두 입력 일치를 확인한다. 복구 RPC는 service_role 전용이다.
- 실제 문자 발송 서비스는 아직 미연결이다. SOLAPI 연동 코드를 준비했으나 가입/계약/잔액 충전/발신번호 등록/인증키 입력을 대신 수행하지 않았다. 준비 상태에서는 문자 발송 성공으로 표시하지 않는다. 실제 문자 수신 및 실제 계정 비밀번호 변경은 미검증이다.

검증: checks/account-access.cjs, checks/account-recovery-server.cjs, checks/release-ui.cjs, checks/information.cjs. checks/account-access-server.sql로 운영 DB에서 합성 자료 트랜잭션을 검증 후 롤백했다. 함수 설치 046/047 후 Auth hook과 Edge function을 설정한다.
