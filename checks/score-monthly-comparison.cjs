const fs = require("fs"),
  assert = require("node:assert/strict"),
  { JSDOM } = require("jsdom");
const dom = new JSDOM('<section id="scoreCoachingPanel"></section>', {
    runScripts: "outside-only",
    url: "https://example.invalid/cheongla/",
  }),
  w = dom.window,
  d = w.document;
w.HTMLDialogElement.prototype.showModal = function () {};
for (const path of ["score-coaching.js", "print-tools.js", "document-brand.js"])
  w.eval(fs.readFileSync(path, "utf8"));
const scores = (raw, standard, percentile, grade) => [
    { subject: "국어", raw, standard, percentile, grade },
  ],
  student = "student";
const current = {
  id: "current",
  student_id: student,
  exam_kind: "mock",
  exam_on: "2026-01-15",
  title: "당월 시험",
  scores: scores(84, 125, 88.5, 2),
  report: "확인한 코칭",
  revision: 1,
};
const previous = {
  id: "previous",
  student_id: student,
  exam_kind: "mock",
  exam_on: "2025-12-20",
  title: "전월 시험",
  scores: scores(80, 120, 85.2, 3),
  report: "이전 코칭",
  revision: 1,
};
const records = [
  current,
  previous,
  {
    ...previous,
    id: "earlier",
    exam_on: "2025-12-03",
    scores: scores(75, 115, 82, 4),
  },
  { ...previous, id: "csat", exam_kind: "csat", exam_on: "2025-12-31" },
  {
    ...previous,
    id: "other-student",
    student_id: "other",
    exam_on: "2025-12-31",
  },
  {
    ...previous,
    id: "deleted",
    archived_at: "2026-01-01",
    exam_on: "2025-12-31",
  },
];
const { monthlyComparison, previousMonth, changeText } =
  w.CheonglaScoreCoaching;
assert.equal(previousMonth("2026-01"), "2025-12");
assert.equal(previousMonth("2024-03"), "2024-02");
let comparison = monthlyComparison(records, "current");
assert.equal(comparison.previous.id, "previous");
assert.equal(comparison.candidates.length, 2);
assert.deepEqual(
  Array.from(comparison.rows[0].metrics, (x) => x.change),
  ["+4", "+5", "+3.3", "-1 · 등급 개선"],
);
assert.equal(
  monthlyComparison(records, "current", "earlier").previous.id,
  "earlier",
);
assert.equal(monthlyComparison(records, "csat"), null);
const missing = monthlyComparison([current], "current");
assert.equal(missing.previous, null);
assert(missing.rows[0].metrics.every((x) => x.change === "비교 자료 없음"));
assert.equal(changeText(0, 1, "raw"), "+1");
assert.equal(changeText(null, 1, "raw"), "비교 자료 없음");
comparison = monthlyComparison(
  [
    { ...current, scores: [{ subject: "수학(나형)", raw: 40, grade: 4 }] },
    { ...previous, scores: [{ subject: "수학(가형)", raw: 45, grade: 3 }] },
  ],
  "current",
);
assert.equal(comparison.rows.length, 2);
assert(
  comparison.rows.every((row) =>
    row.metrics.every((x) => x.change === "비교 자료 없음"),
  ),
);
let calls = [];
// Keep the actor stable, as the normal authenticated app does.
const owner = { id: "owner" };
const stableApi = {
  document: d,
  profile: () => owner,
  principal: () => true,
  confirm: async () => true,
  readable: (e) => e.message,
  client: async () => ({
    rpc: async (name, args) => {
      calls.push({ name, args });
      return {
        data:
          name === "cheongla_score_coaching_list"
            ? {
                students: [{ id: student, name: "검증 학생" }],
                items: [current, previous],
              }
            : current,
      };
    },
  }),
};
const stable = w.CheonglaScoreCoaching.mount(stableApi);
const tick = () => new Promise((r) => setImmediate(r));
(async () => {
  await stable.open();
  const panel = d.querySelector("[data-monthly-comparison]");
  assert(panel);
  assert(panel.textContent.includes("+3.3"));
  [...panel.querySelectorAll("button")]
    .find((b) => b.textContent === "비교표 인쇄 / PDF 저장")
    .click();
  const printed = d.querySelector("iframe").contentDocument;
  assert.equal(
    printed.querySelector(".print-brand strong").textContent,
    "전주 독학재수 청라학원",
  );
  assert.match(
    printed.querySelector(".print-brand img").src,
    /cheongla-icon-180-v2\.png$/,
  );
  assert(printed.body.textContent.includes("전월 시험"));
  assert(printed.body.textContent.includes("당월 시험"));
  assert(printed.body.textContent.includes("+3.3"));
  assert.equal(printed.querySelectorAll("tr").length, 5);
  d.querySelectorAll("dialog button")[1].click();
  [...d.querySelectorAll("button")]
    .find((b) => b.textContent === "수정")
    .click();
  await tick();
  const type = [...d.querySelectorAll("label")]
    .find((n) => n.firstChild.textContent === "시험 구분")
    .querySelector("select");
  type.value = "csat";
  type.dispatchEvent(new w.Event("change", { bubbles: true }));
  await tick();
  const raw = [...d.querySelectorAll("label")]
    .filter((n) => n.firstChild.textContent === "원점수")
    .map((n) => n.querySelector("input"));
  assert(raw.every((n) => n.disabled && n.value === ""));
  [...d.querySelectorAll("button")]
    .find((b) => b.textContent === "성적 · 코칭 초안 저장")
    .click();
  await tick();
  await tick();
  const save = calls.find((c) => c.name === "cheongla_save_score_coaching");
  assert.equal(save.args.exam_type, "csat");
  assert(save.args.subject_scores.every((s) => s.raw === null));
  dom.window.close();
  console.log(
    "PASS exact previous month/year rollover, multiple exams, all metrics, missing data, elective distinction, excluded CSAT/other student/trash, CSAT raw input guard, branded comparison print/PDF preview",
  );
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exit(1);
});
