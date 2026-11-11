(function (root) {
  "use strict";
  function mount(api) {
    const doc = api.document,
      host = doc.createElement("section");
    host.className = "notice-form";
    host.id = "journalPushPreferences";
    host.hidden = true;
    host.setAttribute("data-no-print", "");
    const title = doc.createElement("h3");
    title.textContent = "근무일지 알림";
    const note = doc.createElement("p");
    note.textContent =
      "일시중지는 모든 기기의 근무일지 푸시 알림에 적용됩니다. 기록과 앱 알림함에서는 계속 확인할 수 있습니다.";
    const status = doc.createElement("p");
    status.setAttribute("role", "status");
    const actions = doc.createElement("div");
    actions.className = "row";
    host.append(title, note, actions, status);
    doc.getElementById("pushSettings").before(host);
    let actor = null,
      request = 0,
      busy = false;
    for (const [mode, label] of [
      ["2h", "2시간 쉬기"],
      ["tomorrow", "내일 오전 8시까지 쉬기"],
      ["paused", "다시 켤 때까지 끄기"],
      ["on", "알림 다시 켜기"],
    ]) {
      const b = doc.createElement("button");
      b.type = "button";
      b.className = "secondary";
      b.textContent = label;
      b.addEventListener("click", () => save(mode));
      actions.append(b);
    }
    function render(value) {
      status.textContent = value.paused
        ? "근무일지 푸시 알림을 꺼두었습니다."
        : value.paused_until && Date.parse(value.paused_until) > Date.now()
          ? "알림 일시중지 · " +
            new Date(value.paused_until).toLocaleString("ko-KR", {
              timeZone: "Asia/Seoul",
            }) +
            "까지"
          : "근무일지 푸시 알림이 켜져 있습니다.";
    }
    function reset() {
      request++;
      actor = null;
      busy = false;
      host.hidden = true;
      status.textContent = "";
    }
    async function refresh() {
      if (!api.allowed()) {
        reset();
        return;
      }
      if (actor === api.profile()) return;
      const who = api.profile(),
        seq = ++request;
      actor = who;
      host.hidden = false;
      actions.querySelectorAll("button").forEach((b) => (b.disabled = true));
      try {
        const c = await api.client(),
          r = await c.rpc("cheongla_journal_push_preference");
        if (r.error) throw r.error;
        if (who === api.profile() && seq === request) render(r.data);
      } catch (e) {
        if (seq === request) {
          actor = null;
          status.textContent = api.readable(e);
        }
      } finally {
        if (seq === request)
          actions
            .querySelectorAll("button")
            .forEach((b) => (b.disabled = false));
      }
    }
    async function save(mode) {
      if (busy || !api.allowed()) return;
      const who = api.profile(),
        seq = ++request;
      busy = true;
      actions.querySelectorAll("button").forEach((b) => (b.disabled = true));
      try {
        const c = await api.client(),
          r = await c.rpc("cheongla_set_journal_push_preference", {
            setting: mode,
          });
        if (r.error) throw r.error;
        if (who === api.profile() && seq === request) render(r.data);
      } catch (e) {
        if (seq === request) status.textContent = api.readable(e);
      } finally {
        if (seq === request) {
          busy = false;
          actions
            .querySelectorAll("button")
            .forEach((b) => (b.disabled = false));
        }
      }
    }
    return { refresh, reset };
  }
  root.CheonglaJournalMute = { mount };
})(globalThis);
