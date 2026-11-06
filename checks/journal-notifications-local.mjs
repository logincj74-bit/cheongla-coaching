import fs from'node:fs';
import {createJournalTestDb}from'./journal-notifications-test-db.mjs';
const db=await createJournalTestDb();
try{
 const results=await db.exec(fs.readFileSync(new URL('./journal-notifications-cases.sql',import.meta.url),'utf8'));
 for(const result of results)for(const row of result.rows||[])if(row.result)console.log(row.result);
 console.log('PASS isolated PostgreSQL; production journal RPC/permission/outbox function snapshots; fake local subscriptions only; no network dispatcher installed');
}catch(e){console.error(e.message,e.code,e.detail||'',e.where||'');process.exitCode=1;}finally{await db.close();}
