do $migration$
declare
  original text := pg_get_functiondef('cheongla_private.seed_daily_journal(date)'::regprocedure);
  blocking_call text := $old$perform pg_advisory_xact_lock(hashtext('daily-journal:'||day::text));$old$;
begin
  if position(blocking_call in original) = 0 then
    raise exception 'Expected daily journal lock statement not found';
  end if;
  execute replace(original, blocking_call, $new$if not pg_try_advisory_xact_lock(hashtext('daily-journal:'||day::text)) then
    raise exception '다른 근무자의 저장이 진행 중입니다. 작성 내용을 그대로 두고 잠시 후 다시 저장해 주세요.' using errcode='55P03';
  end if;$new$);
end;
$migration$;
notify pgrst, 'reload schema';
