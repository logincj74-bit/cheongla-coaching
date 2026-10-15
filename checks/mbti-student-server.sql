begin;
do $$declare st uuid;begin select id into st from public.cheongla_profiles where role='student'and approval_status='approved'and membership_state='active'limit 1;if st is null then raise exception '승인된 학생 계정이 없습니다.';end if;perform set_config('request.jwt.claim.sub',st::text,true);end;$$;
set local role authenticated;
do $$declare t text;begin
foreach t in array array['ISTJ','ISFJ','INFJ','INTJ','ISTP','ISFP','INFP','INTP','ESTP','ESFP','ENFP','ENTP','ESTJ','ESFJ','ENFJ','ENTJ']loop
 if public.cheongla_save_my_mbti(t)<>t then raise exception 'FAIL student save';end if;
 if not exists(select 1 from public.cheongla_mbti_preferences where user_id=auth.uid()and mbti=t)then raise exception 'FAIL student read';end if;
end loop;
if exists(select 1 from public.cheongla_mbti_preferences where user_id<>auth.uid())then raise exception 'FAIL other student exposure';end if;
begin perform public.cheongla_save_my_mbti('XXXX');raise exception 'FAIL invalid type';exception when raise_exception then if sqlerrm like 'FAIL%'then raise;end if;end;
end;$$;
reset role;
rollback;
select 'PASS: 승인된 학생 계정의 16유형 저장·본인 조회·다른 학생 유형 차단·잘못된 유형 차단. 원래 학생 정보는 롤백으로 유지.'as result;
