// Emits the one-time backfill from the previously published type catalogue.
// Existing staff reference overrides win. No consultation data enters Git.
const { execFileSync } = require('node:child_process');
const { types } = JSON.parse(execFileSync('git', [
  'show', '9a68cfbd83eb6065671d9dbf7fb120e42354603d:assets/mbti-study-methods.json'
], { encoding: 'utf8' }));
const quote = text => "'" + text.replaceAll("'", "''") + "'";
const values = Object.entries(types).map(([code, guide]) =>
  '(' + quote(code) + ',' + quote(JSON.stringify(guide.coaching)) + '::jsonb)');
process.stdout.write('insert into public.cheongla_mbti_operation_references(mbti,sections) values\n' +
  values.join(',\n') + '\non conflict (mbti) do nothing;\n');
