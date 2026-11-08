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
    const result = await action();
    await db.exec('commit');
    return result;
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
  const extension = readdirSync(migrations).find(name => name.endsWith('_home_content_management.sql'));
  await db.exec(read('../supabase/migrations/' + extension));
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

  const videoTrash = 'public.cheongla_home_video_trash';
  const additional = await as('authenticated', principal, async () => {
    await db.exec(`insert into ${table} (kind,title,sort_order) values ('tour','새 동영상',1)`);
    const [second] = await rows(`insert into ${table} (kind,title,target_date,sort_order)
      values ('countdown','모의평가','2027-06-03',1) returning *`);
    await db.exec(`select public.cheongla_set_featured_home_countdown('${second.id}', ${second.revision})`);
    assert.equal((await rows(`select * from ${table} where featured`))[0].id, second.id);
    const [newTour] = await rows(`select * from ${table} where kind = 'tour'`);
    await db.exec(`insert into storage.objects values ('cheongla-home-videos','${path}')`);
    await db.exec(`delete from public.cheongla_home_video_cleanup where path = '${path}'`);
    await db.exec(`update ${table} set video_path = '${path}', video_hidden = true where id = '${newTour.id}'`);
    assert.equal((await rows(`select * from ${videoTrash} where original_video`)).length, 1);
    return second;
  });
  await as('anon', '', async () => assert.equal((await rows('select * from storage.objects')).length, 0));
  await as('authenticated', principal, async () => {
    const [tour] = await rows(`update ${table} set video_path = null, video_hidden = false where kind = 'tour' returning *`);
    const [trashed] = await rows(`select * from ${videoTrash} where path = '${path}'`);
    assert.equal((await rows('delete from storage.objects returning name')).length, 0);
    await db.exec(`select public.cheongla_manage_home_video_trash('${trashed.id}', '${tour.id}', ${tour.revision})`);
    await db.exec(`update ${table} set hidden = true where featured`);
    assert.equal((await rows(`select * from ${table} where featured`)).length, 0);
  });
  await as('anon', '', async () => {
    assert.equal((await rows('select * from storage.objects')).length, 1);
    assert.equal((await rows(`select * from ${table} where kind = 'countdown'`)).length, 1);
  });
  await as('authenticated', principal, async () => {
    await db.exec(`update ${table} set video_path = null where kind = 'tour'`);
    const [trashed] = await rows(`select * from ${videoTrash} where path = '${path}'`);
    await db.exec(`select public.cheongla_manage_home_video_trash('${trashed.id}')`);
    assert.equal((await rows('delete from storage.objects returning name')).length, 1);
  });

  const dom = new JSDOM(read('../index.html'), { runScripts: 'outside-only' });
  const { document } = dom.window;
  dom.window.eval(read('../home-features-editor.js'));
  const apiRows = data => data.map(row => ({ ...row, target_date: row.target_date?.toISOString().slice(0, 10) || null }));
  let records = apiRows(seed);
  let manager = false;
  const ui = dom.window.CheonglaHomeFeatures.mount({
    document, client: async () => ({ from: name => ({ select: () => name === 'cheongla_home_features'
      ? Promise.resolve({ data: records })
      : { order: async () => ({ data: [] }), limit: async () => ({ data: [] }) } }) }),
    profile: () => null, principal: () => manager, confirm: async () => false, readable: String
  });
  await ui.refresh();
  assert.equal(document.getElementById('homeTourSection').hidden, false);
  assert.equal(document.getElementById('homeFeaturesManage').hidden, true);
  assert.match((await ui.video(seed.find(row => row.kind === 'tour').id)).url, /cheongla-tour\.mp4$/);
  assert.equal(ui.countdown().title, '2027학년도 수능까지');
  records = apiRows([...seed, { ...additional, featured: true }, { ...seed.find(row => row.kind === 'tour'), id: 'hidden-video', hidden: true }]);
  await ui.refresh();
  assert.equal(document.querySelectorAll('#homeDailyCountdown article').length, 2);
  assert.equal(document.querySelectorAll('#homeTourSection article').length, 1);
  assert.equal(ui.countdown().title, '모의평가');
  manager = true;
  await ui.refresh();
  const dialog = document.getElementById('homeFeaturesDialog');
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = () => { dialog.open = false; };
  document.getElementById('homeFeaturesManage').click();
  await new Promise(resolve => setImmediate(resolve));
  const select = document.getElementById('homeFeaturesItem');
  assert.equal(select.options.length, 3);
  select.value = '';
  select.dispatchEvent(new dom.window.Event('change'));
  assert.equal(document.getElementById('homeFeaturesNewVisibility').hidden, false);
  assert.equal(document.querySelector('[name="publishNow"]').checked, false);
  dialog.close();
  manager = false;
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
