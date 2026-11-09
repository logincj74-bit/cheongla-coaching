import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { PGlite } from '@electric-sql/pglite';
const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');
const db = new PGlite();
const roles = ['student','parent','manager','owner','korean_teacher'];
const ids = Object.fromEntries(roles.map((role,i) => [role,'10000000-0000-0000-0000-00000000000'+(i+1)]));
const table = 'public.cheongla_mbti_prescriptions';
const rows = async sql => (await db.query(sql)).rows;
async function as(role, action) {
  await db.exec('begin');
  try {
    await db.exec(`set local role authenticated; set local request.jwt.claim.sub = '${ids[role]}';`);
    await action();
    await db.exec('commit');
  } catch (error) {
    await db.exec('rollback');
    throw error;
  }
}
try {
  await db.exec(read('./journal-notifications-local-bootstrap.sql'));
  await db.exec('create function cheongla_private.is_principal() returns boolean language sql as $$select true$$;');
  await db.exec(read('../067_mbti_guide_editor.sql'));
  await db.exec(`insert into public.cheongla_profiles (id,role,approval_status,membership_state) values ${roles.map(role =>
    `('${ids[role]}','${role}','approved','active')`).join(',')}`);
  await db.exec(`insert into public.cheongla_mbti_guides(mbti,guide,updated_by)
    values ('ISTP','{"title":"ISTP","coaching":[{"title":"기존 원장 수정","body":"보존 대상"}]}','${ids.owner}')`);
  const migrations = new URL('../supabase/migrations/', import.meta.url);
  const migration = readdirSync(migrations).find(file => file.endsWith('_mbti_study_operations.sql'));
  await db.exec(read('../supabase/migrations/' + migration));
  await db.exec(execFileSync('node', ['scripts/seed-mbti-operation-references.cjs'], { cwd: new URL('../',import.meta.url), encoding:'utf8' }));
  assert.equal((await rows("select guide ? 'coaching' as private from public.cheongla_mbti_guides"))[0].private,false);
  for (const role of ['student','parent','korean_teacher']) {
    await as(role, async () => {
      assert.equal((await rows('select * from public.cheongla_mbti_operation_references')).length,0);
      assert.equal((await rows('select * from '+table)).length,0);
    });
    await assert.rejects(as(role, () => rows('select * from public.cheongla_mbti_operation_students()')), {code:'42501'});
  }
  await as('manager', async () => {
    assert.equal((await rows('select * from public.cheongla_mbti_operation_students()'))[0].id,ids.student);
    const guides = await rows('select * from public.cheongla_mbti_operation_references');
    assert.equal(guides.length,16);
    assert.equal(guides.find(guide => guide.mbti==='ISTP').sections[0].title,'기존 원장 수정');
    await db.exec(`insert into ${table}(student_id,mbti,title,body) values ('${ids.student}','ISTP','상담 처방','비공개 본문')`);
    assert.equal((await rows(`delete from ${table} returning id`)).length,0);
    assert.equal((await rows(`update ${table} set archived_at=now() returning revision`))[0].revision,2);
  });
  await as('student', async () => assert.equal((await rows('select * from '+table)).length,0));
  await as('owner', async () => {
    assert.equal((await rows(`update ${table} set archived_at=null, body='수정된 처방' returning revision`))[0].revision,3);
    await db.exec(`update ${table} set archived_at=now()`);
    assert.equal((await rows(`delete from ${table} returning id`)).length,1);
  });
  console.log('PASS private MBTI references and per-student prescriptions: migration, role checks, archive, restore, purge');
} finally {
  await db.close();
}
