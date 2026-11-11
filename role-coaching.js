/* Role-specific entry points share the existing home and document editors. */
(function (root) {
  "use strict";
  const allowedRoles = [
    "owner",
    "english_director",
    "math_director",
    "student",
    "parent",
  ];
  function install() {
    if (!root.CheonglaStaffJournalUI) return;
    const doc = root.document,
      staff = () =>
        currentProfile?.approval_status === "approved" &&
        currentProfile.membership_state === "active" &&
        ["owner", "english_director", "math_director", "manager"].includes(
          currentProfile.role,
        );
    const principal = () =>
      isPrincipal() && currentProfile?.membership_state === "active";
    const fees = ["tuitionPanel", "examFeePanel", "mealFeePanel"];
    const disabled = new Set([
      "englishPanel",
      "externalPanel",
      "billingPanel",
      "mealPanel",
      "examPanel",
      "patrolPanel",
    ]);
    const previousAllowed = allowedAccountSection;
    root.allowedAccountSection = function (id) {
      if (disabled.has(id)) return principal();
      if (fees.includes(id)) return staff() || (currentProfile?.approval_status === 'approved' && currentProfile.membership_state === 'active' && currentProfile.role === 'parent');
      if (id === "mbtiStudyPanel" || id === "contentTrashPanel")
        return principal();
      if (id === "scoreCoachingPanel")
        return (
          currentProfile?.approval_status === "approved" &&
          currentProfile.membership_state === "active" &&
          allowedRoles.includes(currentProfile.role)
        );
      return previousAllowed(id);
    };
    const oldGroup = accountSectionGroup;
    root.accountSectionGroup = (id) =>
      fees.includes(id) || id === "staffJournalPanel"
        ? "청라 생활"
        : id === "scoreCoachingPanel"
          ? "학습·상담"
          : oldGroup(id);
    function entry(key, label) {
      const b = doc.createElement("button");
      b.type = "button";
      b.textContent = label;
      b.addEventListener("click", () => void openSiteDestination(key));
      return b;
    }
    const previousMenu = configureDeskMenu;
    root.configureDeskMenu = function () {
      previousMenu();
      const menu = doc.getElementById("deskMenuItems");
      menu.replaceChildren();
      if (staff())
        menu.append(
          entry("account_staffJournalPanel", "청라 근무일지"),
          entry("account_registrationPanel", "상담 · 신규 등록카드"),
        );
      if (currentProfile?.approval_status === "approved")
        menu.append(
          entry(
            "account_learningPanel",
            staff() ? "일일 학습계획표 확인" : "일일 학습계획표",
          ),
          entry("my_contact", "내 전화번호 등록 · 수정"),
        );
      if (staff()) {
        const group = doc.createElement("details"),
          summary = doc.createElement("summary");
        summary.textContent = "청라 비용안내";
        group.append(summary);
        for (const [id, label] of [
          ["tuitionPanel", "학원비 안내"],
          ["examFeePanel", "모의고사비 안내"],
          ["mealFeePanel", "도시락비 안내"],
        ])
          group.append(entry("account_" + id, label));
        doc.getElementById("feeNoticeMenuItems").replaceChildren(...Array.from(group.querySelectorAll("button")));
      }
      if (principal())
        menu.append(entry("account_contentTrashPanel", "휴지통 관리"));
      for (const id of ["feeNoticeMenu", "financeMenu"]) {
        const n = doc.getElementById(id);
        if (n) n.hidden = id === "financeMenu" || !staff();
      }
      const ask = doc.getElementById("askMenu"),
        items = doc.getElementById("askMenuItems");
      if (ask && items) {
        ask.hidden = false;
        items.replaceChildren();
        if (canManageAccountRecovery())
          items.append(
            entry("account_recoveryManagerPanel", "아이디·비밀번호 복구"),
          );
        items.append(
          entry("my_contact", "내 전화번호 등록 · 수정"),
          entry("question_board", "문의 확인 · 답변"),
        );
      }
      for (const menu of doc.querySelectorAll("#siteNavigation .site-menu")) {
        const label = menu.querySelector("summary")?.textContent.trim() || "";
        if (label === "청라영어") menu.hidden = !principal();
        if (label.startsWith("나의 MBTI")) menu.hidden = !principal();
      }
      root.CheonglaScoreCoachingUI?.reset();
      root.CheonglaJournalMuteUI?.refresh();
    };
    const previousOpen = openSiteDestination;
    const blockedRoutes = new Set([
      "english_study",
      "english_book",
      "english_practice",
      "english_test",
      "meal_forms",
      "exam_apply",
      "desk_roster",
      "desk_exams",
      "desk_notices",
      "billing_dashboard",
    ]);
    root.openSiteDestination = async function (key, context) {
      if (
        (blockedRoutes.has(key) && !principal()) ||
        (key.startsWith("account_") && !allowedAccountSection(key.slice(8))) ||
        (key.startsWith("mbti_") && !principal()) ||
        (["desk_tuition", "desk_fees"].includes(key) &&
          !staff())
      ) {
        showSiteHome();
        $("siteStatus").textContent =
          "현재 계정에서 제공하는 메뉴를 선택해 주세요.";
        return;
      }
      if (
        root.CheonglaScoreCoachingUI?.dirty &&
        !(await root.CheonglaScoreCoachingUI.leave())
      )
        return;
      const result = await previousOpen(key, context);
      if (key === "account_scoreCoachingPanel")
        await root.CheonglaScoreCoachingUI.open();
      return result;
    };
    const oldReset = clearAccount;
    root.clearAccount = function () {
      root.CheonglaScoreCoachingUI?.reset();
      root.CheonglaJournalMuteUI?.reset();
      oldReset();
    };
    const score = doc.createElement("section");
    score.id = "scoreCoachingPanel";
    score.hidden = true;
    doc.getElementById("accountPanel").append(score);
    accountSectionLabels.scoreCoachingPanel = "성적 변화 · 학습코칭";
    root.CheonglaScoreCoachingUI = root.CheonglaScoreCoaching.mount({
      document: doc,
      profile: () => currentProfile,
      principal,
      client: getClient,
      confirm: appConfirm,
      readable,
    });
    root.CheonglaJournalMuteUI = root.CheonglaJournalMute.mount({
      document: doc,
      profile: () => currentProfile,
      allowed: () => currentProfile?.approval_status === "approved" && currentProfile.membership_state === "active",
      client: getClient,
      readable,
    });
    doc.addEventListener(
      "click",
      (event) => {
        const target = event.target.closest?.(
          "#siteNavigation button,#academyHome,#siteGoHome,#siteBack,#backToHome,#openMemberArea,#openNotificationInbox",
        );
        if (!target || !root.CheonglaScoreCoachingUI?.dirty) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        void root.CheonglaScoreCoachingUI.leave().then((ok) => {
          if (ok) target.click();
        });
      },
      true,
    );
    const journalHome = doc.getElementById("journalHomeCard");
    if (journalHome) {
      const preferences = doc.createElement("button");
      preferences.type = "button";
      preferences.className = "text-button";
      preferences.textContent = "청라앱 전체 알림 잠시 꺼두기 · 설정";
      preferences.addEventListener("click", async () => {
        await openSiteDestination("notifications");
        doc
          .getElementById("journalPushPreferences")
          ?.scrollIntoView({ block: "start" });
      });
      journalHome.append(preferences);
    }
    configureDeskMenu();
    configureAccountSections();
  }
  root.CheonglaRoleCoaching = { install };
  install();
})(globalThis);
