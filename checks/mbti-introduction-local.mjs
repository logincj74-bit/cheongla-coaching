import assert from 'node:assert/strict';
import vm from 'node:vm';
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
const parent = '10000000-0000-0000-0000-000000000004';
const manager = '10000000-0000-0000-0000-000000000005';
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
    ('${suspended}', 'math_director', 'approved', 'suspended'),
    ('${parent}', 'parent', 'approved', 'active'),
    ('${manager}', 'manager', 'approved', 'active');`);
  const articlesMigration = readdirSync(migrations).find(name => name.endsWith('_mbti_learning_articles.sql'));
  await db.exec(read('../supabase/migrations/' + articlesMigration));
  const accessMigration = readdirSync(migrations).find(name => name.endsWith('_mbti_parent_guide_access.sql'));
  await db.exec(read('../supabase/migrations/' + accessMigration));
  const articlesTable = 'public.cheongla_mbti_learning_articles';
  const articles = await rows('select * from ' + articlesTable + ' order by category');
  assert.deepEqual(articles.map(row => row.category), ['groups', 'parent_nf', 'parent_nt', 'parent_sj', 'parent_sp']);
  assert(articles.every(row => !/최상위 1%의 비밀|제공된 도서 사진|사용자 제공 사진/.test(row.body)));
  await as('authenticated', member, async () => {
    assert.deepEqual((await rows('select category from ' + articlesTable)).map(row => row.category), ['groups']);
    assert.equal((await rows(`update ${articlesTable} set title = '변조' returning id`)).length, 0);
  });
  for (const reader of [parent, manager]) {
    await as('authenticated', reader, async () => {
      assert.equal((await rows('select * from ' + articlesTable)).length, 5);
      assert.equal((await rows(`update ${articlesTable} set title = '변조' returning id`)).length, 0);
    });
  }
  await as('authenticated', principal, async () => {
    assert.equal((await rows(`delete from ${articlesTable} returning id`)).length, 0);
    await rows(`update ${articlesTable} set archived_at = now() where category = 'parent_nt'`);
  });
  await as('authenticated', parent, async () => assert.equal((await rows('select * from ' + articlesTable)).length, 4));
  await as('authenticated', principal, async () => {
    await rows(`update ${articlesTable} set archived_at = null where category = 'parent_nt'`);
    await rows(`update ${articlesTable} set archived_at = now() where category = 'parent_sp'`);
    assert.equal((await rows(`delete from ${articlesTable} where category = 'parent_sp' returning id`)).length, 1);
    assert.equal((await rows('select * from ' + articlesTable)).length, 4);
  });
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
  const parentMenu = () => document.querySelector('[data-member-page="mbti_parents"]');
  assert.equal(parentMenu(), null);
  const html = read('../index.html');
  const context = vm.createContext({ document, $: id => document.getElementById(id), currentProfile: null });
  vm.runInContext(html.slice(html.indexOf('function canUseMBTIStudy()'), html.indexOf('function resetMBTIStudy()')), context);
  for (const role of ['student', 'parent', 'owner', 'english_director', 'math_director', 'manager']) {
    context.currentProfile = { role, approval_status: 'approved', membership_state: 'active' };
    context.configureMBTIParentMenu();
    assert.equal(Boolean(parentMenu()), role !== 'student');
  }
  context.currentProfile = { role:'student', approval_status:'approved', membership_state:'active' };
  context.configureMBTIParentMenu();
  assert.equal(parentMenu(), null);
  context.currentProfile = null;
  context.configureMBTIParentMenu();
  assert.equal(parentMenu(), null);
  assert.match(html, /key==='mbti_parents'&&!canReadMBTIParentGuide\(\)/);
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
  const printButton = intro.querySelector('[data-mbti-intro-print]');
  const pdfButton = intro.querySelector('[data-mbti-intro-pdf]');
  let printed;
  dom.window.CheonglaPrint = { node: (title, content) => { printed = { title, content }; } };
  printButton.click();
  assert.equal(printed.title, seed.title);
  assert.equal(printed.content.tagName, 'ARTICLE');
  assert.match(printed.content.textContent, /※ 안내/);
  const pdf = new dom.window.Blob([], { type: 'application/pdf' });
  dom.window.CheonglaMBTIIntroductionPDF = {
    create: (_, title, paragraphs) => {
      assert.equal(title, seed.title);
      assert.equal([...paragraphs].filter(node => node.tagName === 'H3').length, 6);
      return pdf;
    }
  };
  let filename;
  dom.window.CheonglaDocumentBrand = { download: (blob, name) => {
    assert.equal(blob, pdf);
    filename = name;
  } };
  pdfButton.click();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(filename, '청라_MBTI학습법_소개글.pdf');
  canEdit = true;
  await ui.load();
  intro.querySelector('[data-mbti-intro-actions] button').click();
  assert.equal(intro.querySelector('textarea').value.startsWith('MBTI로 시작하는'), true);
  ui.reset();
  assert.equal(intro.querySelector('textarea').value, '');
  assert(intro.querySelector('[data-mbti-intro-export]').hidden);
  const pages = dom.window.CheonglaMBTIIntroduction.mountPages({
    document, canEdit: () => false, confirm: () => true, readable: String,
    client: async () => ({ from: () => ({
      select: () => ({ eq: async (_, category) => ({ data: articles.filter(row => row.category === category) }) })
    }) })
  });
  pages.open('mbti_parents');
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual([...document.querySelectorAll('[data-mbti-page="mbti_parents"] > details > summary')]
    .map(node => node.textContent), ['SJ 기질의 부모', 'SP 기질의 부모', 'NF 기질의 부모', 'NT 기질의 부모']);
  assert.deepEqual([...document.querySelectorAll('[data-mbti-page]:not([hidden])')].map(node => node.dataset.mbtiPage), ['mbti_parents']);
  pages.open('mbti_study');
  assert.equal(document.querySelector('#mbtiStudyForm').closest('[data-mbti-page]').hidden, false);
  assert.equal(document.querySelector('#mbtiArticle-parent_nt').closest('[data-mbti-page]').hidden, true);
  dom.window.close();
  console.log('PASS MBTI introduction: seed, role restrictions, stale edits, archive, restore, purge, safe rendering, sign-out reset');
} finally {
  await db.close();
}
