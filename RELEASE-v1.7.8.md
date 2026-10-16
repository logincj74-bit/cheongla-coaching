# v1.7.8

신규 가입에 휴대전화 6자리 문자 인증을 요구한다. 인증번호는 5분 유효, 최대5회 오류, 재요청은60초/번호당하루5회 제한을 적용한다. 인증 완료 후5분 안에 이메일·전화번호가 일치하는 가입 신청만 허용한다. 가입용 인증과 계정 복구용 인증은 교환할 수 없다. 이메일/번호 수정, 위조/만료/재사용을 거부한다. 가입 증명은 auth 메타데이터에 보관하지 않는다.

서버: 048 SQL, Before User Created hook `cheongla_signup_access_hook`. 기존 탈퇴 차단용 Custom Access Token hook을 유지한다. 계정 복구 Edge function은 가입 인증을 함께 처리한다. 문자 서비스 가입 및 발신번호·API credentials 설정은 아직 완료되지 않았다. 따라서 실제 문자는 발송되지 않고 신규 가입도 대기 상태다. 기존 회원의 로그인과 서비스는 유지한다.

검증: account-access.cjs, account-recovery-server.cjs, release-ui.cjs, information.cjs. 운영 DB signup-phone-server.sql은 합성 자료로 검증 후 롤백. 실제 사용자 가입/문자 발송/비밀번호 변경은 수행하지 않았다.
