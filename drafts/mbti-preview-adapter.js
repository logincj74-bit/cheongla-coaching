/* Review fixture only. Never included in index.html or the production app. */
(function(root){'use strict';
function make(seed){
 const copy=value=>JSON.parse(JSON.stringify(value));let rows=seed.documents.map(content=>({code:content.code,content:copy(content),revision:1,archived_at:null,purged_at:null}));
 let preference='';const initial=copy(rows);
 const find=code=>rows.find(r=>r.code===code),stamp=()=>new Date().toISOString();
 function check(args){const row=find(args.target_code);if(!row||row.revision!==args.expected_revision)throw Error('문서가 변경되었습니다. 다시 불러와 주세요.');return row;}
 return{reset(){rows=copy(initial);preference='';},preference:async()=>preference,savePreference:async code=>{preference=code;},
 async rpc(name,args={}){
  if(name==='cheongla_mbti_library_list')return copy(rows);
  if(name==='cheongla_mbti_library_save'){const row=check(args),s=row.content.sections[args.section_id-1];row.content.title=args.document_title;row.content.frontmatter=args.document_frontmatter;s.title=args.section_title;s.body=args.section_body;row.revision++;return copy(row);}
  if(name==='cheongla_mbti_library_action'){const row=check(args);if(args.section_id){const part=row.content.sections[args.section_id-1];if(args.operation==='archive')part.archived_at=stamp();else if(args.operation==='restore')delete part.archived_at;else{part.body=null;part.title='삭제된 항목';part.purged_at=stamp();delete part.archived_at;}}
   else if(args.operation==='archive')row.archived_at=stamp();else if(args.operation==='restore')row.archived_at=null;else{row.content=null;row.archived_at=null;row.purged_at=stamp();}row.revision++;return;}
  if(name==='cheongla_mbti_library_empty_trash'){for(const expected of args.expected_items){const row=find(expected.code);if(row.revision!==expected.revision)throw Error('휴지통 내용이 변경되었습니다.');if(row.archived_at){row.content=null;row.archived_at=null;row.purged_at=stamp();}else for(const s of row.content.sections)if(s.archived_at){s.body=null;s.title='삭제된 항목';s.purged_at=stamp();delete s.archived_at;}row.revision++;}return;}
  throw Error('지원하지 않는 미리보기 작업입니다.');
 }};
}
root.CheonglaMBTIPreview={make};
})(globalThis);
