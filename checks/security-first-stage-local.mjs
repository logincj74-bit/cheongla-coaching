import assert from 'node:assert/strict';import fs from 'node:fs';import {PGlite} from '@electric-sql/pglite';
const db=new PGlite(),read=p=>fs.readFileSync(p,'utf8'),ids=Object.fromEntries(['owner','english_director','math_director','manager','student','other','parent','pending','suspended'].map((r,i)=>[r,'10000000-0000-0000-0000-'+String(i+1).padStart(12,'0')]));
const as=async(role,dbrole='authenticated')=>{await db.exec('reset role');await db.query("select set_config('test.user',$1,false)",[ids[role]||'']);await db.exec('set role '+dbrole);};
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema cheongla_private;
 create function auth.uid()returns uuid language sql as $$select nullif(current_setting('test.user',true),'')::uuid$$;
 create table public.cheongla_profiles(id uuid primary key,role text,approval_status text,membership_state text,full_name text);
 create table public.cheongla_board_posts(id uuid primary key default gen_random_uuid(),author_id uuid,author_name text,title text,body text,visibility text,updated_at timestamptz default clock_timestamp(),deleted_at timestamptz);
 create table public.cheongla_new_inquiries(id uuid primary key default gen_random_uuid(),visitor_key uuid,submission_key uuid,contact_name text,contact_phone text,applicant_role text,title text,body text,visibility text,author_id uuid,risk_flags jsonb,created_at timestamptz default clock_timestamp());
 create table cheongla_private.inquiry_blocks(inquiry_id uuid,enabled boolean);
 create function cheongla_private.inquiry_risk_flags(text)returns jsonb language sql as $$select '[]'::jsonb$$;
 create function cheongla_private.can_use_member_services()returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid()and approval_status='approved'and membership_state='active')$$;
 create function cheongla_private.can_manage_life()returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid()and role in('owner','english_director','math_director','manager')and approval_status='approved'and membership_state='active')$$;
 create function cheongla_private.can_manage_consultations()returns boolean language sql security definer set search_path='' as $$select cheongla_private.can_manage_life()$$;
 create function cheongla_private.can_manage_mbti_operations()returns boolean language sql security definer set search_path='' as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid()and role in('owner','english_director','math_director')and approval_status='approved'and membership_state='active')$$;`);
 for(const [role,id]of Object.entries(ids))await db.query('insert into public.cheongla_profiles values($1,$2,$3,$4,$5)',[id,['pending','suspended'].includes(role)?'owner':role,role==='pending'?'pending':'approved',role==='suspended'?'suspended':'active',role]);
 await db.exec(read('checks/post-submission-baseline.sql'));
 await db.exec(read('supabase/migrations/20261118080619_private_mbti_catalog_and_account_owned_inquiries.sql'));
 await db.exec(`insert into cheongla_private.mbti_legacy_catalog(content)values('{"schemaVersion":1,"types":{"INTJ":{"title":"synthetic"}}}');
 revoke all on public.cheongla_profiles,public.cheongla_board_posts,public.cheongla_new_inquiries from public,anon,authenticated;
 revoke all on function public.cheongla_save_board_post(uuid,text,text,text,timestamptz),public.cheongla_submit_new_inquiry(uuid,uuid,text,text,text,text,text,text,boolean,text) from public,anon,authenticated;
 create function cheongla_private.can_read_board_post(target_post uuid)returns boolean language sql security definer set search_path='' as $$select cheongla_private.can_use_member_services()and exists(select 1 from public.cheongla_board_posts p where p.id=target_post and p.deleted_at is null and(p.visibility='public'or p.author_id=auth.uid()or cheongla_private.can_manage_consultations()))$$;
 grant usage on schema cheongla_private to authenticated;grant execute on function cheongla_private.can_read_board_post(uuid) to authenticated;`);
 for(const role of ['owner','english_director','math_director']){await as(role);assert.equal((await db.query('select public.cheongla_mbti_legacy_catalog() value')).rows[0].value.types.INTJ.title,'synthetic');await assert.rejects(db.query('select * from cheongla_private.mbti_legacy_catalog'),{code:'42501'});}
 for(const role of ['manager','student','parent','pending','suspended']){await as(role);await assert.rejects(db.query('select public.cheongla_mbti_legacy_catalog()'),{code:'42501'});}
 await as(null,'anon');await assert.rejects(db.query('select public.cheongla_mbti_legacy_catalog()'),{code:'42501'});await assert.rejects(db.query("select public.cheongla_save_board_post_secure(null,'a','b','private',null,null)"),{code:'42501'});
 const submit="select public.cheongla_submit_new_inquiry_secure($1,$2,'fixture','01000000000','parent','문의','본문','private',$3,$4,null) value",visitor='20000000-0000-0000-0000-000000000001',token='20000000-0000-0000-0000-000000000002';
 await assert.rejects(db.query(submit,[visitor,token,false,'']),/동의/);await assert.rejects(db.query(submit,[visitor,token,true,'bot']),/동의/);
 const first=(await db.query(submit,[visitor,token,true,''])).rows[0].value;assert.equal((await db.query(submit,[visitor,token,true,''])).rows[0].value,first,'duplicate submission must remain idempotent');await assert.rejects(db.query(submit,[visitor,'20000000-0000-0000-0000-000000000003',true,'']),/기다린/);
 await as('student');const post=(await db.query("select public.cheongla_save_board_post_secure(null,'제목','기존 본문','private',null,null) value")).rows[0].value;assert.equal((await db.query('select cheongla_private.can_read_board_post($1) value',[post])).rows[0].value,true);
 await as('other');assert.equal((await db.query('select cheongla_private.can_read_board_post($1) value',[post])).rows[0].value,false);await assert.rejects(db.query("select public.cheongla_save_board_post_secure($1,'변조','본문','private',null,null)",[post]),{code:'42501'});
 await as('manager');assert.equal((await db.query('select cheongla_private.can_read_board_post($1) value',[post])).rows[0].value,true);
 await db.exec('reset role');const row=(await db.query('select * from public.cheongla_board_posts where id=$1',[post])).rows[0];await as('student');await db.query("select public.cheongla_save_board_post_secure($1,'수정','수정 본문','private',$2,null)",[post,row.updated_at]);await assert.rejects(db.query("select public.cheongla_save_board_post_secure($1,'충돌','본문','private',$2,'1234')",[post,row.updated_at]),/변경/);
 for(const role of ['pending','suspended']){await as(role);await assert.rejects(db.query("select public.cheongla_save_board_post_secure(null,'제목','본문','private',null,null)"),{code:'42501'});}
 console.log('PASS isolated DB: private legacy catalog/RPC role denial; PIN-free owner-based private posts, edit conflict and cross-account protection; existing anonymous consent/honeypot/duplicate/rate limits retained. No production writes or users used.');
}finally{await db.close();}
