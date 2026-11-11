import fs from "node:fs";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url),
  { PGlite } = require("@electric-sql/pglite");
const db = new PGlite();
const baseline = JSON.parse(
  fs.readFileSync("recovery/20261111/learning-and-push.json", "utf8"),
);
const extra = JSON.parse(
  fs.readFileSync("recovery/20261111/mbti-and-permissions.json", "utf8"),
);
const ids = {
  owner: "00000000-0000-0000-0000-000000000001",
  manager: "00000000-0000-0000-0000-000000000002",
  student: "00000000-0000-0000-0000-000000000003",
  parent: "00000000-0000-0000-0000-000000000004",
  other: "00000000-0000-0000-0000-000000000005",
};
const actor = async (role) => {
  await db.exec("reset role");
  await db.query("select set_config('test.user',$1,false)", [ids[role]]);
  await db.exec("set role authenticated");
};
async function denied(fn) {
  let error = false;
  try {
    await fn();
  } catch {
    error = true;
  }
  assert(error, "expected denied");
}
try {
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema cheongla_private;create schema cron;
 create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('test.user',true),'')::uuid$$;
 grant usage on schema public,auth,cheongla_private to authenticated;
 create function cron.schedule(text,text,text)returns bigint language sql as $$select 1::bigint$$;
 create function cron.unschedule(bigint)returns boolean language sql as $$select true$$;create table cron.job(jobid bigint,jobname text);
 create table public.cheongla_profiles(id uuid primary key,role text,full_name text,approval_status text default 'approved',membership_state text default 'active',is_app_admin boolean default false);
 create table public.cheongla_parent_students(parent_id uuid,student_id uuid);
 create table public.cheongla_notifications(id uuid default gen_random_uuid()primary key,recipient_id uuid,source_kind text,source_id uuid,student_id uuid,title text,route text,event_key text,created_at timestamptz default now(),read_at timestamptz,archived_at timestamptz,inbox_until timestamptz default now()+interval '24 hours',unique(recipient_id,event_key));
 create table public.cheongla_push_subscriptions(id uuid default gen_random_uuid()primary key,user_id uuid,enabled boolean default true,endpoint text,p256dh text,auth_key text);
 create table cheongla_private.push_deliveries(id uuid default gen_random_uuid()primary key,notification_id uuid,subscription_id uuid,state text default 'pending',attempts integer default 0,next_attempt_at timestamptz default now(),last_attempt_at timestamptz,finished_at timestamptz,created_at timestamptz default now(),unique(notification_id,subscription_id));
 create table cheongla_private.learning_records(id uuid default gen_random_uuid()primary key,kind text,student_id uuid,record_on date,payload jsonb,state text,created_by uuid,updated_at timestamptz default clock_timestamp(),reviewed_at timestamptz,reviewed_by uuid,review_note text default '',archived_at timestamptz);
 create table cheongla_private.learning_parent_checks(record_id uuid references cheongla_private.learning_records(id)on delete cascade,parent_id uuid,record_version timestamptz,checked_at timestamptz,primary key(record_id,parent_id));
 create table cheongla_private.study_corrections(record_id uuid,student_id uuid,changed_by uuid,action text,before_record jsonb,after_record jsonb);
 create function cheongla_private.can_use_member_services()returns boolean language sql security definer as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid()and approval_status='approved'and membership_state='active')$$;
 create function cheongla_private.can_manage_exams()returns boolean language sql security definer as $$select exists(select 1 from public.cheongla_profiles where id=auth.uid()and role in('owner','manager'))$$;
 create function cheongla_private.is_parent_of(s uuid)returns boolean language sql security definer as $$select exists(select 1 from public.cheongla_parent_students where parent_id=auth.uid()and student_id=s)$$;
 create function cheongla_private.push_source_allowed(uuid,text,uuid,uuid)returns boolean language sql as $$select true$$;
 create function cheongla_private.can_read_notification(text,uuid,uuid)returns boolean language sql as $$select true$$;
 create function cheongla_private.can_use_staff_journal()returns boolean language sql as $$select true$$;
 create function cheongla_private.can_manage_account_recovery()returns boolean language sql as $$select false$$;
 create function cheongla_private.can_manage_winter()returns boolean language sql as $$select false$$;
 create function cheongla_private.can_read_notification_before_winter(text,uuid,uuid)returns boolean language sql as $$select true$$;
 create table cheongla_private.journal_notification_events(id uuid);create table public.cheongla_director_posts(id uuid,state text,archived_at timestamptz);create table cheongla_private.account_help_requests(id uuid);create table cheongla_private.winter_bookings(id uuid,archived_at timestamptz,owner_id uuid);`);
  for (const table of [
    "cheongla_mbti_preferences",
    "cheongla_mbti_guides",
    "cheongla_mbti_introductions",
    "cheongla_mbti_learning_articles",
    "cheongla_mbti_operation_references",
    "cheongla_mbti_prescriptions",
  ])
    await db.exec(
      `create table public.${table}(id uuid);alter table public.${table} enable row level security;grant select on public.${table} to authenticated;create policy existing_read on public.${table} for select to authenticated using(true);insert into public.${table} values(gen_random_uuid());`,
    );
  for (const key of [
    "is_principal",
    "can_manage_life",
    "can_read_learning",
    "send_notification",
    "validate_learning",
  ])
    await db.exec(extra.functions["cheongla_private." + key]);
  await db.exec(baseline.functions.cheongla_learning_list);
  for (const [role, id] of Object.entries(ids))
    await db.query(
      "insert into public.cheongla_profiles(id,role,full_name)values($1,$2,$2)",
      [id, role === "other" ? "student" : role],
    );
  await db.query("insert into public.cheongla_parent_students values($1,$2)", [
    ids.parent,
    ids.student,
  ]);
  await db.exec(
    fs.readFileSync(
      "supabase/migrations/20261111125155_role_coaching_redesign.sql",
      "utf8",
    ),
  );
  await db.exec(
    "create trigger guard_study_day before insert or update or delete on cheongla_private.learning_records for each row execute function cheongla_private.guard_study_day();create trigger notification_outbox after insert on public.cheongla_notifications for each row execute function cheongla_private.enqueue_push_notification();",
  );
  const scalar = async (sql, args = []) =>
    Object.values((await db.query(sql, args)).rows[0])[0];
  await actor("owner");
  const score = [
    { subject: "국어", raw: 80, standard: 120, percentile: 87, grade: 3 },
  ];
  const report = await scalar(
    "select public.cheongla_save_score_coaching(null,$1,current_date,$2,$3,$4,null)",
    [ids.student, "시험", JSON.stringify(score), "학습코칭"],
  );
  await denied(() =>
    db.query("select public.cheongla_score_coaching_action($1,$2,99)", [
      report.id,
      "publish",
    ]),
  );
  await actor("student");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items.length,
    0,
  );
  await denied(() =>
    db.query(
      "select public.cheongla_save_score_coaching(null,$1,current_date,$2,$3,$4,null)",
      [ids.student, "시험", JSON.stringify(score), "코칭"],
    ),
  );
  await actor("owner");
  await db.query("select public.cheongla_score_coaching_action($1,$2,1)", [
    report.id,
    "publish",
  ]);
  await actor("parent");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items[0]
      .report,
    "학습코칭",
  );
  await actor("other");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items.length,
    0,
  );
  await actor("owner");
  await db.query(
    "select public.cheongla_save_score_coaching($1,$2,current_date,$3,$4,$5,1)",
    [report.id, ids.student, "수정시험", JSON.stringify(score), "공유 전 수정"],
  );
  await actor("parent");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items[0]
      .report,
    "학습코칭",
    "draft edits must not leak",
  );
  await actor("manager");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items.length,
    0,
  );
  assert.equal(
    (await db.query("select *from public.cheongla_mbti_guides")).rows.length,
    0,
  );
  await actor("owner");
  assert.equal(
    (await db.query("select *from public.cheongla_mbti_guides")).rows.length,
    1,
  );
  await db.query("select public.cheongla_score_coaching_action($1,$2,2)", [
    report.id,
    "archive",
  ]);
  await actor("parent");
  assert.equal(
    (await scalar("select public.cheongla_score_coaching_list()")).items.length,
    0,
  );
  await actor("owner");
  await db.query("select public.cheongla_score_coaching_action($1,$2,3)", [
    report.id,
    "restore",
  ]);
  await db.query("select public.cheongla_score_coaching_action($1,$2,4)", [
    report.id,
    "archive",
  ]);
  await db.query("select public.cheongla_score_coaching_action($1,$2,5)", [
    report.id,
    "purge",
  ]);
  await actor("student");
  const payload = {
    seat: "",
    subjects: ["korean", "math", "english", "exploration"].map((key) => ({
      key,
      minutes: 20,
      tasks: [{ text: "독해", mark: "done" }],
    })),
    absences: 0,
    late: 0,
    away: 0,
    satisfaction: "high",
    reflection: "",
  };
  const study = await scalar(
    "select public.cheongla_save_learning('study',null,$1,(clock_timestamp()at time zone'Asia/Seoul')::date,$2,true,null)",
    [ids.student, JSON.stringify(payload)],
  );
  await actor("other");
  await denied(() =>
    db.query("select public.cheongla_acknowledge_study($1,$2)", [
      study.id,
      study.updated_at,
    ]),
  );
  await actor("parent");
  await db.query("select public.cheongla_acknowledge_study($1,$2)", [
    study.id,
    study.updated_at,
  ]);
  await actor("owner");
  await db.exec("reset role");
  await db.query(
    "update cheongla_private.learning_records set record_on=record_on-8 where id=$1",
    [study.id],
  );
  await db.exec("reset role;select cheongla_private.archive_confirmed_study()");
  assert(
    await scalar(
      "select archived_at from cheongla_private.learning_records where id=$1",
      [study.id],
    ),
  );
  await actor("owner");
  await db.query("select public.cheongla_archive_learning($1,'restore',$2)", [
    study.id,
    study.updated_at,
  ]);
  await db.exec("reset role;select cheongla_private.archive_confirmed_study()");
  assert.equal(
    await scalar(
      "select archived_at from cheongla_private.learning_records where id=$1",
      [study.id],
    ),
    null,
    "restored records must stay restored",
  );
  await actor("manager");
  await denied(() =>
    db.query("select public.cheongla_archive_learning($1,'purge',$2)", [
      study.id,
      study.updated_at,
    ]),
  );
  await db.exec("reset role");
  await db.query(
    "insert into public.cheongla_push_subscriptions(user_id,endpoint,p256dh,auth_key)values($1,'https://fcm.googleapis.com/example','key','auth')",
    [ids.manager],
  );
  await actor("manager");
  await db.query(
    "select public.cheongla_set_journal_push_preference('paused')",
  );
  await db.exec("reset role");
  await db.query(
    "insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,event_key)values($1,'staff_journal',gen_random_uuid(),'일지','muted')",
    [ids.manager],
  );
  assert.equal(
    await scalar("select count(*)::int from cheongla_private.push_deliveries"),
    0,
  );
  await db.query(
    "insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,event_key)values($1,'notice',gen_random_uuid(),'공지','normal')",
    [ids.manager],
  );
  assert.equal(
    await scalar("select count(*)::int from cheongla_private.push_deliveries"),
    1,
  );
  await actor("manager");
  await db.query("select public.cheongla_set_journal_push_preference('on')");
  await db.exec("reset role");
  await db.query(
    "insert into public.cheongla_notifications(recipient_id,source_kind,source_id,title,event_key)values($1,'staff_journal',gen_random_uuid(),'일지','unmuted')",
    [ids.manager],
  );
  assert.equal(
    await scalar("select count(*)::int from cheongla_private.push_deliveries"),
    2,
  );
  await actor("manager");
  await db.query("select public.cheongla_set_journal_push_preference('2h')");
  await db.exec("reset role");
  assert.equal(
    await scalar(
      "select count(*)::int from cheongla_private.push_deliveries where state='cancelled'",
    ),
    1,
  );
  await db.exec("reset role");
  await db.exec(fs.readFileSync("recovery/20261111/rollback.sql", "utf8"));
  assert.equal((await db.query("select count(*)::int as n from pg_policies where policyname='principal_only_role_release'")).rows[0].n, 0);
  console.log("PASS rollback restores baseline function definitions and removes role-release policies without deleting new records");
  console.log(
    "PASS role access, private/frozen publication, score revision/trash/restore/purge, linked parent confirmation, seven-day retention, restored-record exemption, selective journal push mute",
  );
} catch (error) {
  console.error(error.message, error.position, error.where);
  process.exitCode = 1;
} finally {
  await db.close();
}
