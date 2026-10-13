-- 과목 Q&A 접근·작성·사진 첨부를 중지합니다. 상담문의와 다른 서비스는 유지합니다.
begin;
revoke all on public.cheongla_questions,public.cheongla_answers,
public.cheongla_qa_messages,public.cheongla_qa_photos from public,anon,authenticated;

create or replace function cheongla_private.can_read_question(target_student uuid,target_subject text)
returns boolean language sql stable security definer set search_path='' as $$ select false; $$;
create or replace function cheongla_private.can_answer_question(target_subject text)
returns boolean language sql stable security definer set search_path='' as $$ select false; $$;
create or replace function cheongla_private.can_use_photo(path text,operation text)
returns boolean language sql stable security definer set search_path='' as $$ select false; $$;

revoke all on function public.cheongla_save_answer(uuid,text,timestamptz),
public.cheongla_reserve_photo(uuid,bigint),public.cheongla_finish_photo(uuid),
public.cheongla_remove_photo_record(uuid),public.cheongla_photo_usage()
from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
