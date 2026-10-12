# 청라 휴대전화 Web Push 연결

현재 웹 프런트엔드와 서버 소스는 준비된 상태다. Supabase에 SQL과 서버 함수를 적용하고 실제 기기 수신을 확인하기 전에는 ‘푸시 발송 완료’로 설명하지 않는다.

## 적용 순서

1. 알림함 SQL `020_role_notifications.sql`이 운영 DB에 실행되어 있는지 확인한다. 상담문의는 앞서 `019_general_question_board.sql`을 적용해야 한다.
2. SQL Editor에서 `021_web_push.sql` 전체를 한 번 실행한다. pg_net·pg_cron, 구독 저장, 발송 대기열, 재시도와 서버 초기화 함수를 만든다. 아직 발송은 꺼져 있다.
3. Supabase Edge Functions에서 함수 이름 **cheongla-push**로 `index.ts`를 배포한다. CLI를 사용하는 경우 `supabase/config.toml`의 해당 함수 설정을 적용한다. 대시보드에서는 이 함수의 게이트웨이 JWT 검증 옵션을 소스의 설정과 일치시킨다.
4. 게이트웨이 JWT 검증을 끄더라도 함수 내부에서는 사용자 JWT를 `auth.getUser`로 검증한다. 관리자 초기화는 승인된 is_app_admin만 허용하며 발송기는 DB에 저장된 임의의 비공개 웹훅 키로 검증한다. 익명 초기화와 익명 발송은 거부한다.
5. Supabase가 제공하는 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY 환경변수를 사용한다. 서비스 키를 HTML·GitHub·대화창에 복사하지 않는다.
6. 승인된 앱 관리자 계정으로 청라 앱의 **알림함 → 푸시 서버 연결**을 누른다. 서버가 VAPID 키를 생성해 보호된 DB 테이블에 저장한다. 공개키만 브라우저에 반환한다. 이미 있는 키는 유지한다.
7. 각 회원이 **알림함 → 푸시 알림 켜기**를 직접 누르고 휴대전화 알림 허용을 선택한다. 관리자가 회원 대신 OS 권한을 켤 수는 없다.
8. iPhone/iPad는 Safari에서 청라 앱을 홈 화면에 추가하고 그 아이콘으로 실행한 웹앱에서 켠다.
9. **테스트 알림 보내기**를 누른 뒤 앱을 닫거나 화면을 잠그고 실제 수신을 확인한다. 승인된 회원 자신의 기기에만 테스트를 요청할 수 있고 요청 간격은 30초로 제한한다.

## 동작과 보호

- source notifications의 수신자만 자신의 등록 기기로 받는다. 기존 공지·질문·답변·청구 권한과 동일하다.
- 전송 직전에 수신자의 현재 승인·글 접근 권한·구독 계정 일치를 다시 검증한다.
- 잠금화면 문구에는 비공개 질문 본문·학생 이름·학원비 금액을 넣지 않는다.
- 서비스 워커는 인증 페이지·API·개인 파일을 캐시하지 않는다.
- 기기 연결 해제와 로그아웃 시 해당 브라우저의 구독을 해제한다.
- HTTPS의 Apple·Google·Mozilla·Windows 푸시 서비스만 허용하고 리디렉션은 따라가지 않는다.
- 실패 시 최대 3회 시도한다. pg_cron이 매분 대기 작업을 깨운다. 성공한 전송은 재발송하지 않으며 만료 응답 404/410은 구독을 비활성화한다.
- 새로 알림을 켠 기기에 과거 글을 소급 발송하지 않는다. 과거 알림은 알림함에서 확인한다.
- 요청 성공이나 공급자의 HTTP 2xx는 실제 기기에서 표시된 것을 증명하지 않는다. iOS 집중 모드, 사용자의 알림 설정 등까지 포함해 실제 기기 수신으로 최종 확인한다.

## 확인된 테스트 범위

- PostgreSQL: 승인 제한, 일반 회원의 서버 비밀 조회 차단, 구독 소유권, 악성 엔드포인트 거부, 알림 테스트 제한, 큐의 원자적 가져오기, 성공·실패 처리, 발송 전 승인 취소, SQL 재실행.
- 서버 로직: 실제 Web Push 라이브러리의 키 생성과 암호화 요청 구성, 일반 회원/관리자 인증, 웹훅 인증, 비공개 키 비노출, 엔드포인트 제한, 응답 기록. Supabase API와 외부 네트워크는 모의 처리했다.
- 웹: 사용자 클릭 전 권한 요청 금지, iOS 홈 화면 조건, 구독 저장, 테스트 요청, 로그아웃 연결 해제, 서비스 워커의 표시와 앱 내부 클릭 이동.
- 실제 Supabase Edge Functions 배포 및 휴대전화 잠금화면 수신은 별도 확인해야 한다.

공식 참고:
- https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/
- https://supabase.com/docs/guides/functions/quickstart-dashboard
- https://supabase.com/docs/guides/cron/quickstart
- https://github.com/web-push-libs/web-push
