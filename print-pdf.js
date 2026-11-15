/* Offline PDF export: render bounded A4 pages locally, preserving Korean and ink colours. */
(function(root){'use strict';
const pageWidth=595.28,pageHeight=841.89,scale=2,margin=36;
const font='"Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", sans-serif';
async function create(source){
 const brand=root.CheonglaDocumentBrand;let logo=null;try{logo=await brand.loadLogo();}catch{}
 await source.fonts?.ready;
 const canvas=root.document.createElement('canvas');canvas.width=Math.round(pageWidth*scale);canvas.height=Math.round(pageHeight*scale);
 const context=canvas.getContext('2d');if(!context)throw Error('PDF를 만들 수 없습니다. 인쇄 메뉴를 이용해 주세요.');
 context.scale(scale,scale);context.textBaseline='top';
 const pages=[],bottom=pageHeight-42,width=pageWidth-margin*2;let y=68;
 function start(){context.fillStyle='#fff';context.fillRect(0,0,pageWidth,pageHeight);if(logo)context.drawImage(logo,margin,22,28,28);context.font='bold 10px '+font;context.fillStyle='#203e42';context.fillText(brand.name,margin+36,30);y=68;}
 function finish(){if(pages.length>=200)throw Error('한 번에 출력할 분량이 너무 많습니다. 기간을 나누어 저장해 주세요.');context.font='9px '+font;context.fillStyle='#52695e';context.fillText(String(pages.length+1),margin,pageHeight-27);const image=canvas.toDataURL('image/jpeg',0.94).split(',')[1];pages.push(Uint8Array.from(root.atob(image),c=>c.charCodeAt(0)));}
 function next(){finish();start();}
 function runs(node,color='#203e42',bold=false){
  if(node.nodeType===3)return[{text:node.textContent,color,bold}];if(node.nodeType!==1||node.hidden)return[];
  if(['SCRIPT','STYLE','BUTTON','NAV'].includes(node.tagName))return[];
  color=node.style?.color||color;bold=bold||['TH','STRONG','B'].includes(node.tagName);
  if(node.tagName==='BR')return[{text:'\n',color,bold}];
  const result=[];for(const child of node.childNodes){result.push(...runs(child,color,bold));if(child.nodeType===1&&['P','DIV','SECTION','LI'].includes(child.tagName))result.push({text:'\n',color,bold});}return result;
 }
 function wrap(parts,maxWidth,size){
  const lines=[[]];let used=0;
  for(const part of parts)for(const char of part.text.replace(/\r/g,'')){
   if(char==='\n'){lines.push([]);used=0;continue;}
   context.font=(part.bold?'bold ':'')+size+'px '+font;const length=context.measureText(char).width;
   if(used+length>maxWidth&&lines.at(-1).length){lines.push([]);used=0;}
   lines.at(-1).push({...part,text:char,width:length});used+=length;
  }
  return lines;
 }
 function line(chars,x,top,size){for(const char of chars){context.font=(char.bold?'bold ':'')+size+'px '+font;context.fillStyle=char.color;context.fillText(char.text,x,top);x+=char.width;}}
 function paragraph(node,size=11,bold=false){const leading=size*1.6,lines=wrap(runs(node,'#203e42',bold),width,size);for(const chars of lines){if(y+leading>bottom)next();line(chars,margin,y,size);y+=leading;}y+=7;}
 function table(node){
  const rows=Array.from(node.rows);if(!rows.length)return;
  const columns=Math.max(...rows.map(row=>Array.from(row.cells).reduce((n,c)=>n+(c.colSpan||1),0)));
  const widths=Array(columns).fill(width/columns);const first=Array.from(rows.find(r=>r.cells.length===columns&&Array.from(r.cells).every(c=>/^\d+(?:\.\d+)?%$/.test(c.style.width)))?.cells||[]);
  if(first.length&&first.every(cell=>/^\d+(?:\.\d+)?%$/.test(cell.style.width))){const total=first.reduce((n,c)=>n+parseFloat(c.style.width),0);first.forEach((c,i)=>widths[i]=width*parseFloat(c.style.width)/total);}
  const header=rows[0].querySelector('th')?rows[0]:null;
  function layout(row){let column=0;return Array.from(row.cells).map(cell=>{const span=cell.colSpan||1,w=widths.slice(column,column+span).reduce((a,b)=>a+b,0);column+=span;return{w,lines:wrap(runs(cell),Math.max(10,w-12),9)};});}
  function segment(cells,offset,count){const h=count*15+12;let x=margin;for(const cell of cells){context.strokeStyle='#9eafa4';context.lineWidth=.5;context.strokeRect(x,y,cell.w,h);for(let j=0;j<count;j++)if(cell.lines[offset+j])line(cell.lines[offset+j],x+6,y+6+j*15,9);x+=cell.w;}y+=h;}
  function repeatHeader(){if(!header)return;const cells=layout(header),length=Math.max(...cells.map(c=>c.lines.length));if(length*15+12<bottom-y-50)segment(cells,0,length);}
  if(y>bottom-70)next();
  for(const row of rows){const cells=layout(row),length=Math.max(...cells.map(c=>c.lines.length));let offset=0;while(offset<length){if(y>bottom-28){next();if(row!==header)repeatHeader();}const count=Math.min(length-offset,Math.floor((bottom-y-12)/15));if(count<1){next();if(row!==header)repeatHeader();continue;}segment(cells,offset,count);offset+=count;}}
  y+=10;
 }
 async function visit(node){
  if(node.nodeType!==1||node.hidden||['SCRIPT','STYLE','BUTTON','NAV'].includes(node.tagName)||node.classList.contains('print-brand'))return;
  if(node.tagName==='TABLE'){table(node);return;}
  if(node.tagName==='IMG'){
   if(!node.complete)await node.decode();const w=Math.min(width,node.naturalWidth||width),h=w*(node.naturalHeight||100)/(node.naturalWidth||width);const actualH=Math.min(h,bottom-68);if(y+actualH>bottom)next();context.drawImage(node,margin,y,w*actualH/h,actualH);y+=actualH+10;return;
  }
  if(/^H[1-6]$/.test(node.tagName)){if(y>bottom-70)next();paragraph(node,node.tagName==='H1'?19:13,true);return;}
  if(['P','SUMMARY','LI'].includes(node.tagName)){paragraph(node);return;}
  if(!Array.from(node.children).some(child=>['DIV','TABLE','P','SECTION','ARTICLE','H1','H2','H3','DETAILS','UL','OL'].includes(child.tagName))){if(node.textContent.trim())paragraph(node);return;}
  for(const child of node.childNodes){if(child.nodeType===3&&child.textContent.trim()){const p=source.createElement('p');p.textContent=child.textContent;paragraph(p);}else await visit(child);}
 }
 start();for(const node of source.body.children)await visit(node);finish();return imagePdf(pages,canvas.width,canvas.height);
}
  function imagePdf(pages, width, height) {
    // The PDF embeds each rendered page as a JPEG to preserve Korean glyphs.
    const parts = [];
    const offsets = [0];
    const encoder = new TextEncoder();
    let length = 0;

    function append(part) {
      const bytes = typeof part === 'string' ? encoder.encode(part) : part;
      parts.push(bytes);
      length += bytes.length;
    }

    function object(id, body, stream) {
      offsets[id] = length;
      append(id + ' 0 obj\n' + body);
      if (stream) {
        append('\nstream\n');
        append(stream);
        append('\nendstream');
      }
      append('\nendobj\n');
    }

    append('%PDF-1.4\n');
    object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    const children = pages.map((_, index) => (3 + index * 3) + ' 0 R').join(' ');
    object(2, '<< /Type /Pages /Count ' + pages.length + ' /Kids [' + children + '] >>');
    const paint = encoder.encode('q ' + pageWidth + ' 0 0 ' + pageHeight + ' 0 0 cm /PageImage Do Q');
    pages.forEach((image, index) => {
      const id = 3 + index * 3;
      object(id, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + pageWidth + ' ' + pageHeight +
        '] /Resources << /XObject << /PageImage ' + (id + 1) + ' 0 R >> >> /Contents ' + (id + 2) + ' 0 R >>');
      object(id + 1, '<< /Type /XObject /Subtype /Image /Width ' + width + ' /Height ' + height +
        ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' + image.length + ' >>', image);
      object(id + 2, '<< /Length ' + paint.length + ' >>', paint);
    });

    const xref = length;
    append('xref\n0 ' + offsets.length + '\n0000000000 65535 f \n');
    for (const offset of offsets.slice(1)) append(String(offset).padStart(10, '0') + ' 00000 n \n');
    append('trailer\n<< /Size ' + offsets.length + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n');
    return new Blob(parts, { type: 'application/pdf' });
  }

root.CheonglaPrintPDF={create};
})(globalThis);
