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
  calls = [];
const ui = w.CheonglaScoreCoaching.mount({
  document: d,
  profile: () => profile,
  principal: () => profile.role === "owner",
  confirm: async () => true,
  readable: (e) => e.message,
  client: async () => ({
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
  await ui.open();
  assert(d.querySelector("form"));
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
  profile = { id: "parent", role: "parent" };
  ui.reset();
  rows = [{ ...saved, revision: undefined }];
  await ui.open();
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
    "PASS owner score edit/save/publish, parent read-only report, cleared old-account report, dirty navigation confirmation",
  );
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exit(1);
});
