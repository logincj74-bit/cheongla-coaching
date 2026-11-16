"""Extract the supplied 20 PDFs into editable 12-section documents; no OCR/API calls."""
from pathlib import Path
import fitz,re,json,hashlib,collections,sys,unicodedata
source=Path(sys.argv[1]);dest=Path(sys.argv[2])
groups={'NF':['ENFJ','ENFP','INFJ','INFP'],'NT':['ENTJ','ENTP','INTJ','INTP'],'SJ':['ESTJ','ESFJ','ISTJ','ISFJ'],'SP':['ESTP','ESFP','ISTP','ISFP']}
items=[];reports=[]
for path in sorted(source.glob('*MBTI*.pdf')):
 code=path.name.split(' ')[0];group=code if code in groups else next(k for k,v in groups.items() if code in v)
 pdf=fitz.open(path);sections=[];front=[];title=[];used=[];original=[];previous=None;table_count=0
 for page_index,page in enumerate(pdf):
  lines=[]
  for bi,block in enumerate(page.get_text('dict')['blocks']):
   for li,line in enumerate(block.get('lines',[])):
    spans=line['spans'];size=max(s['size'] for s in spans);text=''.join(s['text'] for s in spans)
    if size<8 or not text.strip():continue
    lines.append({'bbox':line['bbox'],'text':text,'size':size,'block':bi,'line':li})
  original.extend(x['text'] for x in lines)
  tables=[]
  for table in page.find_tables(strategy='lines_strict').tables:
   cells=[[re.sub(r"Page \d+ of \d+", "",c or "").strip() for c in row] for row in table.extract()]
   cells=[row for row in cells if any(row)]
   if len(cells)<2 or max(map(len,cells))<2:continue
   x0,y0,x1,y1=table.bbox
   if any(16<x['size']<18 and re.match(r'^\d{1,2}\.\s',x['text']) and y0<((x['bbox'][1]+x['bbox'][3])/2)<y1 for x in lines):continue
   tables.append((table.bbox,cells))
  events=[]
  for row in lines:
   x=(row['bbox'][0]+row['bbox'][2])/2;y=(row['bbox'][1]+row['bbox'][3])/2
   if any(a<=x<=c and b<=y<=d for (a,b,c,d),cells in tables):continue
   events.append((row['bbox'][1],row['bbox'][0],'text',row))
  for bbox,cells in tables:events.append((bbox[1],bbox[0],'table',cells))
  events.sort(key=lambda e:(round(e[0],1),e[1]))
  for y,x,kind,value in events:
   target=sections[-1]['lines'] if sections else front
   if kind=='table':
    table_count+=1;used.extend(c or '' for row in value for c in row)
    n=max(map(len,value));clean=lambda t:(t or '').replace('|','\\|').replace('\n','<br>')
    target.append('\n'+'\n'.join(['| '+' | '.join(clean(c) for c in row+['']*(n-len(row)))+' |' for row in value[:1]]+['| '+' | '.join(['---']*n)+' |']+['| '+' | '.join(clean(c) for c in row+['']*(n-len(row)))+' |' for row in value[1:]])+'\n');previous=None;continue
   text=value['text'];size=value['size'];used.append(text)
   head=re.match(r'^(\d{1,2})\.\s*(.*)',text) if 16<size<18 else None
   if head:
    number=int(head[1]);assert number==len(sections)+1,(code,number,len(sections))
    sections.append({'id':number,'title':head[2].strip(),'lines':[]});previous=('head',page_index,y);continue
   if size>=20 and not sections:title.append(text);previous=None;continue
   if 16<size<18 and previous and previous[0]=='head' and previous[1]==page_index and y-previous[2]<30:
    sections[-1]['title']+=' '+text;previous=('head',page_index,y);continue
   if 13<=size<16:target.append('\n### '+text+'\n')
   else:target.append(text)
   previous=None
 assert len(sections)==12,(code,len(sections))
 # Verify every non-footer glyph survives table extraction and reading-order conversion.
 chars=lambda seq:collections.Counter(c for t in seq for c in t if not c.isspace())
 before,after=chars(original),chars(used);missing=before-after;extra=after-before
 if missing or extra:raise ValueError((code,'glyph coverage',sum(missing.values()),sum(extra.values()),missing.most_common(12)))
 for section in sections:section['body']='\n'.join(section.pop('lines')).strip();assert section['body'],(code,section['id'])
 entry={'code':code,'kind':'temperament' if code in groups else 'type','temperament':group,'title':' '.join(title),'frontmatter':'\n'.join(front).strip(),'sections':sections,'source':{'filename':unicodedata.normalize('NFC',path.name),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pages':len(pdf)},'curriculum':'2022 개정 교육과정 · 2028학년도 수능 기준'}
 items.append(entry);reports.append({'code':code,'pages':len(pdf),'sections':12,'tables':table_count,'bodyCharacters':sum(len(s['body']) for s in sections),'glyphCoverage':'100%'})
assert len(items)==20
result={'schemaVersion':2,'revision':'2026-11-16','groups':groups,'documents':items}
dest.write_text(json.dumps(result,ensure_ascii=False,indent=2))
Path(str(dest)+'.report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2));print(json.dumps(reports,ensure_ascii=False))
