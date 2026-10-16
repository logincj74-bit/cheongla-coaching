# Manual account recovery (v1.7.9)

No paid SMS provider is used. Public `status` returns `{ready:false,manual:true}`. Previous OTP request/verify/reset routes are retired.

Apply `049_manual_account_recovery.sql` and `050_principal_account_merge.sql`, then deploy this function with `verify_jwt=false`. The handler validates every operational Bearer token using Supabase `/auth/v1/user`; caller IDs are never trusted from request bodies. Keep the existing account-access Auth hook enabled. Signup hook now allows ordinary registration followed by manual staff approval.

An authorized app administrator or principal may issue a random temporary password to an active ordinary student/parent after checking the immutable signup phone and recording a reason. Optional email replacement preserves the auth UUID. Passwords are returned once, never stored in audit data. Staff/admin/self recovery is not supported by this workflow. Failed credential updates remain gated and may be retried after one minute.

The member remains pending until setting a new matching password pair. A recovery marker prevents manual approval from bypassing this gate. Existing pending members remain pending after recovery. Suspended/withdrawn members cannot be restored through recovery. Production smoke tests use status/unauthenticated requests only; actual password changes require the operator's member-specific action.

Principal-only merge runs as one database transaction, verifies a preview fingerprint and locks owned records. Shared monthly tuition, exam/meal application and season deposit conflicts block the operation. Financial amounts, notice IDs, payments and original actor history are preserved. Composite foreign keys are deferred only within the merge transaction. Parent links are combined, target MBTI/contact retained, source values archived in private audit snapshots. Source login is disabled by membership withdrawal; its device subscriptions are disabled. No real member merge is part of automated QA.
