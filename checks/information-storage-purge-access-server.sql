begin;
insert into auth.users(id,email,raw_user_meta_data) values
('07910000-0000-4000-8000-000000000001','purge-video-check-manager@example.invalid','{"full_name":"삭제 권한 검증 관리자","contact_phone":"01000009101"}'),
('07910000-0000-4000-8000-000000000002','purge-video-check-student@example.invalid','{"full_name":"삭제 권한 검증 학생","contact_phone":"01000009102"}');
update public.cheongla_profiles set role=case when id='07910000-0000-4000-8000-000000000001'then'manager'else'student'end,approval_status='approved',membership_state='active' where id in('07910000-0000-4000-8000-000000000001','07910000-0000-4000-8000-000000000002');
insert into public.cheongla_information_posts(id,kind,title,body,status,deleted_at)values
('07910000-0000-4000-9000-000000000001','news','삭제 권한 검증','임시 검증 자료','published',clock_timestamp()),
('07910000-0000-4000-9000-000000000002','news','삭제 준비 전 검증','임시 검증 자료','published',clock_timestamp()),
('07910000-0000-4000-9000-000000000003','news','게시 상태 검증','임시 검증 자료','published',null);
insert into public.cheongla_information_files(post_id,object_path,filename,size_bytes,state)values
('07910000-0000-4000-9000-000000000001','purge-video-check/claimed.pdf','check.pdf',1,'ready'),
('07910000-0000-4000-9000-000000000002','purge-video-check/unclaimed.pdf','check.pdf',1,'ready'),
('07910000-0000-4000-9000-000000000003','purge-video-check/active.pdf','check.pdf',1,'ready');
insert into cheongla_private.content_purge_claims(post_id,record_version)select id,updated_at from public.cheongla_information_posts where id in('07910000-0000-4000-9000-000000000001','07910000-0000-4000-9000-000000000003');
select set_config('request.jwt.claim.sub','07910000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin
 if not cheongla_private.can_purge_information_file('purge-video-check/claimed.pdf')then raise exception 'manager cannot remove claimed trash';end if;
 if cheongla_private.can_purge_information_file('purge-video-check/unclaimed.pdf')then raise exception 'unclaimed file removable';end if;
 if cheongla_private.can_purge_information_file('purge-video-check/active.pdf')then raise exception 'active file removable';end if;
 if cheongla_private.can_purge_information_file('purge-video-check/missing.pdf')then raise exception 'unknown file removable';end if;
 if has_table_privilege('authenticated','cheongla_private.content_purge_claims','select')then raise exception 'private claims exposed';end if;
end;$$;
reset role;
select set_config('request.jwt.claim.sub','07910000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if cheongla_private.can_purge_information_file('purge-video-check/claimed.pdf')then raise exception 'student deletion allowed';end if;
end;$$;
reset role;
update public.cheongla_profiles set membership_state='withdrawn',approval_status='suspended',is_app_admin=false where id='07910000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','07910000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin
 if cheongla_private.can_purge_information_file('purge-video-check/claimed.pdf')then raise exception 'withdrawn staff deletion allowed';end if;
end;$$;
reset role;
select 'PASS manager claimed-trash allowed; unclaimed, published, unknown, student, withdrawn denied; private table remains inaccessible; no actual file deletions' as result;
rollback;
