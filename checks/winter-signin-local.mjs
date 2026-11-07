import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

const dir=new URL('../supabase/migrations/',import.meta.url);
const migration=readdirSync(dir).find(name=>name.endsWith('_winter_signin_handoff.sql'));
assert(migration);
const db=new PGlite();
const approved='10000000-0000-0000-0000-000000000001';
const staff='10000000-0000-0000-0000-000000000002';
const pending='10000000-0000-0000-0000-000000000003';
try {
 await db.exec(readFileSync(new URL('journal-notifications-local-bootstrap.sql',import.meta.url),'utf8'));
 await db.exec(readFileSync(new URL(migration,dir),'utf8'));
 await db.exec(`insert into public.cheongla_profiles(id,role,approval_status,membership_state)
 values ('${approved}','student','approved','active'),('${staff}','owner','approved','active'),('${pending}','parent','pending','active')`);
 async function as(role,id,fn){
   await db.exec('begin');
   try{
     await db.exec(`set local role ${role}; set local request.jwt.claim.sub='${id}'`);
     const value=await fn();
     await db.exec('commit');
     return value;
   }catch(e){await db.exec('rollback');throw e;}
 }
 const issue=()=>db.query('select public.cheongla_issue_winter_signin() as code');
 const redeem=code=>as('anon','',async()=>(await db.query('select public.cheongla_redeem_winter_signin($1) as subject',[code])).rows[0].subject);
 await assert.rejects(as('anon','',issue),{code:'42501'});
 await assert.rejects(as('authenticated',staff,issue),{code:'42501'});
 await assert.rejects(as('authenticated',pending,issue),{code:'42501'});
 const {rows:[{code}]}=await as('authenticated',approved,issue);
 assert.match(code,/^[0-9a-f]{64}$/);
 const internal=(await db.query('select encode(code_hash,\'hex\') as hash from cheongla_private.winter_signin_codes')).rows[0];
 assert.notEqual(internal.hash,code);
 assert.equal(await redeem(code),approved);
 assert.equal(await redeem(code),null);
 const expired=(await as('authenticated',approved,issue)).rows[0].code;
 await db.exec("update cheongla_private.winter_signin_codes set expires_at=now()-interval '1 second'");
 assert.equal(await redeem(expired),null);
 const suspended=(await as('authenticated',approved,issue)).rows[0].code;
 await db.exec(`update public.cheongla_profiles set approval_status='suspended' where id='${approved}'`);
 assert.equal(await redeem(suspended),null);
} finally {await db.close();}
console.log('PASS: approved member eligibility, hash storage, expiration, revocation and one-time redemption.');
