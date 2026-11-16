"""Generate the reviewed seed SQL. Run only after content approval; never overwrite edits/tombstones."""
import json,sys
from pathlib import Path
source=Path(__file__).resolve().parent.parent/'data/mbti-library-2022.json'
seed=json.loads(source.read_text());output=Path(sys.argv[1]);statements=['-- Apply only after review approval. Existing records and tombstones are preserved.']
for doc in seed['documents']:
 text=json.dumps(doc,ensure_ascii=False).replace("'","''")
 statements.append("insert into cheongla_private.mbti_library(code,content)values('%s','%s'::jsonb)on conflict(code)do nothing;"%(doc['code'],text))
output.write_text('\n'.join(statements));print(output)
