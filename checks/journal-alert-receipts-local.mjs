import fs from'node:fs';
import {createJournalTestDb}from'./journal-notifications-test-db.mjs';
const db=await createJournalTestDb();
try{
 const migration=process.argv[2]||new URL('../supabase/migrations/20261106234313_journal_alert_inbox_and_read_receipts.sql',import.meta.url);await db.exec(fs.readFileSync(migration,'utf8'));if(!process.argv[2])await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261106234457_journal_inbox_invoker_role_check.sql',import.meta.url),'utf8'));
 const results=await db.exec(fs.readFileSync(new URL('./journal-alert-receipts-cases.sql',import.meta.url),'utf8'));
 for(const result of results)for(const row of result.rows||[])if(row.result)console.log(row.result);
}catch(e){console.error(e.message,e.code,e.detail||'',e.where||'');process.exitCode=1;}finally{await db.close();}
