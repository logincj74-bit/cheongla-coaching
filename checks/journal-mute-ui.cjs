const fs = require("fs"),
  assert = require("node:assert/strict"),
  { JSDOM } = require("jsdom");
const dom = new JSDOM('<section><div id="pushSettings"></div></section>', {
    runScripts: "outside-only",
  }),
  w = dom.window,
  d = w.document;
w.eval(fs.readFileSync("journal-mute.js", "utf8"));
let profile = { id: "manager" },
  allowed = true,
  fail = false,
  resolvePending = null,
  delay = null,
  calls = [];
const ui = w.CheonglaJournalMute.mount({
  document: d,
  profile: () => profile,
  allowed: () => allowed,
  readable: (e) => e.message,
  client: async () => ({
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (delay) await delay;
      if (fail) return { error: Error("서버 오류") };
      return {
        data: {
          paused: args?.setting === "paused",
          paused_until:
            args?.setting === "2h"
              ? new Date(Date.now() + 7200000).toISOString()
              : null,
        },
      };
    },
  }),
});
const tick = () => new Promise((r) => setImmediate(r));
(async () => {
  await ui.refresh();
  const section = d.getElementById("journalPushPreferences");
  assert(!section.hidden);
  assert(section.textContent.includes("켜져 있습니다"));
  const click = (label) =>
    [...section.querySelectorAll("button")]
      .find((n) => n.textContent === label)
      .click();
  click("다시 켤 때까지 끄기");
  await tick();
  assert(section.textContent.includes("꺼두었습니다"));
  assert.equal(calls.at(-1).args.setting, "paused");
  click("알림 다시 켜기");
  await tick();
  assert(section.textContent.includes("켜져 있습니다"));
  fail = true;
  click("2시간 쉬기");
  await tick();
  assert(section.textContent.includes("서버 오류"));
  assert([...section.querySelectorAll("button")].every((n) => !n.disabled));
  fail = false;
  delay = new Promise((r) => (resolvePending = r));
  click("다시 켤 때까지 끄기");
  await tick();
  profile = null;
  allowed = false;
  ui.reset();
  resolvePending();
  await tick();
  assert(section.hidden);
  assert.equal(section.querySelector('[role="status"]').textContent, "");
  dom.window.close();
  console.log(
    "PASS journal mute/re-enable, server error retry, disabled controls and stale logout response",
  );
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exit(1);
});
