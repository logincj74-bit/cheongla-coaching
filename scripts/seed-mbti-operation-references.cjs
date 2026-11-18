// Emits the one-time backfill from the previously published type catalogue.
// Existing staff reference overrides win. No consultation data enters Git.
const fs = require('node:fs');
if (!process.argv[2]) throw Error('Pass the private legacy catalog JSON path.');
const { types } = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const quote = text => "'" + text.replaceAll("'", "''") + "'";
const values = Object.entries(types).map(([code, guide]) =>
  '(' + quote(code) + ',' + quote(JSON.stringify(guide.coaching)) + '::jsonb)');
process.stdout.write('insert into public.cheongla_mbti_operation_references(mbti,sections) values\n' +
  values.join(',\n') + '\non conflict (mbti) do nothing;\n');
