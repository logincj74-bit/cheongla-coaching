(function (root) {
  'use strict';

  const table = 'cheongla_winter_promotions';
  const guide = 'https://cheongla-winter-2027.logincj.chatgpt.site/';
  const formatDate = new Intl.DateTimeFormat('ko-KR', {
    month: 'long', day: 'numeric', weekday: 'short', timeZone: 'Asia/Seoul'
  });

  function mount({ document, profile, principal, client, confirm, readable }) {
    const card = document.getElementById('winterPromotion');
    const admin = document.getElementById('winterPromotionAdmin');
    const home = document.getElementById('homePanel');
    const status = admin.querySelector('[role="status"]');
    const editor = admin.querySelector('form');
    const list = admin.querySelector('[data-promotions]');
    const trash = admin.querySelector('[data-trash]');
    const fields = editor.elements;
    let actor, editing, rows = [], busy = false, ready = false;
    let publicRequest = 0, adminRequest = 0, expiryTimer;

    function element(tag, value) {
      const node = document.createElement(tag);
      if (value) node.textContent = value;
      return node;
    }

    function button(label, click, style = 'secondary') {
      const node = element('button', label);
      node.type = 'button';
      node.className = style;
      node.disabled = busy || !ready;
      node.addEventListener('click', click);
      return node;
    }

    let openingWinter = false;
    async function openWinter(event, link) {
      const actor = profile();
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
          actor?.approval_status !== 'approved' || actor.membership_state !== 'active' ||
          !['student', 'parent'].includes(actor.role)) return;
      if (openingWinter) { event.preventDefault(); return; }
      const target = 'cheonglaWinter' + Date.now();
      const popup = root.open('about:blank', target);
      if (!popup) return;
      popup.opener = null;
      event.preventDefault();
      openingWinter = true;
      link.setAttribute('aria-busy', 'true');
      try {
        const c = await client();
        if (actor !== profile() || popup.closed) { if (!popup.closed) popup.close(); return; }
        const result = await c.rpc('cheongla_issue_winter_signin');
        if (actor !== profile() || popup.closed) { if (!popup.closed) popup.close(); return; }
        if (result.error || !/^[0-9a-f]{64}$/.test(result.data)) throw Error('Winter sign-in unavailable');
        const form = popup.document.createElement('form');
        form.method = 'post';
        form.target = '_self';
        form.action = new URL('api/student/cheongla', guide).href;
        form.hidden = true;
        const code = popup.document.createElement('input');
        code.type = 'hidden';
        code.name = 'code';
        code.value = result.data;
        form.append(code);
        popup.document.body.append(form);
        form.submit();
        root.setTimeout(() => form.remove(), 1000);
      } catch {
        if (actor === profile() && !popup.closed) popup.location.replace(guide);
        else if (!popup.closed) popup.close();
      } finally {
        openingWinter = false;
        link.removeAttribute('aria-busy');
      }
    }

    function showCard(row) {
      root.clearTimeout(expiryTimer);
      card.replaceChildren();
      card.hidden = true;
      if (!row) return;
      const remaining = row.ends_at == null ? Infinity : Date.parse(row.ends_at) - Date.now();
      if (!(remaining > 0) || !(row.first_open || row.second_open)) return;
      const heading = element('h2', row.title);
      heading.id = 'winterPromotionTitle';
      const dates = element('div');
      dates.className = 'winter-promotion-dates';
      for (const [open, date, number] of [[row.first_open, row.first_date, 1], [row.second_open, row.second_date, 2]]) {
        if (!open) continue;
        const slot = element('div');
        const bothOpen = row.first_open && row.second_open;
        const label = number + (bothOpen ? '차 개강' : '차 모집 중');
        const displayDate = formatDate.format(new Date(date + 'T12:00:00+09:00'));
        const when = element('time', displayDate + (bothOpen ? '' : ' 개강'));
        when.dateTime = date;
        slot.append(element('span', label), when);
        dates.append(slot);
      }
      const viewer = profile();
      const manager = viewer?.role === 'manager' && viewer.approval_status === 'approved' && viewer.membership_state === 'active';
      const link = element('a', (principal() || manager ? '청라윈터스쿨 관리' : row.button_text) + ' →');
      link.href = guide;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.addEventListener('click', event => void openWinter(event, link));
      card.append(heading);
      if (row.message) card.append(element('p', row.message));
      card.append(dates, link);
      card.hidden = home.hidden;
      if (Number.isFinite(remaining)) expiryTimer = root.setTimeout(() => showCard(row), Math.min(remaining, 2147483647));
    }

    async function refreshCard() {
      const request = ++publicRequest;
      try {
        const c = await client();
        if (request !== publicRequest) return;
        const result = await c.from(table).select('title,message,button_text,first_open,second_open,first_date,second_date,ends_at')
          .eq('enabled', true).is('deleted_at', null).or('first_open.eq.true,second_open.eq.true')
          .or('ends_at.is.null,ends_at.gt.' + new Date().toISOString()).maybeSingle();
        if (request !== publicRequest) return;
        if (result.error) throw result.error;
        showCard(result.data);
      } catch {
        if (request === publicRequest) showCard(null);
      }
    }

    function showEditor(row = null) {
      editing = row;
      editor.reset();
      if (row) {
        for (const key of ['title', 'message', 'button_text', 'first_date', 'second_date']) fields[key].value = row[key];
        for (const key of ['enabled', 'first_open', 'second_open']) fields[key].checked = row[key];
      }
      editor.querySelector('legend').textContent = row ? '모집 카드 수정' : '새 모집 카드';
      editor.hidden = false;
      fields.title.focus();
    }

    function renderAdmin() {
      list.replaceChildren();
      trash.replaceChildren();
      const removed = rows.filter(row => row.deleted_at);
      if (removed.length) {
        trash.append(button('휴지통 비우기', () => change('empty'), 'danger'));
      } else {
        trash.append(element('p', '휴지통이 비어 있습니다.'));
      }
      const active = rows.filter(row => !row.deleted_at);
      if (!active.length) list.append(element('p', '저장된 모집 카드가 없습니다.'));
      for (const row of rows) {
        const item = element('article');
        item.className = 'qa-item';
        item.append(element('strong', row.title));
        if (row.deleted_at) {
          item.append(button('복원', () => change('restore', row)),
            button('영구 삭제', () => change('purge', row), 'danger'));
          trash.append(item);
        } else {
          const open = row.enabled && (row.ends_at == null || Date.parse(row.ends_at) > Date.now()) && (row.first_open || row.second_open);
          item.append(element('p', open ? '홈에 게시 중' : '숨김'),
            button('수정', () => showEditor(row)));
          if (row.enabled) {
            item.append(button('홈에서 숨기기', () => change('hide', row)));
          } else {
            const publish = button('홈에 다시 보이기', () => change('publish', row));
            if (!row.first_open && !row.second_open) {
              publish.disabled = true;
              item.append(element('p', '다시 게시하려면 수정 화면에서 모집 차수를 한 개 이상 열어 주세요.'));
            }
            item.append(publish);
          }
          item.append(button('삭제 · 휴지통으로', () => change('trash', row), 'danger'));
          list.append(item);
        }
      }
      admin.querySelector('[data-add]').disabled = busy || !ready;
      editor.querySelector('fieldset').disabled = busy || !ready;
    }

    async function loadAdmin(success = '') {
      if (!principal()) return;
      const owner = profile(), request = ++adminRequest;
      ready = false;
      renderAdmin();
      status.textContent = '모집 카드 확인 중…';
      try {
        const c = await client();
        if (owner !== profile() || request !== adminRequest || !principal()) return;
        const result = await c.from(table).select('*').order('created_at', { ascending: false });
        if (owner !== profile() || request !== adminRequest || !principal()) return;
        if (result.error) throw result.error;
        rows = result.data;
        ready = true;
        status.textContent = success;
      } catch (error) {
        if (owner !== profile() || request !== adminRequest) return;
        rows = [];
        status.textContent = readable(error);
      }
      renderAdmin();
    }

    const prompts = {
      trash: ['휴지통으로 이동', '이 카드를 삭제하고 휴지통으로 이동할까요?'],
      purge: ['영구 삭제', '이 카드를 영구 삭제할까요? 복원할 수 없습니다.'],
      empty: ['휴지통 비우기', '윈터스쿨 카드 휴지통을 모두 비울까요? 복원할 수 없습니다.']
    };
    const messages = {
      save: '카드를 저장했습니다.', hide: '홈에서 카드를 숨겼습니다.', publish: '홈에 카드를 다시 게시했습니다.',
      trash: '카드를 휴지통으로 이동했습니다.', restore: '숨김 상태로 복원했습니다. 다시 게시하려면 홈에 다시 보이기를 누르세요.',
      purge: '카드를 영구 삭제했습니다.', empty: '카드 휴지통을 비웠습니다.'
    };

    async function change(action, row, payload) {
      if (busy || !ready || !principal()) return;
      const owner = profile();
      busy = true;
      renderAdmin();
      try {
        const prompt = prompts[action];
        if (prompt && !await confirm(prompt[1], prompt[0])) return;
        if (owner !== profile() || !principal()) return;
        const c = await client();
        if (owner !== profile() || !principal()) return;
        const data = c.from(table);
        let operation;
        if (action === 'empty') {
          operation = data.delete().not('deleted_at', 'is', null);
        } else if (action === 'save' && !row) {
          operation = data.insert(payload).select('id').single();
        } else {
          const values = {
            save: payload, hide: { enabled: false }, publish: { enabled: true, ends_at: null },
            trash: { deleted_at: new Date().toISOString(), enabled: false },
            restore: { deleted_at: null, enabled: false }
          };
          operation = (action === 'purge' ? data.delete() : data.update(values[action]))
            .eq('id', row.id).eq('revision', row.revision).select('id').maybeSingle();
        }
        const result = await operation;
        if (owner !== profile() || !principal()) return;
        if (result.error) throw result.error;
        if (action !== 'empty' && !result.data) {
          await loadAdmin('다른 화면에서 이 카드가 변경되었습니다. 목록에서 다시 열어 주세요.');
          editor.hidden = true;
          editing = null;
          return;
        }
        if (action === 'save' || (row && editing?.id === row.id)) {
          editor.hidden = true;
          editing = null;
        }
        void refreshCard();
        await loadAdmin(messages[action]);
      } catch (error) {
        if (owner !== profile() || !principal()) return;
        status.textContent = error.code === '23505'
          ? '이미 게시가 설정된 카드가 있습니다. 기존 카드를 숨긴 뒤 다시 시도해 주세요.'
          : readable(error);
      } finally {
        if (owner === profile()) {
          busy = false;
          renderAdmin();
        }
      }
    }

    editor.addEventListener('submit', event => {
      event.preventDefault();
      if (!editor.reportValidity()) return;
      const payload = {
        title: fields.title.value.trim(), message: fields.message.value.trim(),
        button_text: fields.button_text.value.trim(),
        first_date: fields.first_date.value, second_date: fields.second_date.value,
        first_open: fields.first_open.checked, second_open: fields.second_open.checked,
        enabled: fields.enabled.checked,
        ends_at: null
      };
      if (!payload.title || !payload.button_text || payload.first_date > payload.second_date) {
        status.textContent = '제목과 버튼 문구를 입력하고 1차·2차 개강일 순서를 확인해 주세요.';
        return;
      }
      void change('save', editing, payload);
    });
    admin.querySelector('[data-add]').addEventListener('click', () => showEditor());
    admin.querySelector('[data-cancel]').addEventListener('click', () => { editor.hidden = true; editing = null; });
    admin.querySelector('[data-refresh]').addEventListener('click', () => { if (!busy) void loadAdmin(); });
    admin.addEventListener('toggle', () => { if (admin.open && !ready && !busy) void loadAdmin(); });

    function refresh() {
      const current = profile();
      const canManage = principal();
      if (actor !== current || admin.hidden !== !canManage) {
        actor = current;
        ++adminRequest;
        ready = false;
        busy = false;
        rows = [];
        editing = null;
        editor.hidden = true;
        editor.reset();
        admin.open = false;
        admin.hidden = !canManage;
        status.textContent = '';
        renderAdmin();
      }
      if (!home.hidden && !document.hidden) void refreshCard();
    }

    new root.MutationObserver(() => {
      card.hidden = home.hidden || !card.childElementCount;
      if (!home.hidden) refresh();
    }).observe(home, { attributes: true, attributeFilter: ['hidden'] });
    document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
    root.setInterval(() => { if (!home.hidden && !document.hidden) void refreshCard(); }, 60000);
    return { refresh };
  }

  root.CheonglaWinterPromotion = { mount };
})(globalThis);
