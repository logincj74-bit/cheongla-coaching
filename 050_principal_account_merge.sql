begin;
create table cheongla_private.account_merges(id uuid primary key default gen_random_uuid(),source_id uuid not null unique,target_id uuid not null,actor_id uuid not null,reason text not null,snapshot jsonb not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.account_merges enable row level security;
revoke all on cheongla_private.account_merges from public,anon,authenticated;
create or replace function cheongla_private.merge_owners()returns table(s text,t text,c text,label text)language sql immutable set search_path=''as $$values ('public','cheongla_tuition_settings','student_id','학원비 등록 정보'),('public','cheongla_tuition_notices','student_id','학원비 청구'),('public','cheongla_exam_applications','student_id','모의고사 신청'),('public','cheongla_exam_fee_notices','student_id','응시료 청구'),('public','cheongla_meal_submissions','student_id','도시락 신청'),('public','cheongla_meal_bills','student_id','도시락 청구'),('public','cheongla_board_posts','author_id','상담 글'),('public','cheongla_board_replies','author_id','상담 답글'),('public','cheongla_new_inquiries','author_id','신규 상담'),('public','cheongla_questions','student_id','이전 학습 질문'),('public','cheongla_qa_messages','author_id','이전 학습 대화'),('public','cheongla_qa_photos','uploader_id','이전 학습 사진'),('cheongla_private','fee_deposit_reports','reported_by','입금 신고'),('cheongla_private','meal_submission_trash','student_id','도시락 휴지통')$$;
create or replace function cheongla_private.merge_snapshot(a uuid,b uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare r record;j jsonb:='{}';v jsonb;
begin
 for r in select * from cheongla_private.merge_owners()loop
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),''[]''::jsonb)from %I.%I x where %I in($1,$2)',r.s,r.t,r.c)into v using a,b;j:=j||jsonb_build_object(r.t,v);end loop;
 return j||jsonb_build_object('profiles',(select jsonb_agg(to_jsonb(p)order by p.id)from public.cheongla_profiles p where id in(a,b)),
 'links',(select coalesce(jsonb_agg(to_jsonb(x)order by parent_id,student_id),'[]')from public.cheongla_parent_students x where parent_id in(a,b)or student_id in(a,b)),
 'mbti',(select coalesce(jsonb_agg(to_jsonb(x)order by user_id),'[]')from public.cheongla_mbti_preferences x where user_id in(a,b)),
 'contacts',(select coalesce(jsonb_agg(to_jsonb(x)order by user_id),'[]')from cheongla_private.member_contacts x where user_id in(a,b)));
end;$$;
create or replace function public.cheongla_preview_account_merge(source_member uuid,target_member uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare a public.cheongla_profiles%rowtype;b public.cheongla_profiles%rowtype;snap jsonb;conflicts jsonb:='[]';counts jsonb:='[]';r record;n int;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 계정을 통합할 수 있습니다.'using errcode='42501';end if;
 select * into a from public.cheongla_profiles where id=source_member;select * into b from public.cheongla_profiles where id=target_member;
 if a.id is null or b.id is null or a.id=b.id or a.id=auth.uid()or b.id=auth.uid()or a.is_app_admin or b.is_app_admin or a.role not in('student','parent')or a.role is distinct from b.role or a.membership_state<>'active'or b.membership_state<>'active'or a.approval_status not in('approved','pending')or b.approval_status<>'approved'then raise exception '같은 회원 유형의 일반 계정을 선택하세요. 유지할 계정은 승인 상태여야 합니다.';end if;
 if exists(select 1 from cheongla_private.manual_recoveries where user_id in(a.id,b.id)and completed_at is null)then raise exception '계정 복구를 완료한 뒤 통합해 주세요.';end if;
 for r in select * from(values('cheongla_tuition_settings','true','학원비 등록 정보'),('cheongla_tuition_notices','a.billing_month=b.billing_month','같은 달 학원비 청구'),('cheongla_exam_applications','a.exam_id=b.exam_id','같은 모의고사 신청'),('cheongla_meal_submissions','a.month=b.month','같은 달 도시락 신청'),('cheongla_tuition_notices','a.program=b.program and a.deposit_season=b.deposit_season and a.deposit_credit>0 and b.deposit_credit>0 and a.archived_at is null and b.archived_at is null','같은 시즌 예약금 공제'))x(t,condition,label)loop
 execute format('select count(*)from public.%I a join public.%I b on %s where a.student_id=$1 and b.student_id=$2',r.t,r.t,r.condition)into n using a.id,b.id;
 if n>0 then conflicts:=conflicts||jsonb_build_array(jsonb_build_object('label',r.label,'count',n));end if;end loop;
 for r in select * from cheongla_private.merge_owners()loop execute format('select count(*)from %I.%I where %I=$1',r.s,r.t,r.c)into n using a.id;counts:=counts||jsonb_build_array(jsonb_build_object('label',r.label,'count',n));end loop;
 snap:=cheongla_private.merge_snapshot(a.id,b.id);
 return jsonb_build_object('source_name',a.full_name,'target_name',b.full_name,'fingerprint',md5(snap::text),'conflicts',conflicts,'counts',counts,'can_merge',jsonb_array_length(conflicts)=0,'mbti_target_kept',exists(select 1 from public.cheongla_mbti_preferences where user_id=b.id),'contact_target_kept',true);
end;$$;
alter table public.cheongla_exam_fee_notices alter constraint cheongla_exam_fee_notices_exam_id_student_id_fkey deferrable initially immediate;
alter table public.cheongla_meal_bills alter constraint cheongla_meal_bills_month_student_id_fkey deferrable initially immediate;
create or replace function public.cheongla_merge_accounts(source_member uuid,target_member uuid,expected_fingerprint text,reason text,confirmation text)returns uuid language plpgsql security definer set search_path=''as $$
declare preview jsonb;snap jsonb;r record;merge_id uuid;
begin
 if not cheongla_private.is_principal()then raise exception '원장만 계정을 통합할 수 있습니다.'using errcode='42501';end if;
 if confirmation is distinct from '계정통합'or length(btrim(reason))not between 2 and 1000 or reason is null then raise exception '본인 확인 사유와 계정통합 확인 문구를 입력해 주세요.';end if;
 perform pg_advisory_xact_lock(7492052);
 -- Serialize writes while checking the preview and moving composite foreign keys.
 lock table public.cheongla_profiles,public.cheongla_parent_students,public.cheongla_mbti_preferences,public.cheongla_notifications,public.cheongla_push_subscriptions,cheongla_private.member_contacts,cheongla_private.manual_recoveries in share row exclusive mode;
 for r in select * from cheongla_private.merge_owners()order by s,t loop execute format('lock table %I.%I in share row exclusive mode',r.s,r.t);end loop;
 preview:=public.cheongla_preview_account_merge(source_member,target_member);
 if preview->>'fingerprint'is distinct from expected_fingerprint then raise exception '기록이 변경되었습니다. 통합 미리보기를 다시 확인해 주세요.';end if;
 if not(preview->>'can_merge')::boolean then raise exception '겹치는 신청·청구 정보를 먼저 확인해 주세요. 자동으로 덮어쓰지 않습니다.';end if;
 snap:=cheongla_private.merge_snapshot(source_member,target_member);
 insert into cheongla_private.account_merges(source_id,target_id,actor_id,reason,snapshot)values(source_member,target_member,auth.uid(),btrim(reason),snap)returning id into merge_id;
 set constraints public.cheongla_exam_fee_notices_exam_id_student_id_fkey,public.cheongla_meal_bills_month_student_id_fkey deferred;
 for r in select * from cheongla_private.merge_owners()loop execute format('update %I.%I set %I=$1 where %I=$2',r.s,r.t,r.c,r.c)using target_member,source_member;end loop;
 -- Archived snapshots must restore into the surviving account too.
 update cheongla_private.meal_submission_trash set submission_snapshot=jsonb_set(submission_snapshot,'{student_id}',to_jsonb(target_member)),bill_snapshot=case when bill_snapshot is null then null else jsonb_set(bill_snapshot,'{student_id}',to_jsonb(target_member))end where student_id=target_member and submission_snapshot->>'student_id'=source_member::text;
 update cheongla_private.tuition_draft_actions set snapshot=jsonb_set(snapshot,'{student_id}',to_jsonb(target_member))where snapshot->>'student_id'=source_member::text;
 insert into public.cheongla_parent_students(parent_id,student_id,created_by,created_at)select case when parent_id=source_member then target_member else parent_id end,case when student_id=source_member then target_member else student_id end,created_by,created_at from public.cheongla_parent_students where parent_id=source_member or student_id=source_member on conflict do nothing;
 delete from public.cheongla_parent_students where parent_id=source_member or student_id=source_member;
 insert into public.cheongla_mbti_preferences(user_id,mbti,updated_at)select target_member,mbti,updated_at from public.cheongla_mbti_preferences where user_id=source_member on conflict do nothing;
 -- Original MBTI/contact remain archived on the closed profile; target contact stays unchanged.
 update public.cheongla_notifications set recipient_id=target_member,event_key='merge:'||source_member::text||':'||event_key where recipient_id=source_member;
 update public.cheongla_notifications set student_id=target_member where student_id=source_member;
 update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp()where user_id=source_member;
 update public.cheongla_profiles set membership_state='withdrawn',approval_status='suspended',withdrawn_at=clock_timestamp()where id=source_member;
 insert into cheongla_private.member_actions(member_id,actor_id,action,reason)values(source_member,auth.uid(),'merged_into',target_member::text||' · '||btrim(reason)),(target_member,auth.uid(),'merged_from',source_member::text||' · '||btrim(reason));
 set constraints public.cheongla_exam_fee_notices_exam_id_student_id_fkey,public.cheongla_meal_bills_month_student_id_fkey immediate;
 return merge_id;
end;$$;
revoke all on function cheongla_private.merge_owners(),cheongla_private.merge_snapshot(uuid,uuid),public.cheongla_preview_account_merge(uuid,uuid),public.cheongla_merge_accounts(uuid,uuid,text,text,text)from public,anon,authenticated;
grant execute on function public.cheongla_preview_account_merge(uuid,uuid),public.cheongla_merge_accounts(uuid,uuid,text,text,text)to authenticated;
notify pgrst,'reload schema';
commit;
