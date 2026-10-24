"""Convert pinned, openly licensed en-ko StarDict data into plain-text JSON shards.
Input: extracted en-ko.zip from koreader-dicts v1.2.0 (SHA256 recorded below).
No HTML is rendered in the app. Generated dictionary data remains CC BY-SA 4.0.
"""
import sys,json,gzip,struct,re,html,unicodedata
from pathlib import Path
from html.parser import HTMLParser
SOURCE_URL='https://github.com/DanielGregorini/koreader-dicts/releases/download/v1.2.0/en-ko.zip'
SHA256='219eacf3f57e93da993a9ba438d3c3eaf3fa3b94de745847fe74826cb776ccf1'
class Text(HTMLParser):
 def __init__(self):super().__init__();self.parts=[]
 def handle_data(self,s):self.parts.append(s)
def plain(s):
 p=Text();p.feed(s);return ' '.join(''.join(p.parts).split())
def norm(s):return re.sub(r'\s+',' ',unicodedata.normalize('NFKC',s).replace('’',"'").replace('–','-').replace('—','-').strip()).lower()
def valid(s):return bool(re.fullmatch(r"[a-z][a-z0-9 .'-]{0,79}",s))
def bucket(s):return str((ord(s[0])-97)//4)
root=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
raw=(root/'en-ko.idx').read_bytes();data=gzip.decompress((root/'en-ko.dict.dz').read_bytes());entries=[];shards={str(i):{'entries':{},'aliases':{}} for i in range(7)};i=0
while i<len(raw):
 e=raw.index(0,i);word=raw[i:e].decode();off,size=struct.unpack('>II',raw[e+1:e+9]);i=e+9;entries.append(norm(word));key=norm(word)
 if not valid(key):continue
 src=data[off:off+size].decode();pron=re.match(r'<div style="color:#666666">(.*?)</div>',src);pron=plain(pron[1]) if pron else ''
 senses=[]
 for section in re.findall(r'<div>(.*?)</div>',src,re.S):
  pos=re.search(r'<i>(.*?)</i>',section);pos=plain(pos[1]) if pos else ''
  for translation in re.findall(r'<b>(.*?)</b>',section,re.S):
   k=plain(translation)
   if k and (pos,k) not in senses:senses.append((pos,k))
 if not senses:continue
 entry={'w':word,'p':pron,'s':[list(x) for x in senses]}
 existing=shards[bucket(key)]['entries'].setdefault(key,[])
 if entry not in existing:existing.append(entry)
raw=(root/'en-ko.syn').read_bytes();i=0
while i<len(raw):
 e=raw.index(0,i);form=norm(raw[i:e].decode());idx=struct.unpack('>I',raw[e+1:e+5])[0];i=e+5;word=entries[idx]
 if not valid(form) or not valid(word) or form==word or word not in shards[bucket(word)]['entries']:continue
 refs=shards[bucket(form)]['aliases'].setdefault(form,[])
 if word not in refs:refs.append(word)
for k,d in shards.items():(out/(k+'.json')).write_text(json.dumps(d,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
meta={'source':SOURCE_URL,'source_sha256':SHA256,'version':'en-ko-v1.2.0-cheongla-1','license':'CC-BY-SA-4.0','headwords':sum(len(d['entries'])for d in shards.values()),'forms':sum(len(d['aliases'])for d in shards.values()),'changes':'HTML removed; Korean translations, part of speech, pronunciation and inflection references retained; Unicode and case normalization; split into seven JSON files.'}
(out/'manifest.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
(out/'ATTRIBUTION.txt').write_text('Cheongla English–Korean dictionary data\n\n'+(root/'ATTRIBUTION').read_text()+'\n'+(root/'LICENSE').read_text()+'\nCompilation: DanielGregorini/koreader-dicts v1.2.0\n'+SOURCE_URL+'\nSource SHA256: '+SHA256+'\n\nOriginal sources:\nEnglish Wiktionary contributors, via Kaikki.org / Wiktextract\nhttps://en.wiktionary.org/\nhttps://kaikki.org/\nPrinceton University WordNet 3.0\nhttps://wordnet.princeton.edu/license-and-commercial-use\n\nAdapted by Cheongla: '+meta['changes']+'\nThis adapted dictionary data is distributed under CC BY-SA 4.0.\nhttps://creativecommons.org/licenses/by-sa/4.0/\nOriginal page histories: https://en.wiktionary.org/w/index.php?title=WORD&action=history\nNo affiliation or endorsement by source authors is implied.\n',encoding='utf-8')
print(json.dumps(meta,ensure_ascii=False));print('bytes',sum(p.stat().st_size for p in out.glob('*')))
for w in ['study','go','bank','beautiful','photosynthesis','studies','went','children']:
 d=shards[bucket(w)];print(w,d['entries'].get(w)or d['aliases'].get(w))
