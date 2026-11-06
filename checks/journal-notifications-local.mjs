import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const here=path.dirname(new URL(import.meta.url).pathname),repo=path.dirname(here);
const require=createRequire(import.meta.url);
const {PGlite}=require('@electric-sql/pglite');const db=new PGlite();
try{
 await db.exec(fs.readFileSync(path.join(here,'journal-notifications-local-bootstrap.sql'),'utf8'));
 const schema=fs.readFileSync(path.join(repo,'074_daily_shared_journal.sql'),'utf8').split('-- Called only')[0];await db.exec(schema);
 await db.exec('set check_function_bodies=off');
 const defs=JSON.parse(fs.readFileSync(path.join(here,'fixtures/journal-notification-functions.json'),'utf8'));
 for(const {definition}of defs)await db.exec(definition);
 await db.exec('set check_function_bodies=on');
 await db.exec('create trigger notification_outbox after insert on public.cheongla_notifications for each row execute function cheongla_private.enqueue_push_notification()');
 await db.exec(fs.readFileSync(path.join(repo,'supabase/migrations/20261106232149_daily_journal_staff_change_notifications.sql'),'utf8'));
 await db.exec("create policy own_staff_alerts on public.cheongla_notifications for select to authenticated using(recipient_id=auth.uid()and cheongla_private.can_read_notification(source_kind,source_id,student_id))");
 const results=await db.exec(fs.readFileSync(path.join(here,'journal-notifications-cases.sql'),'utf8'));
 for(const result of results)for(const row of result.rows||[])if(row.result)console.log(row.result);
 console.log('PASS isolated PostgreSQL; production journal RPC/permission/outbox function snapshots; fake local subscriptions only; no network dispatcher installed');
}catch(e){console.error(e.message,e.code,e.detail||'',e.where||'');process.exitCode=1;}finally{await db.close();}
