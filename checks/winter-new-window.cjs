const fs = require("fs"),
  assert = require("node:assert/strict"),
  { JSDOM } = require("jsdom");
const tick = () => new Promise((r) => setImmediate(r));
async function fixture(role = "student") {
  const dom = new JSDOM(fs.readFileSync("index.html", "utf8"), {
      runScripts: "outside-only",
      pretendToBeVisual: true,
      url: "https://logincj74-bit.github.io/cheongla-coaching/",
    }),
    w = dom.window,
    d = w.document;
  let profile = {
      id: "member",
      role,
      approval_status: "approved",
      membership_state: "active",
    },
    rpcError = false,
    blocked = false,
    delay = null,
    popup,
    posted = [],
    opened = 0,
    replaced = [];
  w.open = () => {
    opened++;
    if (blocked) return null;
    const view = new JSDOM("<body></body>", { url: w.location.href });
    view.window.HTMLFormElement.prototype.submit = function () {
      posted.push({
        target: this.target,
        action: this.action,
        method: this.method,
        code: this.elements.code?.value,
      });
    };
    popup = {
      document: view.window.document,
      closed: false,
      opener: w,
      close() {
        this.closed = true;
      },
      location: { replace: (href) => replaced.push(href) },
      dispose: () => view.window.close(),
    };
    return popup;
  };
  const row = {
    title: "윈터",
    button_text: "모집안내",
    first_open: true,
    second_open: true,
    first_date: "2026-12-21",
    second_date: "2026-12-28",
    ends_at: null,
  };
  const query = {};
  for (const key of ["select", "eq", "is", "or"]) query[key] = () => query;
  query.maybeSingle = async () => ({ data: row });
  w.eval(fs.readFileSync("winter-promotion.js", "utf8"));
  const ui = w.CheonglaWinterPromotion.mount({
    document: d,
    profile: () => profile,
    principal: () => role === "owner",
    confirm: async () => true,
    readable: (e) => e.message,
    client: async () => ({
      from: () => query,
      rpc: async () => {
        if (delay) await delay;
        return rpcError ? { error: Error("failed") } : { data: "a".repeat(64) };
      },
    }),
  });
  ui.refresh();
  await tick();
  const link = d.querySelector("#winterPromotion a");
  assert(link);
  assert.equal(link.target, "_blank");
  assert.equal(link.rel, "noopener noreferrer");
  return {
    w,
    d,
    link,
    posted,
    replaced,
    get opened() {
      return opened;
    },
    get popup() {
      return popup;
    },
    set blocked(v) {
      blocked = v;
    },
    set rpcError(v) {
      rpcError = v;
    },
    set delay(v) {
      delay = v;
    },
    logout() {
      profile = null;
    },
    close() {
      popup?.dispose();
      w.close();
    },
  };
}
(async () => {
  let f = await fixture();
  f.link.dispatchEvent(
    new f.w.MouseEvent("click", { button: 0, bubbles: true, cancelable: true }),
  );
  await tick();
  assert.equal(f.opened, 1);
  assert.equal(f.posted.length, 1);
  assert.equal(f.posted[0].target, "_self");
  assert(f.posted[0].action.endsWith("/api/student/cheongla"));
  assert.equal(f.popup.opener, null);
  assert.equal(
    f.w.location.href,
    "https://logincj74-bit.github.io/cheongla-coaching/",
  );
  f.close();
  f = await fixture("parent");
  f.rpcError = true;
  f.link.dispatchEvent(
    new f.w.MouseEvent("click", { button: 0, cancelable: true }),
  );
  await tick();
  assert.equal(f.posted.length, 0);
  assert.equal(f.replaced.length, 1);
  f.close();
  f = await fixture();
  let release;
  f.delay = new Promise((r) => (release = r));
  f.link.dispatchEvent(
    new f.w.MouseEvent("click", { button: 0, cancelable: true }),
  );
  await tick();
  f.popup.close();
  release();
  await tick();
  assert.equal(f.posted.length, 0);
  assert.equal(f.opened, 1);
  f.close();
  f = await fixture();
  f.delay = new Promise((r) => (release = r));
  f.link.dispatchEvent(
    new f.w.MouseEvent("click", { button: 0, cancelable: true }),
  );
  await tick();
  f.logout();
  release();
  await tick();
  assert.equal(f.posted.length, 0);
  assert(f.popup.closed);
  f.close();
  f = await fixture();
  f.blocked = true;
  const e = new f.w.MouseEvent("click", { button: 0, cancelable: true });
  f.link.dispatchEvent(e);
  await tick();
  assert(!e.defaultPrevented);
  assert.equal(f.posted.length, 0);
  f.close();
  f = await fixture("owner");
  const ownerEvent = new f.w.MouseEvent("click", {
    button: 0,
    cancelable: true,
  });
  f.link.dispatchEvent(ownerEvent);
  assert(!ownerEvent.defaultPrevented);
  assert.equal(f.opened, 0);
  f.close();
  console.log(
    "PASS Winter new-window link, POST in the opened window, opener removal, source-page preservation, API failure fallback, closed-popup and logout cancellation, blocked-popup native fallback",
  );
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
