import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { JSDOM } from 'jsdom';

const read = file => readFileSync(new URL(file, import.meta.url), 'utf8');
const db = new PGlite();
const table = 'public.cheongla_winter_promotions';
const principalId = '10000000-0000-0000-0000-000000000001';
const managerId = '10000000-0000-0000-0000-000000000002';
const suspendedId = '10000000-0000-0000-0000-000000000003';

try {
  await db.exec(read('./journal-notifications-local-bootstrap.sql'));
  await db.exec(read('../supabase/migrations/20261107125442_winter_school_promotions.sql'));
  await db.exec(read('../supabase/migrations/20261107134414_winter_promotion_manual_hide.sql'));
  const [{ rows: [seed] }] = await db.exec('select * from ' + table);
  assert.equal(seed.title, '2027 청라 윈터스쿨');
  assert.equal(seed.ends_at.toISOString(), '2026-12-27T15:00:00.000Z');
  await db.exec(`
    insert into public.cheongla_profiles (id,role,approval_status,membership_state) values
      ('${principalId}','english_director','approved','active'),
      ('${managerId}','manager','approved','active'),
      ('${suspendedId}','math_director','suspended','active');
    update ${table} set ends_at = now() + interval '1 day';
  `);

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

  const rows = async (sql, args) => (await db.query(sql, args)).rows;
  await as('anon', '', async () => {
    assert.equal((await rows('select title from ' + table)).length, 1);
    await assert.rejects(db.exec("update " + table + " set title = '변조'"), { code: '42501' });
  });
  for (const id of [managerId, suspendedId]) {
    await as('authenticated', id, async () => {
      assert.equal((await rows('select title from ' + table)).length, 1);
      assert.equal((await rows("update " + table + " set title = '변조' returning id")).length, 0);
    });
  }
  await as('authenticated', principalId, async () => {
    assert.equal((await rows('delete from ' + table + ' returning id')).length, 0);
    const [saved] = await rows("update " + table + " set title = '수정된 모집', first_open = false returning *");
    assert.equal(saved.first_open, false);
    assert(saved.revision > seed.revision);
    assert.equal((await rows('update ' + table + ' set first_open = true where revision = $1 returning id', [seed.revision])).length, 0);
  });
  await as('anon', '', async () => {
    assert.equal((await rows('select title from ' + table))[0].title, '수정된 모집');
  });
  await as('authenticated', principalId, async () => {
    await db.exec("update " + table + " set ends_at = now() - interval '1 second'");
  });
  await as('anon', '', async () => {
    assert.equal((await rows('select * from ' + table)).length, 0);
  });
  await as('authenticated', principalId, async () => {
    await db.exec('update ' + table + ' set ends_at = null');
  });
  await as('anon', '', async () => {
    assert.equal((await rows('select title from ' + table)).length, 1);
  });
  await as('authenticated', principalId, async () => {
    await db.exec('update ' + table + ' set enabled = false, deleted_at = now()');
    assert.equal((await rows('select * from ' + table)).length, 1);
    await db.exec('update ' + table + ' set deleted_at = null, enabled = false');
    assert.equal((await rows('delete from ' + table + ' returning id')).length, 0);
    await db.exec('update ' + table + ' set deleted_at = now()');
    await db.query(`insert into ${table} (title, button_text, first_date, second_date, ends_at)
      values ('새 카드', '상담', '2026-12-21', '2026-12-28', now() + interval '1 day')`);
    assert.equal((await rows('delete from ' + table + ' where id = $1 returning id', [seed.id])).length, 1);
    await db.query(`insert into ${table} (title, button_text, first_date, second_date, ends_at)
      values ('두 번째 카드', '상담', '2026-12-21', '2026-12-28', now() + interval '1 day')`);
    await db.exec("update " + table + " set deleted_at = now() where title = '두 번째 카드'");
    assert.equal((await rows('delete from ' + table + ' where deleted_at is not null returning id')).length, 1);
    assert.deepEqual(await rows('select title from ' + table), [{ title: '새 카드' }]);
  });
} finally {
  await db.close();
}

const dom = new JSDOM(read('../index.html'), { runScripts: 'outside-only', pretendToBeVisual: true });
try {
  const { window } = dom;
  const { document } = window;
  const row = {
    title: '2027 청라 윈터스쿨', message: '<b>겨울 준비</b>', button_text: '모집 안내 · 상담 신청',
    first_date: '2026-12-21', second_date: '2026-12-28', first_open: true, second_open: true,
    ends_at: new Date(Date.now() + 60000).toISOString(), enabled: true
  };
  let actor = null;
  const query = {
    select() { return this; }, eq() { return this; }, is() { return this; },
    or() { return this; }, gt() { return this; }, async maybeSingle() { return { data: row }; }
  };
  window.eval(read('../winter-promotion.js'));
  const ui = window.CheonglaWinterPromotion.mount({
    document, profile: () => actor, principal: () => actor?.role === 'owner',
    client: async () => ({ from: () => query }), confirm: async () => true, readable: String
  });
  const refresh = async () => { ui.refresh(); await new Promise(resolve => setTimeout(resolve, 0)); };
  const card = document.getElementById('winterPromotion');
  const admin = document.getElementById('winterPromotionAdmin');
  await refresh();
  assert.equal(card.hidden, false);
  assert.equal(admin.hidden, true);
  assert.equal(card.nextElementSibling.className, 'home-tour');
  assert.equal(card.querySelectorAll('time').length, 2);
  assert.equal(card.querySelector('p').textContent, '<b>겨울 준비</b>');
  assert.equal(card.querySelector('a').href, 'https://cheongla-winter-2027.logincj.chatgpt.site/');
  assert(!card.textContent.includes('기간 한정'));
  actor = { role: 'owner' };
  row.first_open = false;
  await refresh();
  assert.equal(admin.hidden, false);
  assert.equal(card.querySelectorAll('time').length, 1);
  assert.match(card.textContent, /2차 모집 중/);
  assert.doesNotMatch(card.textContent, /21일/);
  row.ends_at = null;
  await refresh();
  assert.equal(card.hidden, false);
  assert.equal(admin.querySelector('[name="ends_at"]'), null);
  actor = { role: 'manager' };
  row.ends_at = new Date(Date.now() - 1).toISOString();
  await refresh();
  assert.equal(admin.hidden, true);
  assert.equal(card.hidden, true);
  assert.equal(card.childElementCount, 0);
} finally {
  dom.window.close();
}

console.log('Winter promotion SQL permissions, lifecycle and home presentation passed.');
