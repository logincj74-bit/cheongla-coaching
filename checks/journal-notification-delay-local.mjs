import fs from 'node:fs';
import {createJournalTestDb} from './journal-notifications-test-db.mjs';

const read = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
const db = await createJournalTestDb();
try {
  await db.exec(`
    create schema cron;
    create function cron.schedule(text, text, text)
    returns bigint language sql as $$select 1::bigint$$;
  `);
  await db.exec(read('../supabase/migrations/20261127130235_debounce_daily_journal_notifications.sql'));
  const fixtures = read('./journal-notifications-cases.sql').split("select set_config('request.jwt.claim.sub'")[0];
  await db.exec(fixtures);
  const results = await db.exec(read('./journal-notification-delay-cases.sql'));
  for (const {rows} of results) {
    for (const {result} of rows) if (result) console.log(result);
  }
  await db.exec('rollback');
} finally {
  await db.close();
}
