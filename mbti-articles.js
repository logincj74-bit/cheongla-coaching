/* Revised source documents share the type library's editor, trash and export workflow. */
(function(root){'use strict';
const collections={
 mbti_intro:{title:'MBTI 학습법 소개',description:'처음 읽는 안내와 청라학원의 소개글을 나누어 확인하세요.',codes:['intro_learning','intro_letter'],labels:{intro_learning:'학습법 이해 · 활용 안내',intro_letter:'청라 MBTI 학습법 소개글'}},
 mbti_groups:{title:'MBTI 여섯 그룹 학습 성향',description:'전체 비교와 SJ·SP·NFJ·NFP·NTJ·NTP 설명을 항목별로 확인하세요. 원문에 명시된 원장용 참고 자료입니다.',codes:['groups'],labels:{groups:'여섯 그룹 비교 · 실천법'}},
 mbti_parents:{title:'학부모 MBTI 학습지도 안내',description:'종합 안내를 먼저 읽고, 부모님의 기질과 자녀의 기질을 함께 살펴보세요.',codes:['parent_overview','parent_sj','parent_sp','parent_nf','parent_nt'],labels:{parent_overview:'학부모 종합 안내',parent_sj:'SJ 부모',parent_sp:'SP 부모',parent_nf:'NF 부모',parent_nt:'NT 부모'}}
};
function mountPages(api){
 const doc=api.document,pages=[...doc.querySelectorAll('[data-mbti-page]')],uis={};let active='mbti_study';
 for(const[page,collection]of Object.entries(collections)){
  const panel=pages.find(p=>p.dataset.mbtiPage===page),host=doc.createElement('div');host.id='mbtiArticles-'+page;
  // Keep the former article records and markup available for rollback, outside the active reader.
  for(const child of panel.children)child.hidden=true;
  panel.append(host);uis[page]=root.CheonglaMBTILibrary.mount({...api,host,collection});
 }
 return {
  async open(page){if(!pages.some(p=>p.dataset.mbtiPage===page))return;if(uis[active]?.dirty&&!await uis[active].leave())return;
   active=page;for(const panel of pages)panel.hidden=panel.dataset.mbtiPage!==page;
   if(uis[page])await uis[page].open();
  },
  reset(){for(const ui of Object.values(uis))ui.reset();active='mbti_study';},
  get dirty(){return Object.values(uis).some(ui=>ui.dirty);},
  async leave(){for(const ui of Object.values(uis))if(ui.dirty&&!await ui.leave())return false;return true;}
 };
}
root.CheonglaMBTIArticles={mountPages,collections};
})(globalThis);
