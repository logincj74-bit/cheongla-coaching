import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite(), read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
const migrations=readdirSync(new URL('../supabase/migrations/',import.meta.url));
const apply=async suffix=>db.exec(read('../supabase/migrations/'+migrations.find(f=>f.endsWith(suffix))));
const roles=['owner','english_director','math_director','manager','student','parent','korean_teacher','suspended','pending'];
const ids=Object.fromEntries(roles.map((r,i)=>[r,`10000000-0000-0000-0000-00000000000${i+1}`]));
async function as(role,fn){await db.exec(`begin;set local role authenticated;set local request.jwt.claim.sub='${ids[role]}';`);try{await fn();}finally{await db.exec('rollback');}}
async function forbidden(sql,params=[]){await db.exec('savepoint denial');await assert.rejects(db.query(sql,params),{code:'42501'});await db.exec('rollback to savepoint denial');}
try{
 await db.exec(read('./journal-notifications-local-bootstrap.sql'));
 await db.exec(`create function cheongla_private.is_principal()returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid() and role='owner' and approval_status='approved' and membership_state='active')$$;
 create or replace function cheongla_private.can_use_member_services()returns boolean language sql as $$select true$$;
 create function cheongla_private.can_use_mbti_study()returns boolean language sql as $$select false$$;
 create table public.cheongla_mbti_preferences(user_id uuid primary key,mbti text);
 alter table public.cheongla_mbti_preferences enable row level security;grant select,insert,update,delete on public.cheongla_mbti_preferences to authenticated;create policy fixture_existing_access on public.cheongla_mbti_preferences for all to authenticated using(true)with check(true);`);
 await db.exec(read('../067_mbti_guide_editor.sql'));
 await apply('_mbti_introduction.sql');await apply('_mbti_learning_articles.sql');await apply('_mbti_study_operations.sql');
 for(const table of ['preferences','guides','introductions','learning_articles','operation_references','prescriptions'])await db.exec(`create policy principal_only_role_release on public.cheongla_mbti_${table} as restrictive for select to authenticated using(cheongla_private.is_principal());`);
 for(const role of roles)await db.query('insert into public.cheongla_profiles(id,role,approval_status,membership_state)values($1,$2,$3,$4)',[ids[role],['suspended','pending'].includes(role)?'owner':role,role==='pending'?'pending':'approved',role==='suspended'?'suspended':'active']);
 await db.query("insert into public.cheongla_mbti_preferences values($1,'ENFP')",[ids.student]);
 await apply('_mbti_manager_collaboration.sql');
 await apply('_mbti_principals_only.sql');
 await db.exec(read('../drafts/mbti-library-schema.sql'));await db.exec(read('../drafts/mbti-articles-schema.sql'));
 for(const[table,file]of [['mbti_library','mbti-library-2022'],['mbti_articles','mbti-articles-2026']])for(const content of JSON.parse(read('../data/'+file+'.json')).documents)await db.query('insert into cheongla_private.'+table+'(code,content)values($1,$2)',[content.code,content]);
 const content={title:'검증',subtitle:'테스트',overview:[{title:'유형',body:'본문'}],subjects:{english_reading:'독해'},groupIntroductions:{english:{title:'영어',body:'학습법'}}};
 for(const role of ['owner','english_director','math_director'])await as(role,async()=>{
  assert.equal((await db.query('select cheongla_private.can_use_mbti_study() as allowed')).rows[0].allowed,true);
  for(const [table,where] of [['introductions','true'],['learning_articles',"category='groups'"]]){
   const full='public.cheongla_mbti_'+table;
   assert.equal((await db.query(`update ${full} set body='공동편집 검증' where ${where} returning id`)).rows.length,1);
   assert.equal((await db.query(`delete from ${full} where ${where} returning id`)).rows.length,0);
   await db.exec(`update ${full} set archived_at=now() where ${where};update ${full} set archived_at=null where ${where};update ${full} set archived_at=now() where ${where};`);
   assert.equal((await db.query(`delete from ${full} where ${where} returning id`)).rows.length,1);
  }
  for(const [kind,code,total]of [['library','NF',20],['articles','parent_sj',8]]){
   const rows=(await db.query('select public.cheongla_mbti_'+kind+'_list() as value')).rows[0].value;assert.equal(rows.length,total);const row=rows.find(x=>x.code===code);
   await db.query('select public.cheongla_mbti_'+kind+'_save($1,1,$2,$3,$4,$5,$6)',[code,row.content.title,row.content.frontmatter,row.content.sections[0].title,'원장만 수정하는 본문',row.revision]);
   await db.query('select public.cheongla_mbti_'+kind+"_action($1,'archive',$2,1)",[code,row.revision+1]);
   await db.query('select public.cheongla_mbti_'+kind+"_action($1,'restore',$2,1)",[code,row.revision+2]);
  }
  await db.query('select public.cheongla_save_mbti_guide($1,$2,null)',['INTJ',content]);
  await assert.rejects(db.query('select public.cheongla_save_mbti_guide($1,$2,null)',['INTJ',content]),/다른 원장·실장/);
 });
 for(const role of ['manager','student','parent','korean_teacher','suspended','pending'])await as(role,async()=>{
  assert.equal((await db.query('select cheongla_private.can_use_mbti_study() as allowed')).rows[0].allowed,false);
  assert.equal((await db.query('select * from public.cheongla_mbti_introductions')).rows.length,0);
  for(const kind of ['library','articles']){
   for(const sql of ['select public.cheongla_mbti_'+kind+'_list()',"select public.cheongla_mbti_"+kind+"_save('NF',1,'제목','','항목','차단',1)","select public.cheongla_mbti_"+kind+"_action('NF','archive',1,null)","select public.cheongla_mbti_"+kind+"_empty_trash('[]'::jsonb)"]){await forbidden(sql);}
  }
  await forbidden('select * from public.cheongla_mbti_operation_students()');
  for(const table of ['guides','learning_articles','operation_references','prescriptions','preferences'])assert.equal((await db.query('select * from public.cheongla_mbti_'+table)).rows.length,0);
  assert.equal((await db.query("update public.cheongla_mbti_preferences set mbti='INTJ' returning user_id")).rows.length,0);
  await forbidden("insert into public.cheongla_mbti_preferences values($1,'INTJ')",[ids[role]]);
  assert.equal((await db.query("update public.cheongla_mbti_learning_articles set body='차단' returning id")).rows.length,0);
  await assert.rejects(db.query('select public.cheongla_save_mbti_guide($1,$2,null)',['INTJ',content]),{code:'42501'});
 });
 console.log('PASS principals-only MBTI: owner/English director/math director retain all 28 documents, editing and trash; manager/student/parent/teacher/pending/suspended denied by all eight library RPCs, legacy guide/student RPCs and six restrictive table policies; no production users impersonated.');
}finally{await db.close();}
