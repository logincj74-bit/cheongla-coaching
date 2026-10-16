# v1.7.9

- Replace paid SMS recovery/signup with academy-assisted recovery and manual signup approval. Keep matching password confirmation at signup.
- Administrators can view an ordinary member's original signup phone/email, record identity verification, optionally replace login email, and issue a temporary password while preserving UUID/history. Temporary login requires setting a matching new password pair before approved services resume.
- Principals can preview duplicate-account history/conflicts and merge eligible same-role accounts after confirmation. Shared financial/application keys block the merge; amounts/notice IDs/payment history are not summed or overwritten. Source login and push subscriptions are disabled; target contact/MBTI retained, originals preserved in private audit.
- Tests: manual recovery Edge network mocks; UI signup/recovery/forced-change checks; synthetic SQL transaction exercises permission denial, recovery gate, stale/conflict rejection, exam/meal composite FK transfer, payment/board/MBTI retention and source-login hook rejection, then rolls back.
- No real member passwords changed or accounts merged during QA.
