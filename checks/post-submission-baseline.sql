-- Existing submission implementations captured read-only before the wrapper change.
CREATE OR REPLACE FUNCTION public.cheongla_save_board_post(target_post uuid, post_title text, post_body text, post_visibility text, expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare me public.cheongla_profiles%rowtype;old public.cheongla_board_posts%rowtype;result_id uuid;
begin
 select * into me from public.cheongla_profiles
 where id=(select auth.uid()) and approval_status='approved';
 if not found then raise exception '승인된 계정으로 이용해 주세요.' using errcode='42501';end if;
 if post_title is null or length(btrim(post_title)) not between 1 and 150
 or post_body is null or length(btrim(post_body)) not between 1 and 10000
 or post_visibility is null or post_visibility not in ('public','private') then
 raise exception '제목, 내용과 공개 여부를 확인해 주세요.';end if;
 if target_post is null then
  if expected_updated_at is not null then raise exception '새 글의 저장 정보를 확인해 주세요.';end if;
  insert into public.cheongla_board_posts(author_id,author_name,title,body,visibility)
  values(me.id,me.full_name,btrim(post_title),btrim(post_body),post_visibility) returning id into result_id;
 else
  select * into old from public.cheongla_board_posts where id=target_post for update;
  if not found or not (old.author_id=me.id or cheongla_private.can_manage_consultations()) then
   raise exception '글을 수정할 권한이 없습니다.' using errcode='42501';end if;
  if old.updated_at is distinct from expected_updated_at then raise exception '글이 변경되었습니다. 다시 확인해 주세요.';end if;
  update public.cheongla_board_posts set title=btrim(post_title),body=btrim(post_body),
  visibility=post_visibility,updated_at=clock_timestamp() where id=target_post returning id into result_id;
 end if;
 return result_id;
end;$function$;

CREATE OR REPLACE FUNCTION public.cheongla_submit_new_inquiry(visitor_token uuid, submission_token uuid, visitor_name text, visitor_phone text, visitor_role text, inquiry_title text, inquiry_body text, inquiry_visibility text, contact_consent boolean, website_field text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end;$function$;
