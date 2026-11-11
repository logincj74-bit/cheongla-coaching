DO $patch$
declare r record; s text;
begin
for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and p.proname in ('cheongla_journal_push_preference','cheongla_set_journal_push_preference','cheongla_claim_push_deliveries')) or (n.nspname='cheongla_private' and p.proname='enqueue_push_notification')
loop
s:=pg_get_functiondef(r.oid);
s:=replace(s,'cheongla_private.can_manage_life()','cheongla_private.can_use_member_services()');
s:=replace(s,'item.source_kind=''staff_journal''and exists','exists');
s:=replace(s,'new.source_kind=''staff_journal''and exists','exists');
s:=replace(s,'n.source_kind=''staff_journal''and n.recipient_id','n.recipient_id');
execute s;
end loop;
end;$patch$;