import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { JSDOM } from 'jsdom';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const migrations = new URL('../supabase/migrations/', import.meta.url);
const migration = readdirSync(migrations).find(name => name.endsWith('_mbti_introduction.sql'));
const db = new PGlite();
const table = 'public.cheongla_mbti_introductions';
const principal = '10000000-0000-0000-0000-000000000001';
const member = '10000000-0000-0000-0000-000000000002';
const suspended = '10000000-0000-0000-0000-000000000003';
const rows = async (sql, args) => (await db.query(sql, args)).rows;

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
  await db.exec(read('../supabase/migrations/' + migration));
  await db.exec(`insert into public.cheongla_profiles (id, role, approval_status, membership_state) values
    ('${principal}', 'english_director', 'approved', 'active'),
    ('${member}', 'student', 'approved', 'active'),
    ('${suspended}', 'math_director', 'approved', 'suspended');`);
  const [seed] = await rows('select * from ' + table);
  assert.equal(seed.title, '나를 이해하는 공부, 나에게 맞는 학습법');
  assert.equal(seed.body.match(/^[1-6]\. /gm)?.length, 6);
  assert.match(seed.body, /※ 안내: MBTI는 학업 능력이나 성적을 진단하는 검사가 아닙니다/);
  await assert.rejects(as('anon', '', () => rows('select * from ' + table)), { code: '42501' });
  await as('authenticated', suspended, async () => assert.equal((await rows('select * from ' + table)).length, 0));
  await as('authenticated', member, async () => {
    assert.equal((await rows('select * from ' + table)).length, 1);
    assert.equal((await rows(`update ${table} set title = '변조' returning id`)).length, 0);
    assert.equal((await rows(`delete from ${table} returning id`)).length, 0);
  });
  await as('authenticated', principal, async () => {
    assert.equal((await rows(`delete from ${table} returning id`)).length, 0);
    const [edited] = await rows(`update ${table} set title = '수정한 글' returning *`);
    assert.equal(edited.revision, seed.revision + 1);
    assert.equal((await rows(`update ${table} set title = '오래된 변경' where revision = $1 returning id`, [seed.revision])).length, 0);
    await rows(`update ${table} set archived_at = now()`);
  });
  await as('authenticated', member, async () => assert.equal((await rows('select * from ' + table)).length, 0));
  await as('authenticated', principal, async () => {
    assert.equal((await rows('select * from ' + table)).length, 1);
    await rows(`insert into ${table} (title, body) values ('새 소개글', '새 본문')`);
  });
  await assert.rejects(as('authenticated', principal, () =>
    rows(`update ${table} set archived_at = null where id = $1`, [seed.id])), { code: '23505' });
  await as('authenticated', principal, async () => {
    await rows(`update ${table} set archived_at = now() where id <> $1`, [seed.id]);
    await rows(`update ${table} set archived_at = null where id = $1`, [seed.id]);
    assert.equal((await rows(`delete from ${table} where archived_at is not null returning id`)).length, 1);
  });
  await as('authenticated', member, async () => {
    const [restored] = await rows('select * from ' + table);
    assert.equal(restored.title, '수정한 글');
  });

  const dom = new JSDOM(read('../index.html'), { runScripts: 'outside-only' });
  const { document } = dom.window;
  dom.window.eval(read('../mbti-introduction.js'));
  const intro = document.getElementById('mbtiIntroduction');
  let canEdit = false;
  const ui = dom.window.CheonglaMBTIIntroduction.mount({
    document, canEdit: () => canEdit, confirm: () => true, readable: String,
    client: async () => ({
      from: () => ({ select: async () => ({ data: [{ ...seed, body: seed.body + '\n\n<img src=x>' }] }) })
    })
  });
  await ui.load();
  assert.equal(intro.querySelectorAll('article h3').length, 6);
  assert.equal(intro.querySelector('article img'), null);
  assert(intro.querySelector('fieldset').hidden);
  canEdit = true;
  await ui.load();
  intro.querySelector('[data-mbti-intro-actions] button').click();
  assert.equal(intro.querySelector('textarea').value.startsWith('MBTI로 시작하는'), true);
  ui.reset();
  assert.equal(intro.querySelector('textarea').value, '');
  dom.window.close();
  console.log('PASS MBTI introduction: seed, role restrictions, stale edits, archive, restore, purge, safe rendering, sign-out reset');
} finally {
  await db.close();
}
