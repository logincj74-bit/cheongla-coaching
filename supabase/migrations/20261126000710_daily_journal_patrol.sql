-- Validate patrol text and colour runs, and keep them when a pre-update client
-- saves only the three original fields. A purge must still clear the whole record.
create function cheongla_private.guard_daily_journal_patrol()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.purged_at is not null then
    return new;
  end if;

  if not (new.fields ? 'patrol' or new.field_inks ? 'patrol') then
    if old.fields ? 'patrol' then
      new.fields := jsonb_set(new.fields, '{patrol}', old.fields->'patrol');
      new.field_inks := jsonb_set(new.field_inks, '{patrol}', old.field_inks->'patrol');
    end if;
  elsif jsonb_typeof(new.fields->'patrol') is distinct from 'string'
     or length(new.fields->>'patrol') > 60000
     or cheongla_private.valid_journal_inks(new.field_inks->'patrol', new.fields->>'patrol') is not true then
    raise exception '순시상황은 60,000자 이내이며 글씨색과 본문이 일치해야 합니다.' using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function cheongla_private.guard_daily_journal_patrol() from public, anon, authenticated;

create trigger guard_daily_journal_patrol
before update of fields, field_inks on cheongla_private.daily_journals
for each row execute function cheongla_private.guard_daily_journal_patrol();
