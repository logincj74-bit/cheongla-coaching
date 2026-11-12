(function(root){
'use strict';
const doc=root.document,roles=['owner','english_director','math_director','manager'];
const allowed=()=>currentProfile?.approval_status==='approved'&&currentProfile.membership_state==='active'&&roles.includes(currentProfile.role);
const fields={
 학생이름:['text',''],상담일시:['datetime-local',''],시즌연도:['number',''],수능학년도:['number',''],운영시작일:['date',''],운영종료일:['date',''],개강일:['date',''],첫등원일:['date',''],교육비:['number','610000'],납부기한:['date',''],할인율:['number','15'],할인시작일:['date',''],할인종료일:['date',''],청구시작일:['date',''],청구종료일:['date',''],청구금액:['number',''],모집대상:['text','예비고1·2·3'],운영시간:['text','08:00~23:00'],의무학습종료:['text','22:00'],모집기한:['text','상시모집'],은행명:['text',''],계좌번호:['text',''],예금주:['text',''],학원전화:['tel','063-255-2052'],학원휴대폰:['tel','010-8664-2052'],카카오톡:['text','@전주청라독재학원'],인스타그램:['text','cheongla_edu'],주차안내:['text','학원 뒤편 무료 공영주차장을 이용해 주세요.'],할인장학안내:['text',''],시험명:['text',''],시험일:['date','']
};
const names=['대성 더 프리미엄 모의고사','시대인재 서프 모의고사','6월 한국교육과정평가원 모의고사','9월 한국교육과정평가원 모의고사'];
function variables(body){return [...new Set([...String(body).matchAll(/\{\{([^{}]+)\}\}/g)].map(m=>m[1].trim()))];}
function display(key,value){
 if(!value)return '';
 const type=fields[key]?.[0];
 if(type==='date'||type==='datetime-local'){
  const [day,time]=value.split('T'),date=new Date(day+'T00:00:00Z');
  if(Number.isNaN(date.getTime()))return value;
  const text=new Intl.DateTimeFormat('ko-KR',{year:'numeric',month:'long',day:'numeric',weekday:'short',timeZone:'UTC'}).format(date);
  return text+(time?' '+time:'');
 }
 return ['교육비','청구금액'].includes(key)?Number(value).toLocaleString('ko-KR'):value;
}
function render(body,values){return String(body).replace(/\{\{([^{}]+)\}\}/g,(_,key)=>display(key.trim(),values[key.trim()]||''));}
function element(tag,text){const n=doc.createElement(tag);if(text!==undefined)n.textContent=text;return n;}
function button(text,fn,kind='secondary'){const n=element('button',text);n.type='button';n.className=kind;n.addEventListener('click',fn);return n;}
function field(box,label,type='text',value=''){const wrap=element('label',label),input=element(type==='textarea'?'textarea':'input');if(type!=='textarea')input.type=type;input.value=value;input.setAttribute('aria-label',label);wrap.append(input);box.append(wrap);return input;}
function select(box,label,options){const wrap=element('label',label),n=element('select');n.setAttribute('aria-label',label);for(const [value,text] of options)n.append(new Option(text,value));wrap.append(n);box.append(wrap);return n;}
let lifecycle=0,epoch=0,actor=null,rows=[],students=[],bank={},selected=null,editing=null,busy=false,dirty=false,composeDirty=false,previewEdited=false;
let status,chooser,compose,params,preview,recipients,studentSelect,recipientSelect,registeredPhone,contactEditor,contactInput,contactStatus,manualBox,manualPhone,manualRole,search,category,list,editForm,editTitle,editCategory,editAudience,editBody,editDetails,generated=false,paramInputs={};
const panel=element('section');panel.id='officeSmsPanel';panel.hidden=true;panel.className='office-sms';
doc.getElementById('accountPanel').append(panel);accountSectionLabels.officeSmsPanel='청라 문자 발송 안내문';
function valid(){return actor===currentProfile&&allowed();}
function reset(){lifecycle++;epoch++;actor=null;rows=[];students=[];bank={};selected=null;editing=null;dirty=false;composeDirty=false;previewEdited=false;generated=false;paramInputs={};panel.replaceChildren();panel.hidden=true;}
function feedback(text){if(status)status.textContent=text;}
async function leave(){if(!dirty&&!composeDirty)return true;if(!await appConfirm('저장하지 않은 안내문 수정 또는 작성 중인 문자를 버리고 이동할까요?'))return false;dirty=false;composeDirty=false;return true;}
async function mutation(row,action,payload){
 if(busy||!valid())return false;
 if(action!=='save'&&!await appConfirm(action==='purge'?'안내문을 영구삭제할까요? 복구할 수 없습니다.':action==='trash'?'이 안내문을 휴지통으로 이동할까요?':'이 안내문을 복구할까요?'))return false;
 if(!valid())return false;busy=true;
 const requestActor=actor,life=lifecycle;
 try{
  const c=await getClient();if(!valid())return false;
  let q=c.from('cheongla_office_sms_templates');
  if(action==='save')q=row?q.update(payload).eq('id',row.id).eq('revision',row.revision).is('deleted_at',null):q.insert(payload);
  else if(action==='purge')q=q.delete().eq('id',row.id).eq('revision',row.revision).not('deleted_at','is',null);
  else q=q.update({deleted_at:action==='trash'?new Date().toISOString():null}).eq('id',row.id).eq('revision',row.revision);
  const r=await q.select('id');if(requestActor!==currentProfile||!valid()||life!==lifecycle)return false;if(r.error)throw r.error;
  if(r.data?.length!==1)throw Error('다른 직원이 이 안내문을 변경했습니다. 작성 내용을 복사해 보관하고 새로고침해 주세요.');
  feedback(action==='save'?'안내문을 저장했습니다.':action==='purge'?'영구삭제했습니다.':action==='trash'?'휴지통으로 이동했습니다.':'복구했습니다.');
  if(action==='save'){dirty=false;editing=null;editDetails.open=false;}
  if(selected?.id===row?.id&&action!=='save'){selected=null;chooser.value='';compose.replaceChildren();composeDirty=false;}
  await reload();return true;
 }catch(e){if(requestActor===currentProfile)feedback(readable(e));return false;}finally{busy=false;}
}
async function reload(){
 const request=++epoch,c=await getClient();if(!valid())return;
 const r=await c.from('cheongla_office_sms_templates').select('id,title,category,audience,body,deleted_at,revision').order('category').order('title');
 if(!valid()||request!==epoch)return;if(r.error)throw r.error;rows=r.data||[];
 const previous=chooser.value;chooser.replaceChildren(new Option('안내문을 선택해 주세요',''));for(const row of rows.filter(r=>!r.deleted_at))chooser.append(new Option(row.category+' · '+row.title,row.id));
 if(rows.some(r=>r.id===previous&&!r.deleted_at))chooser.value=previous;
 const prev=category.value;category.replaceChildren(new Option('전체 분류',''));for(const name of [...new Set(rows.map(r=>r.category))])category.append(new Option(name,name));category.value=prev;showList();
}
function edit(row){
 editing=row;editTitle.value=row?.title||'';editCategory.value=row?.category||'상담';editAudience.value=row?.audience||'both';editBody.value=row?.body||'';dirty=false;editDetails.open=true;editDetails.scrollIntoView({block:'start'});editTitle.focus();
}
function showList(){
 list.replaceChildren();const trash=element('details');trash.append(element('summary','휴지통 · 복구 · 영구삭제'));
 for(const row of rows){if(category.value&&row.category!==category.value||search.value&&!((row.title+' '+row.body).includes(search.value)))continue;
  const card=element('article');card.className='qa-item';card.append(element('strong',row.category+' · '+row.title));
  if(row.deleted_at)card.append(button('복구',()=>mutation(row,'restore')),button('영구삭제',()=>mutation(row,'purge'),'danger'));
  else card.append(button('선택해 문자 작성',async()=>{if(await choose(row))chooser.value=row.id;}),button('문구 수정',async()=>{if(dirty&&!await appConfirm('저장하지 않은 문구 수정을 버릴까요?'))return;edit(row);}),button('삭제 · 휴지통 이동',()=>mutation(row,'trash'),'text-button'));
  (row.deleted_at?trash:list).append(card);
 }
 if(!trash.querySelector('article'))trash.append(element('p','휴지통이 비어 있습니다.'));list.append(trash);
}
function values(){return Object.fromEntries(Object.entries(paramInputs).map(([k,v])=>[k,v.value.trim()]));}
function stale(){generated=false;composeDirty=true;recipients.replaceChildren(element('p','입력값이 바뀌었습니다. ‘선택값으로 문구 만들기’를 눌러 다시 확인해 주세요.'));}
async function choose(row){
 if(!valid()||busy)return false;
 if(composeDirty&&!await appConfirm('현재 작성 중인 문자를 버리고 다른 안내문을 선택할까요?')){chooser.value=selected?.id||'';return false;}
 selected=row;composeDirty=false;previewEdited=false;generated=false;paramInputs={};compose.replaceChildren();
 compose.append(element('h3',row.title),element('p','학생·일정·금액을 선택하고 문구를 만든 뒤 수정할 수 있습니다. 원본 안내문은 아래 ‘안내문 관리’에서 별도로 수정·저장합니다.'));
 studentSelect=select(compose,'학생 선택',[['','신규 상담 · 직접 입력'],...students.map(s=>[s.student_id,s.student_name])]);
 params=element('form');params.className='office-sms-fields';params.addEventListener('submit',e=>{e.preventDefault();void generate();});
 for(const key of variables(row.body)){
  const [type,initial]=fields[key]||['text',''];let value=initial;
  if(['은행명','계좌번호','예금주'].includes(key))value=({은행명:bank.bank_name,계좌번호:bank.account_number,예금주:bank.account_holder})[key]||'';
  const input=field(params,key,type,value);input.required=true;
  if(type==='number'){input.min=key==='할인율'?'0':['시즌연도','수능학년도'].includes(key)?'2000':'0';input.max=key==='할인율'?'100':['시즌연도','수능학년도'].includes(key)?'2100':'100000000';input.step='1';}
  if(key==='시험명')input.setAttribute('list','cheonglaExamNames');
  input.addEventListener('input',stale);paramInputs[key]=input;
 }
 const registered=element('section');registered.className='notice-form';recipientSelect=select(registered,'수신자 선택',[['','학생을 먼저 선택해 주세요']]);registeredPhone=field(registered,'선택한 수신자 전화번호','tel');registeredPhone.readOnly=true;
 contactEditor=element('details');contactEditor.append(element('summary','선택한 수신자 연락처 수정 · 저장'));const contactForm=element('form');contactInput=field(contactForm,'새 문자 수신 연락처','tel');contactInput.required=true;const contactSave=element('button','연락처 저장');contactSave.type='submit';contactStatus=element('p');contactStatus.setAttribute('role','status');contactForm.append(element('p','선택한 학생 또는 학부모의 문자 수신 연락처를 변경합니다. 가입 아이디는 그대로 유지됩니다.'),contactSave,contactStatus);contactEditor.append(contactForm);registered.append(contactEditor);compose.append(registered);
 contactForm.addEventListener('submit',ev=>{ev.preventDefault();void saveContact();});recipientSelect.addEventListener('change',()=>{updateContact();showRecipients();});
 const manual=element('details');manualBox=manual;manual.append(element('summary','신규 상담자 · 연락처 직접 입력'));manual.className='notice-form';manualRole=select(manual,'직접 입력 수신자 구분',[['parent','학부모'],['student','학생']]);manualPhone=field(manual,'직접 입력 수신번호','tel');manualPhone.placeholder='신규 상담자 또는 전화번호 직접 입력';manualPhone.autocomplete='off';
 if(row.audience==='student')manualRole.value='student';
 preview=field(compose,'최종 문자 내용 · 직접 수정 가능','textarea');preview.rows=18;preview.maxLength=12000;
 preview.addEventListener('input',()=>{previewEdited=true;composeDirty=true;showRecipients();});
 const build=button('선택값으로 문구 만들기',()=>void generate(),'');
 compose.insertBefore(params,preview.parentElement);compose.insertBefore(build,preview.parentElement);compose.append(manual);
 recipients=element('div');recipients.className='office-sms-recipients';compose.append(recipients,element('p','문자 앱에서 수신번호·내용을 확인한 뒤 전송을 누릅니다. 이 화면에서는 발송 여부를 자동 확인하지 않습니다. iPad·PC는 문자 연동이 필요하며, 문구를 복사해 학원 휴대폰에서도 보낼 수 있습니다.'));
 studentSelect.addEventListener('change',()=>{const s=students.find(s=>s.student_id===studentSelect.value);if(paramInputs.학생이름)paramInputs.학생이름.value=s?.student_name||'';if(paramInputs.첫등원일)paramInputs.첫등원일.value=s?.enrolled_on||'';if(paramInputs.교육비)paramInputs.교육비.value=s?.monthly_fee||'610000';manualPhone.value='';updateRecipientChoices();stale();});
 manualPhone.addEventListener('input',showRecipients);manualRole.addEventListener('change',showRecipients);
 feedback(row.category==='교육비'?'교육비는 학부모에게 먼저, 첫 등원 안내는 학생·학부모에게 이어서 보내세요. 금액·계좌·기간을 확인해 주세요.':'날짜와 운영기간은 실제 일정으로 선택해 주세요. 샘플 금액·모집대상도 발송 전 확인합니다.');
 compose.scrollIntoView({block:'start'});updateRecipientChoices();showRecipients();return true;
}
function chosenRecipient(){return students.find(s=>s.student_id===studentSelect?.value)?.recipients?.find(r=>r.id===recipientSelect?.value);}
function updateContact(){
 const r=chosenRecipient();registeredPhone.value=normalizeContactPhone(r?.phone)||'';registeredPhone.placeholder=r?'연락처 미등록':'수신자를 선택해 주세요';
 contactInput.value=normalizeContactPhone(r?.phone)||'';contactEditor.hidden=!r;contactEditor.open=false;contactStatus.textContent='';
}
function updateRecipientChoices(){
 const student=students.find(s=>s.student_id===studentSelect.value),previous=recipientSelect.value;
 recipientSelect.replaceChildren();const targets=(student?.recipients||[]).filter(r=>selected.audience==='both'||r.role===selected.audience);
 for(const r of targets)recipientSelect.append(new Option(r.name+' · '+(r.role==='parent'?'학부모':'학생')+' · '+(normalizeContactPhone(r.phone)||'연락처 미등록'),r.id));
 if(!targets.length)recipientSelect.append(new Option(student?'연결된 수신자가 없습니다':'학생을 먼저 선택해 주세요',''));
 if(targets.some(r=>r.id===previous))recipientSelect.value=previous;recipientSelect.disabled=!targets.length;
 manualBox.hidden=!!student;manualBox.open=!student;if(student)manualPhone.value='';updateContact();
}
async function saveContact(){
 const r=chosenRecipient(),studentId=studentSelect.value,newPhone=normalizeContactPhone(contactInput.value),oldPhone=normalizeContactPhone(r?.phone)||null,requestActor=actor,life=lifecycle;
 if(!valid()||!r||busy)return;if(!newPhone){contactStatus.textContent='올바른 휴대전화번호를 입력해 주세요.';return;}
 if(!await appConfirm(r.name+' '+(r.role==='parent'?'학부모':'학생')+'\n기존: '+(oldPhone||'미등록')+'\n변경: '+newPhone+'\n본인에게 확인한 문자 수신 연락처로 저장할까요?'))return;
 if(!valid()||life!==lifecycle||studentSelect.value!==studentId||chosenRecipient()?.id!==r.id||normalizeContactPhone(contactInput.value)!==newPhone)return;
 busy=true;contactStatus.textContent='연락처를 저장하는 중…';
 try{
  const c=await getClient();if(!valid()||life!==lifecycle)return;
  const saved=await c.rpc('cheongla_office_sms_update_contact',{target_student:studentId,target_member:r.id,new_phone:newPhone,expected_phone:oldPhone});if(saved.error)throw saved.error;
  if(!valid()||actor!==requestActor||life!==lifecycle)return;
  const result=await c.rpc('cheongla_office_sms_students');if(result.error)throw result.error;
  if(!valid()||actor!==requestActor||life!==lifecycle)return;students=result.data||[];
  updateRecipientChoices();showRecipients();contactEditor.open=true;contactStatus.textContent='연락처를 저장했습니다. 이후 문자에도 변경된 번호가 표시됩니다.';
 }catch(e){if(valid()&&life===lifecycle)contactStatus.textContent=readable(e);}finally{busy=false;}
}
function dateRangeError(v){for(const [a,b] of [['운영시작일','운영종료일'],['할인시작일','할인종료일'],['청구시작일','청구종료일']])if(v[a]&&v[b]&&v[a]>v[b])return a+'은 '+b+'보다 늦을 수 없습니다.';return '';}
async function generate(){
 if(!valid()||!selected||!params.reportValidity())return;
 const v=values(),error=dateRangeError(v);if(error){feedback(error);return;}
 if(previewEdited&&!await appConfirm('직접 고친 최종 문자를 선택값으로 다시 만들까요?'))return;
 if(!valid())return;preview.value=render(selected.body,v);generated=true;previewEdited=false;composeDirty=true;showRecipients();feedback('학생 이름·날짜·금액·수신자를 확인한 후 문자 앱을 열어 주세요.');
}
function showRecipients(){
 if(!recipients||!valid())return;recipients.replaceChildren();
 if(!generated||!preview.value.trim()||/\{\{|\}\}/.test(preview.value)){recipients.append(element('p','필수 항목을 입력하고 최종 문구를 만들어 주세요.'));return;}
 const text=preview.value;recipients.append(button('문자 내용 복사',async()=>{if(valid())await copyFeeMessage(preview.value,recipients.querySelector('button'));}));
 const s=students.find(s=>s.student_id===studentSelect.value),audience=selected.audience;
 const options=(s?.recipients||[]).filter(r=>r.id===recipientSelect.value&&(audience==='both'||r.role===audience));
 for(const r of options){const phone=normalizeContactPhone(r.phone);if(!phone){recipients.append(element('p',r.name+' · 연락처가 없습니다. 위 ‘연락처 수정 · 저장’에서 등록해 주세요.'));continue;}
  const b=button(r.name+' '+(r.role==='parent'?'학부모':'학생')+' · '+phone+' 문자 앱 열기',async()=>{
   if(!valid()||busy||!generated)return;const chosen=studentSelect.value,requestActor=actor,body=preview.value;if(!body.trim()||/\{\{|\}\}/.test(body))return;busy=true;
   try{const c=await getClient(),result=await c.rpc('cheongla_office_sms_students');if(result.error)throw result.error;if(requestActor!==currentProfile||!valid()||studentSelect.value!==chosen||recipientSelect.value!==r.id||preview.value!==body)return;
    const fresh=result.data?.find(x=>x.student_id===chosen)?.recipients?.find(x=>x.id===r.id&&x.role===r.role);
    if(!fresh||normalizeContactPhone(fresh.phone)!==phone)throw Error('수신자 연결 또는 번호가 변경되었습니다. 새로고침 후 다시 선택해 주세요.');
    if(!await appConfirm(r.name+' '+(r.role==='parent'?'학부모':'학생')+' · '+phone+'\n최종 문구로 문자 앱을 열까요?'))return;
    if(valid()&&studentSelect.value===chosen&&recipientSelect.value===r.id&&preview.value===body&&generated)root.location.href=examFeeSMSURL(phone,body);
   }catch(e){if(valid())feedback(readable(e));}finally{busy=false;}
  });recipients.append(b);
 }
 const manualNumber=s?'':normalizeContactPhone(manualPhone.value),manualAudience=manualRole.value;
 if(!s&&manualPhone.value&&!manualNumber)recipients.append(element('p','직접 입력한 휴대전화번호를 확인해 주세요.'));
 if(manualNumber){if(audience!=='both'&&audience!==manualAudience)recipients.append(element('p','이 안내문은 '+(audience==='parent'?'학부모':'학생')+'용입니다. 수신자 구분을 확인해 주세요.'));
 else recipients.append(button('직접 입력 번호 '+manualNumber+' · 문자 앱 열기',async()=>{const body=preview.value;if(!valid()||!generated||!body.trim()||/\{\{|\}\}/.test(body))return;if(await appConfirm((manualAudience==='parent'?'학부모':'학생')+' · '+manualNumber+'\n수신번호와 최종 문구를 확인했나요?'))if(valid()&&generated&&normalizeContactPhone(manualPhone.value)===manualNumber&&manualRole.value===manualAudience&&preview.value===body)root.location.href=examFeeSMSURL(manualNumber,body);}));}
 if(!options.length&&!manualNumber)recipients.append(element('p',s?'학생에게 연결된 학부모를 확인하거나 수신자를 선택해 주세요.':'학생을 선택하거나 신규 상담자의 휴대전화번호를 직접 입력해 주세요.'));
}
async function open(){
 if(!allowed())return;reset();actor=currentProfile;panel.hidden=false;const request=++epoch,life=lifecycle;
 panel.append(element('h2','청라 문자 발송 안내문'),element('p','교육비 안내는 학부모에게 먼저 보내고, 첫 등원 안내는 학생·학부모에게 각각 보내 주세요. 실제 운영 일정과 금액을 선택하여 발송합니다.'));
 status=element('p','안내문을 불러오는 중…');status.setAttribute('role','status');panel.append(status);
 chooser=select(panel,'안내문 선택',[['','불러오는 중…']]);chooser.disabled=true;compose=element('section');panel.append(compose);
 const manage=element('details');manage.className='notice-form';manage.append(element('summary','안내문 관리 · 추가 · 수정 · 휴지통'));panel.append(manage);
 editDetails=element('details');editDetails.append(element('summary','안내문 원본 작성 · 수정'));manage.append(button('새 안내문 만들기',async()=>{if(dirty&&!await appConfirm('작성 중인 원본 수정을 버릴까요?'))return;edit(null);}),editDetails);
 editForm=element('form');editDetails.append(editForm);editTitle=field(editForm,'안내문 제목');editTitle.required=true;editTitle.maxLength=150;editCategory=field(editForm,'분류','text','상담');editCategory.required=true;editCategory.maxLength=60;
 editAudience=select(editForm,'기본 수신 대상',[['both','학생·학부모 각각'],['parent','학부모만'],['student','학생만']]);editBody=field(editForm,'안내문 원본 · {{학생이름}}처럼 입력','textarea');editBody.rows=16;editBody.required=true;editBody.maxLength=10000;
 editForm.append(element('p','치환 예시: {{학생이름}}, {{상담일시}}, {{운영시작일}}, {{운영종료일}}, {{첫등원일}}, {{교육비}}, {{납부기한}}, {{시험명}}, {{시험일}}. 새로운 {{항목명}}도 직접 추가할 수 있습니다. 최종 문자 수정은 원본에 저장되지 않습니다.'));
 const save=element('button','원본 안내문 저장');save.type='submit';editForm.append(save);editForm.addEventListener('input',()=>dirty=true);editForm.addEventListener('change',()=>dirty=true);
 editForm.addEventListener('submit',async ev=>{ev.preventDefault();if(!editForm.reportValidity()||!valid()||busy)return;save.disabled=true;try{await mutation(editing,'save',{title:editTitle.value.trim(),category:editCategory.value.trim(),audience:editAudience.value,body:editBody.value.trim()});}finally{save.disabled=false;}});
 search=field(manage,'안내문 검색');category=select(manage,'분류 필터',[['','전체 분류']]);list=element('div');manage.append(button('안내문·학생 새로고침',async()=>{if(await leave())await open();}),list);search.addEventListener('input',showList);category.addEventListener('change',showList);
 chooser.addEventListener('change',()=>{const row=rows.find(r=>r.id===chooser.value&&!r.deleted_at);if(row)void choose(row);else{chooser.value=selected?.id||'';}});
 try{const c=await getClient();if(!valid()||request!==epoch)return;
  const results=await Promise.allSettled([reload(),c.rpc('cheongla_office_sms_students'),c.rpc('cheongla_billing_config')]);if(!valid()||life!==lifecycle)return;
  const [templates,people,config]=results;if(templates.status==='rejected')throw templates.reason;
  let errors=[];if(people.status==='fulfilled'&&!people.value.error)students=people.value.data||[];else errors.push('학생 연락처를 불러오지 못했습니다. 직접 입력하거나 새로고침해 주세요.');
  if(config.status==='fulfilled'&&!config.value.error)bank=config.value.data||{};else errors.push('계좌는 직접 확인하여 입력해 주세요.');
  chooser.disabled=false;feedback(errors.join(' ')||'안내문을 선택해 주세요. 오래된 연도·날짜가 자동 입력되지 않도록 실제 일정을 직접 선택합니다.');
 }catch(e){if(valid())feedback(readable(e));}
}
const previousAllowed=allowedAccountSection;root.allowedAccountSection=id=>id==='officeSmsPanel'?allowed():previousAllowed(id);
const previousMenu=configureDeskMenu;root.configureDeskMenu=function(){previousMenu();doc.getElementById('officeSmsMenu')?.remove();if(allowed()){const b=button('청라 문자 발송 안내문',()=>void openSiteDestination('account_officeSmsPanel'));b.id='officeSmsMenu';doc.getElementById('deskMenuItems').append(b);}else reset();};
const previousOpen=openSiteDestination;root.openSiteDestination=async function(key,...args){if((dirty||composeDirty)&&!await leave())return;if(key==='account_officeSmsPanel'&&!allowed())return;const result=await previousOpen(key,...args);if(key==='account_officeSmsPanel'&&allowed()){await open();if(valid()){panel.scrollIntoView({block:'start'});root.CheonglaDetailNavigation?.align(panel);}}return result;};
const previousClear=clearAccount;root.clearAccount=function(...args){reset();return previousClear(...args);};
root.addEventListener('beforeunload',ev=>{if(dirty||composeDirty){ev.preventDefault();ev.returnValue='';}});
root.CheonglaOfficeSMS={variables,render,dateRangeError,open,reset,allowed,names};
configureDeskMenu();configureAccountSections();
})(globalThis);
