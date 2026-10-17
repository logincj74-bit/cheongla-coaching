const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const h=fs.readFileSync(require('path').join(__dirname,'../index.html'),'utf8');
class N{constructor(){this.children=[];this.dataset={};this.hidden=false;this.classes=new Set();this.classList={add:x=>this.classes.add(x),remove:x=>this.classes.delete(x),toggle:(x,b)=>b?this.classes.add(x):this.classes.delete(x)}}setAttribute(k,v){this[k]=v}}
const nodes={},$=id=>nodes[id]??=new N();let allowed=['examPanel','mealPanel','billingPanel','noticesPanel'];
const c=vm.createContext({$,currentProfile:{role:'manager'},useAccountSections:()=>true,allowedAccountSection:id=>allowed.includes(id),accountSectionLabels:Object.fromEntries(allowed.map(x=>[x,x])),isAppAdmin:()=>false,canManageMealForms:()=>true});
vm.runInContext(h.slice(h.indexOf('function applyAccountSection('),h.indexOf('function configureStaffWorkspace(')),c);
for(const key of allowed){const b=new N();b.dataset.section=key;$('accountSectionButtons').children.push(b);}
$('accountMenuDrawer').open=true;c.applyAccountSection('examRosterManager');assert.equal($('accountMenuDrawer').open,false);assert(!$('examPanel').classes.has('account-section-inactive'));assert($('mealPanel').classes.has('account-section-inactive'));assert($('studentExamWorkspace').classes.has('account-section-inactive'));assert($('staffWorkspace').classes.has('account-section-inactive'));assert.equal($('accountSectionButtons').children[0]['aria-current'],'page');assert($('accountSectionTitle').textContent.startsWith('청라 운영 업무'));
c.applyAccountSection('approvalPanel');assert(!$('examPanel').classes.has('account-section-inactive'));
assert(h.includes("desk_roster:[canManageExams(),'examPanel']"));assert(!h.includes('신청·취소는 학생 계정에서 진행합니다.'));
assert(h.includes('href="guide.html"'));assert(h.includes("['billing_dashboard','청구 · 입금 관리']"));
for(const m of h.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(m[1]);
console.log('PASS compact role workspace: duplicate shortcuts hidden, drawer closes on navigation, selected task only, permission gate retained, exam menu opens full composer/roster, parent copy matches application support');
