"""Import the eight revised MBTI articles. OCR transcription is visually checked locally."""
from pathlib import Path
import fitz, re, json, hashlib, collections, unicodedata, sys

source=Path(sys.argv[1]);dest=Path(sys.argv[2])
mapping={
 '나를 이해하는 공부, 나에게 맞는 학습법.pdf':('intro_learning','mbti_intro'),
 '청라 MBTI학습법 소개글.pdf':('intro_letter','mbti_intro'),
 'MBTI 여섯 그룹 학습성향.pdf':('groups','mbti_groups'),
 '기질별_부모의_양육태도_학부모용.pdf':('parent_overview','mbti_parents'),
 **{f'기질별_부모의_양육태도_{i}_{code}부모.pdf':('parent_'+code.lower(),'mbti_parents') for i,code in enumerate(['SJ','SP','NF','NT'],1)}
}
items=[];reports=[]
for filename,(code,category) in mapping.items():
 path=next(p for p in source.glob('*.pdf') if unicodedata.normalize('NFC',p.name)==filename)
 pdf=fitz.open(path);sections=[];front=[];titles=[];original=[];used=[];table_count=0
 if code=='intro_letter':
  entry=json.loads(Path(sys.argv[3]).read_text())
  coverage='image PDF · local OCR + three-page visual verification'
 else:
  for page_index,page in enumerate(pdf):
   lines=[]
   for bi,block in enumerate(page.get_text('dict')['blocks']):
    for line in block.get('lines',[]):
     size=max(s['size'] for s in line['spans']);text=''.join(s['text'] for s in line['spans'])
     if size<8 or not text.strip():continue
     lines.append({'bbox':line['bbox'],'text':text,'size':size,'block':bi})
   original.extend(x['text'] for x in lines)
   tables=[]
   for table in page.find_tables(strategy='lines_strict').tables:
    cells=[[re.sub(r'Page \d+ of \d+','',c or '').strip() for c in row] for row in table.extract()]
    cells=[row for row in cells if any(row)]
    if len(cells)<2 or max(map(len,cells))<2:continue
    a,b,c,d=table.bbox
    if any(x['size']>=13.9 and b<(x['bbox'][1]+x['bbox'][3])/2<d for x in lines):continue
    tables.append((table.bbox,cells))
   events=[]
   for line in lines:
    x=(line['bbox'][0]+line['bbox'][2])/2;y=(line['bbox'][1]+line['bbox'][3])/2
    if not any(a<=x<=c and b<=y<=d for (a,b,c,d),cells in tables):events.append((line['bbox'][1],line['bbox'][0],'text',line))
   for bbox,cells in tables:events.append((bbox[1],bbox[0],'table',cells))
   events.sort(key=lambda e:(round(e[0],1),e[1]));previous=None
   for y,x,kind,value in events:
    target=sections[-1]['lines'] if sections else front
    if kind=='table':
     table_count+=1;used.extend(c or '' for row in value for c in row);n=max(map(len,value))
     clean=lambda t:(t or '').replace('|','\\|').replace('\n','<br>')
     rows=['| '+' | '.join(clean(c) for c in row+['']*(n-len(row)))+' |'for row in value]
     rows.insert(1,'| '+' | '.join(['---']*n)+' |');target.append('\n'+'\n'.join(rows)+'\n');previous=None;continue
    text=value['text'];size=value['size'];used.append(text)
    if size>=20 and not sections:titles.append(text);previous=None;continue
    if size>=13.9:
     sections.append({'id':len(sections)+1,'title':text.strip(),'lines':[]});previous=None;continue
    if previous is not None and y-previous[0]>1.7*max(size,previous[1]):target.append('')
    target.append(text);previous=(y,size)
  chars=lambda seq:collections.Counter(c for t in seq for c in t if not c.isspace())
  before,after=chars(original),chars(used)
  if before!=after:raise ValueError((code,'glyph mismatch',before-after,after-before))
  for section in sections:section['body']='\n'.join(section.pop('lines')).strip();assert section['body'],(code,section['id'])
  entry={'title':' '.join(titles),'frontmatter':'\n'.join(front).strip(),'sections':sections};coverage='100%'
 if code=='intro_learning':
  for section in entry['sections']:section['title']=section['title'].replace('ㅜㅜㅎ','')
 entry.update(code=code,category=category,kind='article',source={'filename':filename,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pages':len(pdf)})
 assert entry['title'] and entry['sections'] and len(entry['sections'])<=30
 items.append(entry);reports.append({'code':code,'pages':len(pdf),'sections':len(entry['sections']),'tables':table_count,'bodyCharacters':sum(len(s['body']) for s in entry['sections']),'glyphCoverage':coverage})
dest.write_text(json.dumps({'schemaVersion':1,'revision':'2026-11-16','documents':items},ensure_ascii=False,indent=2))
Path(str(dest)+'.report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2));print(json.dumps(reports,ensure_ascii=False))
