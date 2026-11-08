import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { JSDOM } from 'jsdom';

const read = file => readFileSync(new URL(file, import.meta.url), 'utf8');
const migrations = new URL('../supabase/migrations/', import.meta.url);
const migration = readdirSync(migrations).find(name => name.endsWith('_home_features_editor.sql'));
const db = new PGlite();
const table = 'public.cheongla_home_features';
const principal = '10000000-0000-0000-0000-000000000001';
const student = '10000000-0000-0000-0000-000000000002';
const path = '10000000-0000-0000-0000-000000000003.mp4';
const rows = async sql => (await db.query(sql)).rows;
async function as(role, id, action) {
  await db.exec('begin');
  try {
    await db.exec(`set local role ${role}; set local request.jwt.claim.sub = '${id}';`);
    await action();
    await db.exec('commit');
  } catch (error) {
    await db.exec('rollback');
    throw error;
  }
}

try {
  await db.exec(read('./journal-notifications-local-bootstrap.sql'));
  await db.exec(`
    create schema storage;
    grant usage on schema storage to anon, authenticated;
    create table storage.buckets(id text, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects(bucket_id text, name text);
    alter table storage.objects enable row level security;
    grant select on storage.objects to anon, authenticated;
    grant insert, delete on storage.objects to authenticated;
    insert into public.cheongla_profiles(id,role,approval_status,membership_state)
    values ('${principal}','english_director','approved','active'), ('${student}','student','approved','active');
  `);
  await db.exec(read('../supabase/migrations/' + migration));
  const seed = await rows('select * from ' + table);
  assert.equal(seed.length, 2);
  assert.equal(seed.find(row => row.kind === 'tour').original_video, true);
  await as('authenticated', student, async () => {
    assert.equal((await rows(`update ${table} set title = '변조' returning id`)).length, 0);
  });
  await as('authenticated', principal, async () => {
    assert.equal((await rows(`delete from ${table} returning id`)).length, 0);
    await db.exec(`insert into storage.objects values ('cheongla-home-videos','${path}')`);
    await db.exec(`update ${table} set video_path = '${path}', original_video = false where kind = 'tour'`);
    assert.equal((await rows('delete from storage.objects returning name')).length, 0);
  });
  await as('anon', '', async () => assert.equal((await rows('select * from storage.objects')).length, 1));
  await as('authenticated', principal, async () => {
    await db.exec(`update ${table} set archived_at = now() where kind = 'tour'`);
  });
  await as('anon', '', async () => {
    assert.equal((await rows('select * from storage.objects')).length, 0);
    assert.equal((await rows('select * from ' + table)).length, 1);
  });
  await as('authenticated', principal, async () => {
    await db.exec(`update ${table} set archived_at = null where kind = 'tour'`);
    await db.exec(`update ${table} set archived_at = now() where kind = 'tour'`);
    assert.equal((await rows(`delete from ${table} where kind = 'tour' returning id`)).length, 1);
    assert.equal((await rows('select * from public.cheongla_home_video_cleanup'))[0].path, path);
    assert.equal((await rows('delete from storage.objects returning name')).length, 1);
  });

  const dom = new JSDOM(read('../index.html'), { runScripts: 'outside-only' });
  const { document } = dom.window;
  dom.window.eval(read('../home-features-editor.js'));
  let records = seed;
  const ui = dom.window.CheonglaHomeFeatures.mount({
    document, client: async () => ({ from: () => ({ select: async () => ({ data: records }) }) }),
    profile: () => null, principal: () => false, confirm: async () => false, readable: String
  });
  await ui.refresh();
  assert.equal(document.getElementById('homeTourSection').hidden, false);
  assert.equal(document.getElementById('homeFeaturesManage').hidden, true);
  assert.match((await ui.video('tour')).url, /cheongla-tour\.mp4$/);
  assert.equal(ui.countdown().title, '2027학년도 수능까지');
  records = [];
  await ui.refresh();
  assert.equal(document.getElementById('homeTourSection').hidden, true);
  assert.equal(document.getElementById('homeClockExam').hidden, true);
  assert.equal(document.getElementById('homeDailyCountdown').hidden, true);
  assert.equal(document.getElementById('dailyWordPanel').hidden, false);
  dom.window.close();
  console.log('PASS home features: public visibility, principal permissions, archive, restore, permanent deletion and video cleanup');
} finally {
  await db.close();
}
