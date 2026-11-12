process.chdir(require("node:path").join(__dirname, ".."));
const fs = require("fs"),
  assert = require("node:assert/strict"),
  { JSDOM } = require(process.env.JOURNAL_DOM_MODULE || "jsdom");
const html = fs.readFileSync("index.html", "utf8"),
  dom = new JSDOM(html, {
    runScripts: "outside-only",
    url: "https://example.invalid",
  }),
  w = dom.window,
  d = w.document;
w.eval(`var financeEnabled=()=>true,feeNoticesEnabled=()=>true;window.CheonglaFeatures={finance:true};var currentProfile=null,activeAccountSection=null;var $=id=>document.getElementById(id);var accountSectionLabels=${html.match(/const accountSectionLabels=(\{[^\n]+\});/)[1]};
var showSiteHome=()=>{},clearAccount=()=>{};var canManageLife=()=>currentProfile?.approval_status==='approved'&&currentProfile?.membership_state==='active'&&['owner','english_director','math_director','manager'].includes(currentProfile.role);var canManageMealForms=canManageLife,canManageAccountRecovery=canManageLife;var isPrincipal=()=>canManageLife()&&currentProfile.role!=='manager';var isAppAdmin=()=>false;var appConfirm=async()=>true,readable=e=>e.message;var getClient=async()=>({rpc:async()=>({data:[]})});var renderMealCancelContacts=()=>{},configureStaffWorkspace=()=>{},feeDepositInstructions=()=>'';var allowedAccountSection=()=>true,accountSectionGroup=()=> '내 계정',configureAccountSections=()=>{},useAccountSections=()=>false,applyAccountSection=()=>{},tuitionText=()=>{},openSiteDestination=async k=>{window.lastRoute=k;},openMemberBilling=()=>{};`);
w.eval(
  html.slice(
    html.indexOf("function configureDeskMenu(){"),
    html.indexOf("async function loadApplicationStudents"),
  ),
);
w.eval(`
var canManageExams=canManageLife,canAdministerMembers=isPrincipal,canManageContacts=canManageLife,canCoachAll=isPrincipal;
var canUseTuition=canManageLife,canUseExamFees=canManageLife,canUseBilling=()=>false,canUseMealForms=()=>false,canUseExams=()=>false;
var canUseSchedule=()=>currentProfile?.approval_status==='approved',canUseBoard=canUseSchedule,canUseInbox=canUseSchedule,canUseMBTIStudy=canManageLife;
useAccountSections=()=>currentProfile?.approval_status==='approved';
`);
w.eval(html.match(/^function canUseMBTIStudy\(\).*$/m)[0]);
w.eval(html.match(/^function canEditMBTIStudy\(\).*$/m)[0]);
w.eval(html.match(/^function allowedAccountSection\(id\).*$/m)[0]);
w.eval(fs.readFileSync("content-trash.js", "utf8"));
w.eval(fs.readFileSync("staff-journal.js", "utf8"));
d.dispatchEvent(new w.Event("DOMContentLoaded"));
w.eval(fs.readFileSync("score-coaching.js", "utf8"));
w.eval(fs.readFileSync("journal-mute.js", "utf8"));
w.eval(fs.readFileSync("role-coaching.js", "utf8"));
const texts = (id) =>
  [...d.getElementById(id).querySelectorAll("button")].map(
    (n) => n.textContent,
  );
for (const role of [
  "owner",
  "english_director",
  "math_director",
  "manager",
  "student",
  "parent",
]) {
  w.currentProfile = {
    id: role,
    role,
    approval_status: "approved",
    membership_state: "active",
  };
  w.configureDeskMenu();
  const items = texts("deskMenuItems"),
    staff = ["owner", "english_director", "math_director", "manager"].includes(
      role,
    ),
    principal = staff && role !== "manager";
  assert.equal(items.includes("청라 근무일지"), staff);
  assert.equal(items.includes("상담 · 신규 등록카드"), staff);
  assert.equal(items.includes("휴지통 관리"), principal);
  assert(items.includes("내 전화번호 등록 · 수정"));
  assert(!d.getElementById("askMenu").hidden);
  assert.equal(d.getElementById("feeNoticeMenu").hidden,!staff);
  assert(d.getElementById("financeMenu").hidden);
  assert.equal(d.getElementById("englishMenu").hidden,!principal);
  assert.equal(w.allowedAccountSection("mbtiStudyPanel"), staff);
  assert.equal(w.canEditMBTIStudy(),staff);
  assert.equal([...d.querySelectorAll("#siteNavigation .site-menu")].find(n=>n.querySelector("summary")?.textContent.includes("나의 MBTI")).hidden,!staff);
  assert.equal(w.allowedAccountSection("tuitionPanel"), staff || role === "parent");
  w.configureAccountSections();
  const accountButtons = texts("accountSectionButtons");
  assert.equal(
    accountButtons.includes("성적 변화 · 학습코칭"),
    role !== "manager",
  );
  assert.equal(accountButtons.includes("MBTI 학습법"), staff);
  for (const retired of (principal ? [] : [
    "englishPanel",
    "externalPanel",
    "billingPanel",
    "mealPanel",
    "examPanel",
  ])) {
    assert(
      !d.querySelector(
        '#accountSectionButtons [data-section="' + retired + '"]',
      ),
    );
  }
  for (const id of ["mealPanel", "examPanel", "externalPanel", "englishPanel"])
    assert.equal(w.allowedAccountSection(id), principal);
  assert.equal(texts("feeNoticeMenuItems").includes("학원비 안내"), staff);
  assert(!items.includes("학원비 안내"));
}
(async () => {
  w.currentProfile = {
    id: "student",
    role: "student",
    approval_status: "approved",
    membership_state: "active",
  };
  await w.openSiteDestination("mbti_intro");
  assert.notEqual(w.lastRoute, "mbti_intro");
  w.currentProfile = {id:"manager", role:"manager", approval_status:"approved", membership_state:"active"};
  await w.openSiteDestination("mbti_intro");
  assert.equal(w.lastRoute,"mbti_intro");
  w.currentProfile = {id:"student", role:"student", approval_status:"approved", membership_state:"active"};
  await w.openSiteDestination("english_book");
  assert.notEqual(w.lastRoute, "english_book");
  await w.openSiteDestination("account_scoreCoachingPanel");
  assert.equal(w.lastRoute, "account_scoreCoachingPanel");
  const summary = w.CheonglaScoreCoaching.analyze(
    [{ subject: "국어", grade: 2, percentile: 90 }],
    [
      {
        exam_on: "2026-10-01",
        title: "이전",
        scores: [{ subject: "국어", grade: 3, percentile: 80 }],
      },
    ],
  );
  assert(summary.includes("+10"));
  assert(summary.includes("등급 개선"));
  dom.window.close();
  console.log(
    "PASS six role menus, deep-link restrictions, common help, manager-only embedded fees, staff MBTI and principal-only trash, score coaching entry and trend analysis",
  );
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exit(1);
});
