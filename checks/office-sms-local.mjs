import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite(),read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
const roles=['owner','english_director','math_director','manager','student','parent','korean_teacher','pending','suspended'];
const ids=Object.fromEntries(roles.map((r,i)=>[r,`10000000-0000-0000-0000-00000000000${i+1}`]));
async function as(role,fn){await db.exec(`begin;set local role authenticated;set local request.jwt.claim.sub='${ids[role]}';`);try{return await fn();}finally{await db.exec('rollback');}}
try{
 await db.exec(read('./journal-notifications-local-bootstrap.sql'));
 await db.exec(`create table public.cheongla_tuition_settings(student_id uuid,enrolled_on date,monthly_fee integer);
 create table public.cheongla_parent_students(student_id uuid,parent_id uuid);
 create table cheongla_private.member_contacts(user_id uuid primary key,phone text,updated_at timestamptz default now());`);
 for(const role of roles)await db.query('insert into public.cheongla_profiles(id,full_name,role,approval_status,membership_state)values($1,$2,$3,$4,$5)',[ids[role],'검증 '+role,['pending','suspended'].includes(role)?'manager':role,role==='pending'?'pending':'approved',role==='suspended'?'suspended':'active']);
 await db.query('insert into public.cheongla_parent_students values($1,$2)',[ids.student,ids.parent]);
 await db.query('insert into cheongla_private.member_contacts values($1,$2)',[ids.parent,'01000000001']);
 const file=readdirSync(new URL('../supabase/migrations/',import.meta.url)).find(f=>f.endsWith('_office_sms_templates.sql'));
 await db.exec(read('../supabase/migrations/'+file));
 const contactFile=readdirSync(new URL('../supabase/migrations/',import.meta.url)).find(f=>f.endsWith('_office_sms_contact_edit.sql'));await db.exec(read('../supabase/migrations/'+contactFile));
 assert.equal((await db.query('select count(*)::int n from public.cheongla_office_sms_templates')).rows[0].n,20);
 assert.equal((await db.query("select has_table_privilege('anon','public.cheongla_office_sms_templates','select') x")).rows[0].x,false);
 for(const role of ['owner','english_director','math_director','manager'])await as(role,async()=>{
  assert.equal((await db.query('select * from public.cheongla_office_sms_templates')).rows.length,20);
  const people=(await db.query('select public.cheongla_office_sms_students() p')).rows[0].p;assert.equal(people.length,1);assert.equal(people[0].recipients.length,2);
  const saved=(await db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4) r',[ids.student,ids.parent,'01000000003','01000000001'])).rows[0].r;assert.equal(saved.phone,'01000000003');
  assert.equal((await db.query('select public.cheongla_office_sms_students() p')).rows[0].p[0].recipients.find(r=>r.id===ids.parent).phone,'01000000003');
  await db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4)',[ids.student,ids.student,'01000000004',null]);
  let row=(await db.query("insert into public.cheongla_office_sms_templates(title,category,audience,body)values('신규','상담','parent','{{학생이름}} 학생 안내')returning *")).rows[0];
  const changed=(await db.query("update public.cheongla_office_sms_templates set body='수정' where id=$1 and revision=$2 returning *",[row.id,row.revision])).rows[0];assert.equal(changed.revision,2);
  assert.equal((await db.query("update public.cheongla_office_sms_templates set body='덮어쓰기' where id=$1 and revision=$2 returning id",[row.id,row.revision])).rows.length,0);
  assert.equal((await db.query('delete from public.cheongla_office_sms_templates where id=$1 returning id',[row.id])).rows.length,0);
  await db.query('update public.cheongla_office_sms_templates set deleted_at=now() where id=$1',[row.id]);
  await db.query('update public.cheongla_office_sms_templates set deleted_at=null where id=$1',[row.id]);
  await db.query('update public.cheongla_office_sms_templates set deleted_at=now() where id=$1',[row.id]);
  assert.equal((await db.query('delete from public.cheongla_office_sms_templates where id=$1 returning id',[row.id])).rows.length,1);
 });
 await assert.rejects(as('manager',()=>db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4)',[ids.student,ids.parent,'01000000005','01000000000'])),/다른 곳에서 변경/);
 await assert.rejects(as('manager',()=>db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4)',[ids.student,ids.owner,'01000000005',null])),{code:'42501'});
 await assert.rejects(as('manager',()=>db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4)',[ids.student,ids.parent,'123','01000000001'])),{code:'22023'});
 for(const role of ['student','parent','korean_teacher','pending','suspended']){
  await as(role,async()=>{assert.equal((await db.query('select * from public.cheongla_office_sms_templates')).rows.length,0);assert.equal((await db.query("update public.cheongla_office_sms_templates set title='차단' returning id")).rows.length,0);});
  await assert.rejects(as(role,()=>db.query('select public.cheongla_office_sms_update_contact($1,$2,$3,$4)',[ids.student,ids.parent,'01000000005','01000000001'])),{code:'42501'});
  await assert.rejects(as(role,()=>db.query('select public.cheongla_office_sms_students()')),{code:'42501'});
  await assert.rejects(as(role,()=>db.query("insert into public.cheongla_office_sms_templates(title,category,body)values('차단','상담','차단')")),{code:'42501'});
 }
 console.log('PASS office SMS: 20 seeds, four staff roles CRUD, conflict guard, trash/restore/purge, scoped linked recipients, unauthorized and suspended denial');
}finally{await db.close();}
