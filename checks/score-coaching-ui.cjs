const fs = require("fs"),
  assert = require("node:assert/strict"),
  { JSDOM } = require("jsdom");
const dom = new JSDOM('<section id="scoreCoachingPanel"></section>', {
    runScripts: "outside-only",
  }),
  w = dom.window,
  d = w.document;
w.eval(fs.readFileSync("score-coaching.js", "utf8"));
const people = [{ id: "student", name: "테스트학생" }],
  saved = {
    id: "report",
    student_id: "student",
    exam_on: "2026-11-01",
    title: "모의고사",
    scores: [
      { subject: "국어", raw: 80, standard: 120, percentile: 87, grade: 3 },
    ],
    report: "확인한 코칭",
    revision: 1,
  };
let profile = { id: "owner", role: "owner" },
  rows = [saved],
  calls = [], photoCalls = [], consent = true, photoFailure = false, photoResponse = null;
const ui = w.CheonglaScoreCoaching.mount({
  document: d,
  profile: () => profile,
  principal: () => profile.role === "owner",
  confirm: async () => consent,
  readable: (e) => e.message,
  client: async () => ({
    functions: {invoke: async (name,args)=>{photoCalls.push({name,args});if(photoResponse)return await photoResponse;if(photoFailure)return {error:{context:{status:402,json:async()=>({code:'api_credit',error:'OpenAI API 사용 가능 잔액을 확인해 주세요.'})}}};return {data:{scores:[{subject:'수학(미적분)',raw:90,standard:130,percentile:97,grade:1}]},error:null};}},
    rpc: async (name, args) => {
      calls.push({ name, args });
      return {
        data:
          name === "cheongla_score_coaching_list"
            ? { students: people, items: rows }
            : saved,
      };
    },
  }),
});
const click = (label) =>
    [...d.querySelectorAll("button")]
      .find((n) => n.textContent === label)
      .click(),
  tick = () => new Promise((r) => setImmediate(r));
(async () => {
  ui.reset();assert(d.getElementById("scoreCoachingPanel").hidden);
  await ui.open();
  assert(!d.getElementById("scoreCoachingPanel").hidden,"opened score screen remained hidden");
  assert.equal(d.querySelector('label[for="scoreCoachingStudentSelect"]').textContent,"학생 선택");
  assert(d.querySelector("form"));
  assert(d.querySelector('input[type="file"]').disabled);
  const beforePhoto = calls.length;
  click("사진 자동 읽기 · 준비 중");
  await tick();
  assert.equal(calls.length, beforePhoto);
  assert(d.body.textContent.includes("점수를 직접 입력해 주세요."));
  assert(d.body.textContent.includes("백분위 87"));
  click("수정");
  await tick();
  assert.equal(d.querySelector("textarea").value, "확인한 코칭");
  const title = [...d.querySelectorAll("label")]
    .find((n) => n.textContent === "시험명")
    .querySelector("input");
  title.value = "변경";
  title.dispatchEvent(new w.Event("input", { bubbles: true }));
  assert(ui.dirty);
  assert(await ui.leave());
  assert(!ui.dirty);
  click("성적 · 코칭 초안 저장");
  await tick();
  await tick();
  assert(
    calls.some(
      (c) =>
        c.name === "cheongla_save_score_coaching" &&
        c.args.expected_revision === 1,
    ),
  );
  click("학생·학부모에게 공유");
  await tick();
  await tick();
  assert(
    calls.some(
      (c) =>
        c.name === "cheongla_score_coaching_action" &&
        c.args.action === "publish",
    ),
  );
  // The deployed switch enables the complete upload -> consent -> editable draft flow.
  w.eval(fs.readFileSync('feature-flags.js','utf8'));assert.equal(w.CheonglaFeatures.scoreOcr,true);ui.reset();await ui.open();
  const file=d.querySelector('input[type="file"]');assert(!file.disabled);Object.defineProperty(file,'files',{value:[{size:100}]});
  w.FileReader=class{readAsDataURL(){this.result='data:image/jpeg;base64,YWJj';Promise.resolve().then(()=>this.onload());}};
  w.Image=class{width=100;height=100;set src(value){Promise.resolve().then(()=>this.onload());}};
  w.HTMLCanvasElement.prototype.getContext=()=>({drawImage(){}});w.HTMLCanvasElement.prototype.toDataURL=()=> 'data:image/jpeg;base64,YWJj';
  const savedBeforePhoto=calls.filter(c=>c.name==='cheongla_save_score_coaching').length;
  consent=false;file.dispatchEvent(new w.Event('change',{bubbles:true}));await tick();assert.equal(photoCalls.length,0,'photo sent without consent');
  consent=true;file.dispatchEvent(new w.Event('change',{bubbles:true}));file.dispatchEvent(new w.Event('change',{bubbles:true}));await tick();await tick();await tick();
  assert.equal(photoCalls.length,1);assert.equal(photoCalls[0].name,'cheongla-score-extract');assert.deepEqual(Object.keys(photoCalls[0].args.body).sort(),['exam_type','image']);assert.equal(photoCalls[0].args.body.exam_type,'mock');
  assert([...d.querySelectorAll('input')].some(n=>n.value==='수학(미적분)'));assert([...d.querySelectorAll('input[type="number"]')].some(n=>n.value==='90'));assert(d.body.textContent.includes('인식 초안입니다'));
  assert.equal(calls.filter(c=>c.name==='cheongla_save_score_coaching').length,savedBeforePhoto,'OCR saved without review');
  const readScore=[...d.querySelectorAll('input[type="number"]')].find(n=>n.value==='90');readScore.value='91';photoFailure=true;click('사진 다시 읽기');await tick();await tick();assert.equal(readScore.value,'91','failed extraction overwrote reviewed scores');assert(d.body.textContent.includes('OpenAI API 사용 가능 잔액을 확인해 주세요.'));assert(!d.body.textContent.includes('성적표 인식 서버 연결을 확인')); photoFailure=false;click('사진 다시 읽기');await tick();await tick();await tick();
  [...d.querySelectorAll('label')].find(n=>n.textContent==='시험명').querySelector('input').value='인식 검토 테스트';
  click('성적 · 코칭 초안 저장');await tick();await tick();const photoSaved=calls.filter(c=>c.name==='cheongla_save_score_coaching').at(-1);assert.equal(photoSaved.args.subject_scores[0].subject,'수학(미적분)');assert.equal(photoSaved.args.subject_scores[0].raw,90);
  let completePhoto;photoResponse=new Promise(resolve=>completePhoto=resolve);const pendingFile=d.querySelector('input[type="file"]');Object.defineProperty(pendingFile,'files',{value:[{size:100}]});pendingFile.dispatchEvent(new w.Event('change',{bubbles:true}));await tick();await tick();assert(pendingFile.disabled);assert(d.querySelector('#scoreCoachingStudentSelect').disabled);const saveCount=calls.filter(c=>c.name==='cheongla_save_score_coaching').length;click('성적 · 코칭 초안 저장');await tick();assert.equal(calls.filter(c=>c.name==='cheongla_save_score_coaching').length,saveCount);
  profile = { id: "parent", role: "parent" };
  ui.reset();
  rows = [{ ...saved, revision: undefined }];
  await ui.open();
  completePhoto({data:{scores:[{subject:'이전 계정의 인식 결과',raw:55}]},error:null});await tick();await tick();assert(!d.body.textContent.includes('이전 계정의 인식 결과'));assert(!ui.dirty);
  assert(!d.querySelector("form"));
  assert(!d.body.textContent.includes("성적 · 코칭 초안 저장"));
  assert(d.body.textContent.includes("확인한 코칭"));
  profile = { id: "other", role: "student" };
  ui.reset();
  rows = [];
  await ui.open();
  assert(!d.body.textContent.includes("확인한 코칭"));
  dom.window.close();
  console.log(
    "PASS automatic photo-change OCR/consent/deduplication/error preservation/late-response isolation/explicit save with mocked provider, owner score edit/save/publish, parent read-only report, cleared old-account report, dirty navigation confirmation",
  );
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exit(1);
});
