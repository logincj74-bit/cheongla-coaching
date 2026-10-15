begin;
alter table public.cheongla_profiles add column membership_state text not null default 'active' check(membership_state in ('active','withdrawn')),
 add column membership_updated_at timestamptz not null default clock_timestamp(),add column withdrawn_at timestamptz;
create table cheongla_private.member_actions(id bigint generated always as identity primary key,member_id uuid not null,actor_id uuid,action text not null,reason text not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.member_actions enable row level security;
revoke all on cheongla_private.member_actions from public,anon,authenticated;
create or replace function cheongla_private.guard_membership() returns trigger language plpgsql set search_path='' as $$
begin
 if new.membership_state='withdrawn' and (new.approval_status<>'suspended' or new.is_app_admin) then raise exception '탈퇴 회원은 다시 승인할 수 없습니다.';end if;
 if old.membership_state='withdrawn' and new.membership_state<>old.membership_state then raise exception '탈퇴 회원의 이용 상태를 변경할 수 없습니다.';end if;
 if (new.role,new.approval_status,new.is_app_admin,new.membership_state) is distinct from (old.role,old.approval_status,old.is_app_admin,old.membership_state) then new.membership_updated_at:=clock_timestamp();end if;
 return new;
end;$$;
create trigger cheongla_membership_guard before update on public.cheongla_profiles for each row execute function cheongla_private.guard_membership();
create or replace function public.cheongla_withdraw_membership(confirmation text) returns uuid language plpgsql security definer set search_path='' as $$
declare me public.cheongla_profiles%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492052);
 select * into me from public.cheongla_profiles where id=(select auth.uid()) for update;
 if not found then raise exception '로그인 후 이용해 주세요.' using errcode='42501';end if;
 if confirmation is distinct from '회원탈퇴' then raise exception '확인란에 회원탈퇴를 입력해 주세요.';end if;
 if me.is_app_admin or me.role='owner' then raise exception '앱 관리자 계정은 먼저 다른 관리자에게 업무를 인계해 주세요.';end if;
 if me.membership_state='withdrawn' then return me.id;end if;
 update public.cheongla_profiles set membership_state='withdrawn',approval_status='suspended',is_app_admin=false,withdrawn_at=clock_timestamp() where id=me.id;
 update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp() where user_id=me.id;
 insert into cheongla_private.member_actions(member_id,actor_id,action,reason) values(me.id,me.id,'self_withdraw','본인 회원탈퇴');
 return me.id;
end;$$;
create or replace function public.cheongla_manage_member(target_member uuid,member_action text,action_reason text,expected_member_version timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.cheongla_profiles%rowtype;
begin
 perform pg_catalog.pg_advisory_xact_lock(7492052);
 if not cheongla_private.is_app_admin() or not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and role in ('owner','english_director','math_director')) then raise exception '원장 앱 관리자만 이용 제한과 탈퇴를 처리할 수 있습니다.' using errcode='42501';end if;
 if member_action is null or member_action not in ('suspend','restore','withdraw') or action_reason is null or length(btrim(action_reason)) not between 2 and 1000 then raise exception '처리 종류와 사유를 확인해 주세요.';end if;
 select * into m from public.cheongla_profiles where id=target_member for update;
 if not found or m.id=(select auth.uid()) or m.is_app_admin or m.role not in ('student','parent') then raise exception '학생·학부모 일반 회원만 처리할 수 있습니다.' using errcode='42501';end if;
 if m.membership_updated_at is distinct from expected_member_version then raise exception '회원 상태가 변경되었습니다. 목록을 새로고침해 주세요.';end if;
 if m.membership_state='withdrawn' then raise exception '이미 탈퇴 처리된 회원입니다.';end if;
 if member_action='restore' and m.approval_status<>'suspended' then raise exception '이용 중지된 회원만 복원할 수 있습니다.';end if;
 update public.cheongla_profiles set approval_status=case when member_action='restore' then 'approved' else 'suspended' end,
 membership_state=case when member_action='withdraw' then 'withdrawn' else 'active' end,
 withdrawn_at=case when member_action='withdraw' then clock_timestamp() else null end where id=m.id;
 if member_action<>'restore' then update public.cheongla_push_subscriptions set enabled=false,updated_at=clock_timestamp() where user_id=m.id;end if;
 insert into cheongla_private.member_actions(member_id,actor_id,action,reason) values(m.id,(select auth.uid()),member_action,btrim(action_reason));
 return m.id;
end;$$;
create or replace function public.cheongla_member_action_history(target_member uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not cheongla_private.is_app_admin() then raise exception '앱 관리자만 처리 기록을 확인할 수 있습니다.' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select action,reason,created_at from cheongla_private.member_actions where member_id=target_member order by created_at desc,id desc limit 20) x),'[]'::jsonb);
end;$$;
revoke all on function public.cheongla_withdraw_membership(text),public.cheongla_manage_member(uuid,text,text,timestamptz),public.cheongla_member_action_history(uuid) from public,anon,authenticated;
grant execute on function public.cheongla_withdraw_membership(text),public.cheongla_manage_member(uuid,text,text,timestamptz),public.cheongla_member_action_history(uuid) to authenticated;

alter table public.cheongla_new_inquiries add column author_id uuid references public.cheongla_profiles(id),
 add column review_state text not null default 'pending' check(review_state in ('pending','published','hidden')),
 add column risk_flags text[] not null default '{}',add column review_reason text not null default '',add column reviewed_by uuid references public.cheongla_profiles(id),add column reviewed_at timestamptz;
-- Existing public inquiries remain public; all newly submitted public inquiries require review.
update public.cheongla_new_inquiries set review_state='published' where visibility='public';
create table cheongla_private.inquiry_blocks(inquiry_id uuid primary key references public.cheongla_new_inquiries(id),blocked_by uuid not null,reason text not null,created_at timestamptz not null default clock_timestamp());
alter table cheongla_private.inquiry_blocks enable row level security;
revoke all on cheongla_private.inquiry_blocks from public,anon,authenticated;
create or replace function cheongla_private.inquiry_risk_flags(content text) returns text[] language plpgsql immutable set search_path='' as $$
declare flags text[]:='{}';t text:=regexp_replace(lower(coalesce(content,'')),'[[:space:][:punct:]]','','g');
begin
 if t ~ '(씨발|시발놈|병신|개새끼|좆|죽여버)' then flags:=array_append(flags,'욕설·위협 의심');end if;
 if t ~ '(야동|성인동영상|조건만남|섹스|porn|xvideos|xnxx)' then flags:=array_append(flags,'성인·음란 표현 의심');end if;
 if t ~ '(불법도박|온라인카지노|대출광고|스팸|바카라)' then flags:=array_append(flags,'광고·스팸 의심');end if;
 if coalesce(content,'') ~* '(https?://|www\.)' then flags:=array_append(flags,'외부 링크 확인');end if;
 return flags;
end;$$;
revoke all on function cheongla_private.inquiry_risk_flags(text) from public,anon,authenticated;
alter table cheongla_private.inquiry_blocks add column enabled boolean not null default true;
create or replace function public.cheongla_submit_new_inquiry(visitor_token uuid,submission_token uuid,visitor_name text,visitor_phone text,visitor_role text,inquiry_title text,inquiry_body text,inquiry_visibility text,contact_consent boolean,website_field text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;phone text;
begin
 if visitor_token is null or submission_token is null or contact_consent is distinct from true or coalesce(website_field,'')<>'' then raise exception '상담 정보와 연락처 이용 동의를 확인해 주세요.';end if;
 phone:=regexp_replace(coalesce(visitor_phone,''),'[^0-9]','','g');
 if visitor_name is null or length(btrim(visitor_name)) not between 1 and 60 or phone !~ '^0[0-9]{8,10}$' or visitor_role is null or visitor_role not in ('student','parent') or inquiry_title is null or length(btrim(inquiry_title)) not between 1 and 150 or inquiry_body is null or length(btrim(inquiry_body)) not between 1 and 5000 or inquiry_visibility is null or inquiry_visibility not in ('public','private') then raise exception '이름, 전화번호, 제목, 내용과 공개 여부를 확인해 주세요.';end if;
 if auth.uid() is not null and not exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and membership_state='active' and approval_status not in ('suspended','rejected')) then raise exception '현재 계정은 문의를 등록할 수 없습니다.' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 if exists(select 1 from cheongla_private.inquiry_blocks b join public.cheongla_new_inquiries q on q.id=b.inquiry_id where b.enabled and (q.visitor_key=visitor_token or q.contact_phone=phone or (q.author_id is not null and q.author_id=(select auth.uid())))) then raise exception '이용 규칙 위반으로 신규 문의 접수가 제한되었습니다.' using errcode='42501';end if;
 select id into result_id from public.cheongla_new_inquiries where submission_key=submission_token and visitor_key=visitor_token;if found then return result_id;end if;
 if exists(select 1 from public.cheongla_new_inquiries where (visitor_key=visitor_token or contact_phone=phone) and created_at>clock_timestamp()-interval '30 seconds') then raise exception '잠시 기다린 뒤 문의를 등록해 주세요.';end if;
 if (select count(*) from public.cheongla_new_inquiries where (visitor_key=visitor_token or contact_phone=phone) and created_at>clock_timestamp()-interval '1 day')>=5 then raise exception '오늘 문의 접수 한도를 초과했습니다. 학원 전화·문자로 문의해 주세요.';end if;
 insert into public.cheongla_new_inquiries(visitor_key,submission_key,contact_name,contact_phone,applicant_role,title,body,visibility,author_id,risk_flags)
 values(visitor_token,submission_token,btrim(visitor_name),phone,visitor_role,btrim(inquiry_title),btrim(inquiry_body),inquiry_visibility,(select auth.uid()),cheongla_private.inquiry_risk_flags(inquiry_title||' '||inquiry_body)) returning id into result_id;
 return result_id;
end;$$;
create or replace function public.cheongla_list_new_inquiries(page_limit integer default 20) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare manager boolean:=false;result jsonb;max_rows integer;
begin
 if auth.uid() is not null then manager:=cheongla_private.can_manage_consultations();end if;
 max_rows:=greatest(1,least(coalesce(page_limit,20),200));
 select coalesce(jsonb_agg(item order by created_at desc,id desc),'[]'::jsonb) into result
 from (select id,created_at,jsonb_build_object('id',id,'title',title,'body',body,'visibility',visibility,'applicant_role',applicant_role,'created_at',created_at,'updated_at',updated_at,'reply_body',reply_body,'replied_at',replied_at)
 ||case when manager then jsonb_build_object('contact_name',contact_name,'contact_phone',contact_phone,'consultation_status',consultation_status,'status_updated_at',status_updated_at,'review_state',review_state,'risk_flags',risk_flags,'review_reason',review_reason,'author_id',author_id,'blocked',exists(select 1 from cheongla_private.inquiry_blocks b join public.cheongla_new_inquiries q on q.id=b.inquiry_id where b.enabled and (q.visitor_key=cheongla_new_inquiries.visitor_key or q.contact_phone=cheongla_new_inquiries.contact_phone or (q.author_id is not null and q.author_id=cheongla_new_inquiries.author_id)))) else '{}'::jsonb end as item
 from public.cheongla_new_inquiries where manager or (visibility='public' and review_state='published') order by created_at desc,id desc limit max_rows) p;
 return jsonb_build_object('items',result,'can_manage',manager);
end;$$;
create or replace function public.cheongla_review_new_inquiry(target_inquiry uuid,review_action text,action_reason text,expected_updated_at timestamptz) returns uuid language plpgsql security definer set search_path='' as $$
declare q public.cheongla_new_inquiries%rowtype;
begin
 if not cheongla_private.can_manage_consultations() then raise exception '원장·실장만 신규 문의를 검토할 수 있습니다.' using errcode='42501';end if;
 if review_action is null or review_action not in ('publish','hide','pending','block','unblock') or action_reason is null or length(action_reason)>1000 then raise exception '검토 처리 내용을 확인해 주세요.';end if;
 if review_action in ('hide','block') and length(btrim(action_reason))<2 then raise exception '숨김·차단 사유를 입력해 주세요.';end if;
 perform pg_catalog.pg_advisory_xact_lock(7492053);
 select * into q from public.cheongla_new_inquiries where id=target_inquiry for update;
 if not found then raise exception '해당 문의가 없습니다.';end if;
 if q.updated_at is distinct from expected_updated_at then raise exception '문의가 변경되었습니다. 새로고침해 주세요.';end if;
 if review_action='publish' and q.visibility<>'public' then raise exception '비공개 문의는 공개 게시할 수 없습니다.';end if;
 if review_action='publish' and exists(select 1 from cheongla_private.inquiry_blocks b join public.cheongla_new_inquiries x on x.id=b.inquiry_id where b.enabled and (x.visitor_key=q.visitor_key or x.contact_phone=q.contact_phone or (x.author_id is not null and x.author_id=q.author_id))) then raise exception '차단된 작성자의 문의는 공개할 수 없습니다.';end if;
 if review_action='block' then
  insert into cheongla_private.inquiry_blocks(inquiry_id,blocked_by,reason) values(q.id,(select auth.uid()),btrim(action_reason)) on conflict(inquiry_id) do update set enabled=true,blocked_by=excluded.blocked_by,reason=excluded.reason,created_at=clock_timestamp();
  update public.cheongla_new_inquiries set review_state='hidden',review_reason=btrim(action_reason),reviewed_by=(select auth.uid()),reviewed_at=clock_timestamp(),updated_at=clock_timestamp() where visitor_key=q.visitor_key or contact_phone=q.contact_phone or (author_id is not null and author_id=q.author_id);
 elsif review_action='unblock' then
  update cheongla_private.inquiry_blocks b set enabled=false from public.cheongla_new_inquiries x where x.id=b.inquiry_id and (x.visitor_key=q.visitor_key or x.contact_phone=q.contact_phone or (x.author_id is not null and x.author_id=q.author_id));
  update public.cheongla_new_inquiries set updated_at=clock_timestamp() where id=q.id;
 else
  update public.cheongla_new_inquiries set review_state=case review_action when 'publish' then 'published' when 'hide' then 'hidden' else 'pending' end,review_reason=btrim(action_reason),reviewed_by=(select auth.uid()),reviewed_at=clock_timestamp(),updated_at=clock_timestamp() where id=q.id;
 end if;
 return q.id;
end;$$;
revoke all on function public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text),public.cheongla_list_new_inquiries(integer),public.cheongla_review_new_inquiry(uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text),public.cheongla_list_new_inquiries(integer) to anon,authenticated;
grant execute on function public.cheongla_review_new_inquiry(uuid,text,text,timestamptz) to authenticated;
-- Restrictive policies also stop access from an already-issued login session.
create or replace function cheongla_private.can_use_member_services() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.cheongla_profiles where id=(select auth.uid()) and approval_status='approved' and membership_state='active');
$$;
revoke all on function cheongla_private.can_use_member_services() from public,anon,authenticated;
grant execute on function cheongla_private.can_use_member_services() to authenticated;
do $$declare t record;begin
 for t in select tablename from pg_catalog.pg_tables where schemaname='public' and tablename like 'cheongla_%' and tablename not in ('cheongla_profiles','cheongla_new_inquiries') loop
  execute format('create policy cheongla_active_member_gate on public.%I as restrictive for all to authenticated using ((select cheongla_private.can_use_member_services())) with check ((select cheongla_private.can_use_member_services()))',t.tablename);
 end loop;
end;$$;
notify pgrst,'reload schema';
commit;
