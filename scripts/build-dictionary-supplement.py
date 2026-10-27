"""Add Korean-Wiktionary English glosses and reviewed Cheongla core vocabulary.

Usage: python scripts/build-dictionary-supplement.py /path/to/kaikki-jsonl
Pinned input digest and provenance are recorded in supplement/manifest.json.
No executable source, examples, remote audio, or HTML is retained.
"""
import hashlib, json, re, sys, unicodedata
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'assets/dictionary/supplement'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE='https://kaikki.org/kowiktionary/%EC%98%81%EC%96%B4/kaikki.org-dictionary-%EC%98%81%EC%96%B4.jsonl'
POS={'noun':'n.','verb':'v.','adj':'adj.','adv':'adv.','pron':'pron.','prep':'prep.','conj':'conj.','intj':'interj.','det':'det.','num':'num.','article':'art.','phrase':'phr.','name':'고유명사','abbrev':'약어','prefix':'접두사','suffix':'접미사'}
CATEGORIES={'명사':'n.','동사':'v.','형용사':'adj.','부사':'adv.','전치사':'prep.','접속사':'conj.','대명사':'pron.'}
def normalize(value):
 return re.sub(r'\s+',' ',unicodedata.normalize('NFKC',value).replace('’',"'").replace('‘',"'").replace('–','-').replace('—','-').strip()).lower()
def valid(word):return bool(re.fullmatch("[a-z][a-z0-9 .'-]{0,79}",word))
shards={chr(i):{'entries':{}} for i in range(97,123)}
base={}
for i in range(7):base.update(json.loads((ROOT/f'assets/dictionary/{i}.json').read_text())['entries'])
source=Path(sys.argv[1])
for line in source.open():
 item=json.loads(line);word=normalize(item.get('word',''))
 if not valid(word) or item.get('lang_code')!='en':continue
 pos=POS.get(item.get('pos'),'')
 if not pos:
  categories={x['name'] for x in item.get('categories',[])}
  inferred=[v for k,v in CATEGORIES.items() if '영어 '+k in categories]
  if len(inferred)==1:pos=inferred[0]
 senses=[]
 for sense in item.get('senses',[]):
  if sense.get('form_of') or 'no-gloss' in sense.get('tags',[]):continue
  for raw in sense.get('glosses',[]):
   text=re.sub(r'\s+',' ',raw).strip()
   if not re.search('[가-힣]',text) or not 1<=len(text)<=600:continue
   if '<' in text or '>' in text or '{{' in text:continue
   pair=[pos,text]
   if pair not in senses:senses.append(pair)
 if not senses:continue
 sounds=list(dict.fromkeys(x['ipa'] for x in item.get('sounds',[]) if x.get('ipa')))
 entry={'w':item['word'],'p':' · '.join(sounds)[:180],'s':senses}
 dest=shards[word[0]]['entries'].setdefault(word,[])
 if entry not in dest:dest.append(entry)
reviewed={}
for line in (ROOT/'assets/dictionary/reviewed-core.tsv').read_text().splitlines():
 if not line.strip():continue
 word,pos,meaning=line.split('\t');assert valid(word)
 reviewed.setdefault(word,[]).append([pos,meaning])
for word,senses in reviewed.items():
 prev=base.get(word) or shards[word[0]]['entries'].get(word) or [{'p':''}]
 shards[word[0]]['entries'][word]=[{'w':word,'p':prev[0]['p'],'s':senses,'reviewed':True}]
supplement=set()
for letter,data in shards.items():
 supplement.update(data['entries'])
 (OUT/(letter+'.json')).write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
manifest={'version':'20261027-1','source':SOURCE,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_dump':'Korean Wiktionary 2026-10-01; Kaikki extraction 2026-10-24','license':'CC-BY-SA-4.0','headwords':len(supplement),'added_headwords':len(supplement-set(base)),'combined_headwords':len(supplement|set(base)),'reviewed_headwords':len(reviewed),'changes':'English entries with Korean plain-text glosses only; POS inferred from explicit categories when necessary; IPA retained when supplied; form-only senses excluded; Cheongla reviewed core senses override selected sparse entries. Other original data and 40 editorial entries preserved.'}
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest,ensure_ascii=False))
print('largest letter shard',max((p.stat().st_size,p.name)for p in OUT.glob('?.json')))
