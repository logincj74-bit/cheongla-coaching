(function (root) {
  "use strict";
  const metrics = {
    raw: "원점수",
    standard: "표준점수",
    percentile: "백분위",
    grade: "등급",
  };
  const examKinds = { mock: "학원 모의고사", csat: "수능" };
  const subjectKey = (value) =>
    String(value).normalize("NFKC").replace(/\s+/g, "").replace(/[·ㆍ]/g, "");
  const examKind = (record) => (record?.exam_kind === "csat" ? "csat" : "mock");
  function previousMonth(month) {
    const date = new Date(month + "-01T00:00:00Z");
    date.setUTCMonth(date.getUTCMonth() - 1);
    return date.toISOString().slice(0, 7);
  }
  function changeText(before, after, metric) {
    if (before == null || after == null) return "비교 자료 없음";
    const change = Math.round((after - before) * 100) / 100;
    if (change === 0) return "동일";
    return (
      (change > 0 ? "+" : "") +
      change +
      (metric === "grade" ? (change < 0 ? " · 등급 개선" : " · 등급 하락") : "")
    );
  }
  function monthlyComparison(records, currentId, previousId) {
    const current = records.find(
      (record) =>
        record.id === currentId &&
        !record.archived_at &&
        examKind(record) === "mock",
    );
    if (!current) return null;
    const month = previousMonth(current.exam_on.slice(0, 7));
    const candidates = records
      .filter(
        (record) =>
          !record.archived_at &&
          record.student_id === current.student_id &&
          examKind(record) === "mock" &&
          record.exam_on.slice(0, 7) === month,
      )
      .sort(
        (a, b) =>
          b.exam_on.localeCompare(a.exam_on) || b.id.localeCompare(a.id),
      );
    const previous =
      candidates.find((record) => record.id === previousId) ||
      candidates[0] ||
      null;
    const before = new Map(
      (previous?.scores || []).map((score) => [
        subjectKey(score.subject),
        score,
      ]),
    );
    const after = new Map(
      current.scores.map((score) => [subjectKey(score.subject), score]),
    );
    const subjects = [...new Set([...after.keys(), ...before.keys()])];
    return {
      current,
      previous,
      candidates,
      month,
      rows: subjects.map((key) => ({
        subject: (after.get(key) || before.get(key)).subject,
        metrics: Object.keys(metrics).map((metric) => ({
          metric,
          before: before.get(key)?.[metric] ?? null,
          after: after.get(key)?.[metric] ?? null,
          change: changeText(
            before.get(key)?.[metric],
            after.get(key)?.[metric],
            metric,
          ),
        })),
      })),
    };
  }
  function analyze(scores, history) {
    const lines = ["과목별 학습 점검"];
    for (const score of scores) {
      const previous = history.find((r) =>
        r.scores?.some(
          (s) => subjectKey(s.subject) === subjectKey(score.subject),
        ),
      );
      const before = previous?.scores.find(
        (s) => subjectKey(s.subject) === subjectKey(score.subject),
      );
      const results = Object.entries(metrics)
        .filter(([k]) => score[k] != null)
        .map(([k, label]) => label + " " + score[k])
        .join(" · ");
      lines.push("\n" + score.subject + " — " + results);
      const sharedMetrics = Object.keys(metrics).filter(
        (key) => score[key] != null && before?.[key] != null,
      );
      if (sharedMetrics.length) {
        lines.push(previous.exam_on + " " + previous.title + " 대비");
        for (const metric of sharedMetrics) {
          lines.push(
            metrics[metric] +
              " " +
              before[metric] +
              " → " +
              score[metric] +
              " (" +
              changeText(before[metric], score[metric], metric) +
              ")",
          );
        }
      } else
        lines.push(
          "비교할 이전 성적이 부족합니다. 다음 시험부터 변화 추이를 확인합니다.",
        );
      lines.push(
        score.grade != null && score.grade >= 5
          ? "기본 개념과 필수 문제의 이해를 확인하고, 틀린 이유를 개념·기억·풀이 과정으로 나누어 기록합니다."
          : "오답 재풀이와 시간 배분을 점검하고, 같은 유형을 다시 풀어 개선 여부를 확인합니다.",
      );
    }
    lines.push(
      "\n향후 2주 실천\n① 과목별 오답 원인 세 가지를 정리합니다.\n② 틀린 문제를 3일 후와 7일 후 다시 풀어봅니다.\n③ 일일 학습계획표의 실행량과 재풀이 결과를 상담 때 확인합니다.\n\n비교 기준\n시험마다 난도와 응시 집단이 달라 점수 변화만으로 실력 변화를 단정하기 어렵습니다. 위 초안은 입력한 성적을 바탕으로 작성했으며, 원장이 실제 풀이와 학습기록을 확인하여 보완합니다.",
    );
    return lines.join("\n");
  }
  function mount(api) {
    const doc = api.document,
      box = doc.getElementById("scoreCoachingPanel");
    let rows = [],
      students = [],
      selected = "",
      editing = null,
      busy = false,
      dirty = false,
      seq = 0;
    const e = (tag, text) => {
      const n = doc.createElement(tag);
      if (text !== undefined) n.textContent = text;
      return n;
    };
    const b = (label, fn) => {
      const n = e("button", label);
      n.type = "button";
      n.className = "secondary";
      n.addEventListener("click", fn);
      return n;
    };
    const field = (parent, label, type, value = "", required = false) => {
      const l = e("label", label),
        n = e(type === "textarea" ? "textarea" : "input");
      if (type !== "textarea") n.type = type;
      n.value = value;
      n.required = required;
      l.append(n);
      parent.append(l);
      return n;
    };
    const who = () => api.profile();
    async function rpc(name, args) {
      const c = await api.client(),
        r = await c.rpc(name, args);
      if (r.error) throw r.error;
      return r.data;
    }
    function reset() {
      seq++;
      rows = [];
      students = [];
      selected = "";
      editing = null;
      busy = false;
      dirty = false;
      box.replaceChildren();
      box.hidden = true;
    }
    async function leave() {
      if (!dirty) return true;
      const accepted = await api.confirm(
        "저장하지 않은 성적·코칭 초안이 있습니다. 이동하시겠습니까?",
      );
      if (accepted) dirty = false;
      return accepted;
    }
    async function open() {
      const actor = who(),
        req = ++seq;
      box.replaceChildren(e("p", "성적·코칭 확인 중…"));
      try {
        const result = await rpc("cheongla_score_coaching_list");
        if (actor !== who() || req !== seq) return;
        rows = result.items || [];
        students = result.students || [];
        if (!students.some((s) => s.id === selected))
          selected = students[0]?.id || "";
        dirty = false;
        render();
      } catch (err) {
        if (req === seq)
          box.replaceChildren(
            e("p", api.readable(err)),
            b("다시 불러오기", open),
          );
      }
    }
    function render() {
      box.replaceChildren(e("h2", "성적 변화 · 학습코칭"));
      const select = e("select");
      select.setAttribute(
        "aria-label",
        api.principal() ? "학생 선택" : "성적·코칭 대상",
      );
      for (const s of students) {
        const op = e("option", s.name);
        op.value = s.id;
        select.append(op);
      }
      select.value = selected;
      select.addEventListener("change", async () => {
        if (!(await leave())) {
          select.value = selected;
          return;
        }
        selected = select.value;
        editing = null;
        dirty = false;
        render();
      });
      box.append(
        select,
        b("새로고침", async () => {
          if (await leave()) await open();
        }),
      );
      if (!selected) {
        box.append(
          e("p", "연결된 승인 학생이 없습니다. 자녀 연결을 확인해 주세요."),
        );
        return;
      }
      const own = rows
        .filter((r) => r.student_id === selected && !r.archived_at)
        .sort(
          (a, b) =>
            b.exam_on.localeCompare(a.exam_on) || b.id.localeCompare(a.id),
        );
      const trend = e("table");
      trend.className = "lr-card";
      trend.style.cssText =
        "width:100%;table-layout:fixed;white-space:pre-wrap;border-spacing:10px";
      const head = e("tr");
      for (const title of ["시험일 · 시험명", "과목별 성적"])
        head.append(e("th", title));
      trend.append(head);
      for (const r of own) {
        const line = e("tr");
        line.append(
          e("td", r.exam_on + " · " + examKinds[examKind(r)] + " · " + r.title),
          e(
            "td",
            r.scores
              .map(
                (s) =>
                  s.subject +
                  " " +
                  Object.entries(metrics)
                    .filter(([k]) => s[k] != null)
                    .map(([k, label]) => label + " " + s[k])
                    .join(" / "),
              )
              .join("\n"),
          ),
        );
        trend.append(line);
      }
      box.append(trend);
      comparisonPanel(own);
      if (api.principal()) {
        box.append(
          b("＋ 새 성적표 등록", async () => {
            if (!(await leave())) return;
            editing = null;
            dirty = false;
            render();
          }),
        );
        editor(own);
      }
      for (const r of own) {
        const card = e("details");
        card.className = "lr-card";
        card.dataset.scoreId = r.id;
        card.append(
          e(
            "summary",
            r.exam_on +
              " · " +
              r.title +
              (api.principal()
                ? r.published_snapshot
                  ? " · 공유본 있음"
                  : " · 원장 초안"
                : ""),
          ),
        );
        const body = e("p", r.report || "코칭 작성 전");
        body.style.whiteSpace = "pre-wrap";
        card.append(
          body,
          b("인쇄 / PDF 저장", () => print(r)),
        );
        if (api.principal()) {
          card.append(
            b("수정", async () => {
              if (!(await leave())) return;
              editing = r;
              dirty = false;
              render();
            }),
            b("학생·학부모에게 공유", () => publish(r)),
            b("휴지통으로", () => archive(r, "archive")),
          );
          if (r.published_snapshot)
            card.append(b("공유 취소", () => archive(r, "unpublish")));
        }
        box.append(card);
      }
      if (api.principal()) {
        const trash = e("details");
        trash.append(e("summary", "성적·코칭 휴지통"));
        const items = rows.filter(
          (r) => r.archived_at && r.student_id === selected,
        );
        trash.append(
          b("이 학생 휴지통 비우기", async () => {
            if (
              busy ||
              !(await api.confirm(
                "이 학생의 휴지통 " + items.length + "건을 영구삭제할까요?",
              ))
            )
              return;
            let done = 0;
            try {
              busy = true;
              for (const r of items) {
                await rpc("cheongla_score_coaching_action", {
                  target_report: r.id,
                  action: "purge",
                  expected_revision: r.revision,
                });
                done++;
              }
              await open();
            } catch (err) {
              box.append(e("p", done + "건 처리 완료 · " + api.readable(err)));
            } finally {
              busy = false;
            }
          }),
        );
        for (const r of items) {
          const n = e("div");
          n.append(
            e("p", r.exam_on + " · " + r.title),
            b("복구", () => archive(r, "restore")),
            b("영구삭제", () => archive(r, "purge")),
          );
          trash.append(n);
        }
        box.append(trash);
      }
    }
    function renderComparison(parent, comparison, printDocument = doc) {
      const node = (tag, text) => {
        const element = printDocument.createElement(tag);
        if (text !== undefined) element.textContent = text;
        return element;
      };
      parent.append(node("h3", "전월·당월 모의고사 성적 비교"));
      const name =
        students.find((student) => student.id === comparison.current.student_id)
          ?.name || "";
      parent.append(
        node(
          "p",
          name +
            " · 당월 " +
            comparison.current.exam_on +
            " " +
            comparison.current.title,
        ),
      );
      parent.append(
        node(
          "p",
          comparison.previous
            ? "전월 " +
                comparison.previous.exam_on +
                " " +
                comparison.previous.title
            : comparison.month + " 모의고사 자료가 없습니다.",
        ),
      );
      const table = node("table"),
        head = node("tr");
      table.style.cssText =
        "width:100%;border-collapse:collapse;white-space:pre-wrap";
      for (const label of ["과목", "지표", "전월", "당월", "변화"])
        head.append(node("th", label));
      table.append(head);
      for (const row of comparison.rows) {
        for (const value of row.metrics) {
          const line = node("tr");
          for (const text of [
            row.subject,
            metrics[value.metric],
            value.before ?? "—",
            value.after ?? "—",
            value.change,
          ]) {
            const cell = node("td", String(text));
            cell.style.cssText =
              "padding:8px;border:1px solid #cbd5d3;overflow-wrap:anywhere";
            line.append(cell);
          }
          table.append(line);
        }
      }
      parent.append(
        table,
        node(
          "p",
          "같은 과목·선택과목의 수치를 비교합니다. 시험의 난도와 응시 집단 차이를 함께 살펴주세요. 등급은 숫자가 낮아질수록 개선입니다.",
        ),
      );
    }
    function comparisonPanel(records) {
      const mocks = records.filter((record) => examKind(record) === "mock");
      if (!mocks.length) return;
      const section = e("section");
      section.className = "lr-card";
      section.dataset.monthlyComparison = "";
      const month = field(
        section,
        "비교할 당월",
        "month",
        mocks[0].exam_on.slice(0, 7),
        true,
      );
      const currentLabel = e("label", "당월 모의고사"),
        current = e("select"),
        previousLabel = e("label", "전월 모의고사"),
        previous = e("select"),
        result = e("div");
      currentLabel.append(current);
      previousLabel.append(previous);
      section.append(currentLabel, previousLabel, result);
      function show() {
        const comparison = monthlyComparison(
          records,
          current.value,
          previous.value,
        );
        result.replaceChildren();
        if (!comparison) {
          result.append(e("p", "선택한 달의 모의고사 자료가 없습니다."));
          return;
        }
        renderComparison(result, comparison);
        result.append(
          b("비교표 인쇄 / PDF 저장", () =>
            root.CheonglaPrint.open(
              "전월·당월 모의고사 성적 비교",
              (body, printDocument) =>
                renderComparison(body, comparison, printDocument),
              "청라성적비교_" + month.value,
            ),
          ),
        );
      }
      function choosePrevious() {
        const comparison = monthlyComparison(records, current.value);
        previous.replaceChildren();
        for (const record of comparison?.candidates || []) {
          const option = e("option", record.exam_on + " · " + record.title);
          option.value = record.id;
          previous.append(option);
        }
        previousLabel.hidden = !previous.options.length;
        show();
      }
      function chooseMonth() {
        current.replaceChildren();
        for (const record of mocks.filter(
          (record) => record.exam_on.slice(0, 7) === month.value,
        )) {
          const option = e("option", record.exam_on + " · " + record.title);
          option.value = record.id;
          current.append(option);
        }
        choosePrevious();
      }
      month.addEventListener("change", chooseMonth);
      current.addEventListener("change", choosePrevious);
      previous.addEventListener("change", show);
      chooseMonth();
      box.append(section);
    }
    function editor(history) {
      const form = e("form");
      form.className = "lr-card";
      form.addEventListener("submit", (ev) => ev.preventDefault());
      form.addEventListener("input", () => (dirty = true));
      form.addEventListener("change", () => (dirty = true));
      form.append(e("h3", editing ? "성적·코칭 수정" : "새 성적표 등록"));
      const date = field(
          form,
          "시험일",
          "date",
          editing?.exam_on ||
            new Intl.DateTimeFormat("en-CA", {
              timeZone: "Asia/Seoul",
              year: "numeric",
              month: "2-digit",
              day: "2-digit",
            }).format(new Date()),
          true,
        ),
        title = field(form, "시험명", "text", editing?.title || "", true);
      title.maxLength = 150;
      title.setAttribute("list","cheonglaExamNames");
      const typeLabel = e("label", "시험 구분"),
        type = e("select");
      for (const [value, label] of Object.entries(examKinds)) {
        const option = e("option", label);
        option.value = value;
        type.append(option);
      }
      type.value = examKind(editing);
      typeLabel.append(type);
      form.append(typeLabel);
      const typeHelp = e("p");
      form.append(typeHelp);

      const file = field(form, "성적표 사진 선택 · 카메라 촬영", "file");
      file.accept = "image/jpeg,image/png,image/webp";
      const ocrEnabled = root.CheonglaFeatures?.scoreOcr === true;
      file.disabled = !ocrEnabled;
      form.append(
        e(
          "p",
          ocrEnabled
            ? "이름·수험번호 등 개인정보는 가리고 촬영해 주세요. 사진은 점수를 읽는 데 사용하며, 저장할 과목별 점수는 원본과 대조해 확인해 주세요."
            : "사진 자동 읽기는 연결 준비 중입니다. 과목별 점수를 직접 입력해 저장·비교·공유할 수 있습니다.",
        ),
      );
      const scores = e("div");
      let readers = [];
      function fill(data) {
        scores.replaceChildren();
        readers = [];
        for (const s of data) {
          const line = e("div");
          line.className = "lr-card";
          const subject = field(
            line,
            "과목 · 선택과목명",
            "text",
            s.subject,
            true,
          );
          subject.maxLength = 60;
          const inputs = {};
          for (const [key, label] of Object.entries(metrics)) {
            const n = field(line, label, "number", s[key] ?? "");
            n.min = key === "grade" ? 1 : 0;
            n.max = key === "grade" ? 9 : key === "standard" ? 200 : 100;
            n.step = key === "percentile" ? "0.01" : "1";
            n.disabled = key === "raw" && type.value === "csat";
            if (n.disabled) n.value = "";
            inputs[key] = n;
          }
          readers.push({ subject, inputs });
          line.append(
            b("이 과목 제외", () => {
              line.remove();
              readers = readers.filter((x) => x.subject !== subject);
              dirty = true;
            }),
          );
          scores.append(line);
        }
      }
      const read = () =>
        readers.map((x) => {
          const s = { subject: x.subject.value.trim() };
          for (const [key, n] of Object.entries(x.inputs))
            s[key] = n.disabled || n.value === "" ? null : Number(n.value);
          return s;
        });
      fill(
        editing?.scores ||
          ["국어", "수학", "영어", "탐구1", "탐구2", "한국사"].map(
            (subject) => ({ subject }),
          ),
      );
      function explainType() {
        typeHelp.textContent =
          type.value === "csat"
            ? "수능 성적표는 원점수가 공개되지 않아 표준점수·백분위·등급을 기록합니다."
            : "학원 모의고사는 원점수·표준점수·백분위·등급을 기록하고 전월과 비교합니다.";
      }
      explainType();
      type.addEventListener("change", async () => {
        if (
          type.value === "csat" &&
          readers.some((reader) => reader.inputs.raw.value !== "")
        ) {
          if (
            !(await api.confirm(
              "수능으로 바꾸면 입력한 원점수를 비웁니다. 변경할까요?",
            ))
          ) {
            type.value = "mock";
            return;
          }
        }
        fill(read());
        explainType();
        dirty = true;
      });
      const report = field(
        form,
        "학습 방향 · 원장 코칭",
        "textarea",
        editing?.report || "",
      );
      report.maxLength = 20000;
      const status = e("p");
      status.setAttribute("role", "status");
      form.append(
        b(ocrEnabled ? "사진에서 점수 읽기" : "사진 자동 읽기 · 준비 중", async () => {
          if (!ocrEnabled) {
            status.textContent = "사진 자동 읽기는 준비 중입니다. 점수를 직접 입력해 주세요.";
            return;
          }
          if (busy || !file.files?.[0]) {
            status.textContent = "성적표 사진을 먼저 선택해 주세요.";
            return;
          }
          if (
            !(await api.confirm(
              "선택한 성적표 사진을 OpenAI API로 보내 과목별 점수를 읽을까요? 이름·수험번호 등 개인정보를 가렸는지 확인해 주세요.",
            ))
          )
            return;
          const actor = who(),
            extractionType = type.value;
          busy = true;
          status.textContent = "성적표 확인 중…";
          try {
            const image = await compress(file.files[0]),
              c = await api.client();
            if (actor !== who()) return;
            const r = await c.functions.invoke("cheongla-score-extract", {
              body: { image, exam_type: extractionType },
            });
            if (r.error)
              throw Error(
                "성적표 인식 서버 연결을 확인해 주세요. 점수를 직접 입력해 저장할 수도 있습니다.",
              );
            if (actor !== who()) return;
            if (!Array.isArray(r.data?.scores) || !r.data.scores.length)
              throw Error(
                "읽을 수 있는 점수가 없습니다. 선명한 사진으로 다시 시도해 주세요.",
              );
            if (extractionType !== type.value) {
              status.textContent =
                "시험 구분이 변경되었습니다. 사진 읽기를 다시 실행해 주세요.";
              return;
            }
            fill(r.data.scores);
            dirty = true;
            status.textContent =
              "인식 초안입니다. 학생·시험·과목과 모든 점수를 확인해 주세요.";
          } catch (err) {
            if (actor === who()) status.textContent = api.readable(err);
          } finally {
            busy = false;
          }
        }),
        scores,
        b("과목 추가", () => {
          if (readers.length < 10) {
            fill([...read(), { subject: "" }]);
            dirty = true;
          }
        }),
        b("성적 기반 코칭 초안 만들기", () => {
          if (!form.reportValidity()) return;
          report.value = analyze(
            read(),
            history.filter(
              (r) =>
                r.id !== editing?.id &&
                examKind(r) === type.value &&
                (type.value === "mock"
                  ? r.exam_on.slice(0, 7) ===
                    previousMonth(date.value.slice(0, 7))
                  : r.exam_on < date.value),
            ),
          );
          dirty = true;
        }),
        b("성적 · 코칭 초안 저장", async () => {
          if (busy || !form.reportValidity()) return;
          const values = read();
          if (
            !values.length ||
            values.some((s) => !Object.keys(metrics).some((k) => s[k] != null))
          ) {
            status.textContent =
              "각 과목에 점수를 하나 이상 입력하거나 점수가 없는 과목을 제외해 주세요.";
            return;
          }
          const actor = who();
          busy = true;
          try {
            const r = await rpc("cheongla_save_score_coaching", {
              target_report: editing?.id || null,
              target_student: selected,
              exam_date: date.value,
              exam_title: title.value.trim(),
              subject_scores: values,
              coaching_text: report.value.trim(),
              expected_revision: editing?.revision || null,
              exam_type: type.value,
            });
            if (actor !== who()) return;
            dirty = false;
            editing = r;
            await open();
          } catch (err) {
            if (actor === who()) status.textContent = api.readable(err);
          } finally {
            busy = false;
          }
        }),
        status,
      );
      box.append(form);
    }
    async function archive(r, action) {
      if (
        busy ||
        !(await leave()) ||
        !(await api.confirm(
          action === "purge"
            ? "영구삭제하면 복구할 수 없습니다. 진행할까요?"
            : action === "unpublish"
              ? "학생·학부모에게 공유한 코칭을 회수할까요?"
              : "선택한 문서를 " +
                (action === "restore" ? "복구" : "휴지통으로 이동") +
                "할까요?",
        ))
      )
        return;
      const actor = who();
      busy = true;
      try {
        await rpc("cheongla_score_coaching_action", {
          target_report: r.id,
          action,
          expected_revision: r.revision,
        });
        if (actor === who()) {
          editing = null;
          dirty = false;
          await open();
        }
      } catch (err) {
        if (actor === who()) box.append(e("p", api.readable(err)));
      } finally {
        busy = false;
      }
    }
    async function publish(r) {
      if (
        busy ||
        !(await leave()) ||
        !(await api.confirm(
          "저장된 성적과 코칭을 이 학생 및 연결된 학부모에게 공유하고 알림을 보낼까요?",
        ))
      )
        return;
      const actor = who();
      busy = true;
      try {
        await rpc("cheongla_score_coaching_action", {
          target_report: r.id,
          action: "publish",
          expected_revision: r.revision,
        });
        if (actor === who()) {
          dirty = false;
          await open();
        }
      } catch (err) {
        if (actor === who()) box.append(e("p", api.readable(err)));
      } finally {
        busy = false;
      }
    }
    function print(r) {
      root.CheonglaPrint.open(
        examKinds[examKind(r)] + " · 학습코칭 · " + r.exam_on,
        (body) => {
          body.append(
            e(
              "h2",
              (students.find((s) => s.id === r.student_id)?.name || "") +
                " · " +
                r.title,
            ),
          );
          for (const s of r.scores)
            body.append(
              e(
                "p",
                s.subject +
                  " · " +
                  Object.entries(metrics)
                    .filter(([k]) => s[k] != null)
                    .map(([k, v]) => v + " " + s[k])
                    .join(" / "),
              ),
            );
          body.append(e("p", r.report));
        },
        "청라학습코칭_" + r.exam_on,
      );
    }
    root.addEventListener?.("beforeunload", (event) => {
      if (dirty) {
        event.preventDefault();
        event.returnValue = "";
      }
    });
    return {
      open,
      reset,
      leave,
      get dirty() {
        return dirty;
      },
    };
  }
  async function compress(file) {
    if (file.size > 20 * 1024 * 1024)
      throw Error("사진은 20MB 이하로 선택해 주세요.");
    const data = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(Error("사진을 읽을 수 없습니다."));
      reader.readAsDataURL(file);
    });
    const img = new Image();
    await new Promise((resolve, reject) => {
      img.onload = resolve;
      img.onerror = () => reject(Error("지원하는 사진 형식을 선택해 주세요."));
      img.src = data;
    });
    const scale = Math.min(1, 2200 / Math.max(img.width, img.height)),
      canvas = document.createElement("canvas");
    canvas.width = Math.round(img.width * scale);
    canvas.height = Math.round(img.height * scale);
    canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", 0.88);
  }
  root.CheonglaScoreCoaching = {
    mount,
    analyze,
    monthlyComparison,
    previousMonth,
    changeText,
  };
})(globalThis);
