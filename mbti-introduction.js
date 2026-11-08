globalThis.CheonglaMBTIIntroduction = {
  mount({ document, client, canEdit, confirm, readable }) {
    const section = document.getElementById('mbtiIntroduction');
    const summary = section.querySelector('summary');
    const status = section.querySelector('[role="status"]');
    const content = section.querySelector('article');
    const controls = section.querySelector('fieldset');
    const exports = section.querySelector('[data-mbti-intro-export]');
    const form = controls.querySelector('form');
    const trash = controls.querySelector('details');
    const trashList = trash.querySelector('ul');
    let request = 0;
    let busy = false;
    let rows = [];
    const table = 'cheongla_mbti_introductions';
    const columns = 'id,title,body,archived_at,revision';
    const defaultTitle = '나를 이해하는 공부, 나에게 맞는 학습법';

    function button(label, action) {
      const element = document.createElement('button');
      element.type = 'button';
      element.className = 'secondary';
      element.textContent = label;
      element.addEventListener('click', action);
      return element;
    }

    async function run(action, fallback) {
      if (busy) return;
      const token = ++request;
      busy = true;
      controls.disabled = true;
      status.textContent = '';
      try {
        const db = await client();
        if (token !== request) return;
        await action(db.from(table), () => token === request);
      } catch (error) {
        if (token === request) {
          status.textContent = error?.code === '23505'
            ? '이미 게시된 소개글이 있습니다. 해당 글을 휴지통으로 옮긴 뒤 다시 시도해 주세요.'
            : fallback + ' ' + readable(error);
        }
      } finally {
        if (token === request) {
          busy = false;
          controls.disabled = false;
        }
      }
    }

    function write(change, message, { prompt, remove = false } = {}) {
      if (!canEdit()) return;
      return run(async (source, current) => {
        if (prompt && !(await confirm(prompt, 'MBTI 소개글 관리'))) return;
        if (!current() || !canEdit()) return;
        const result = await change(source).select(columns).maybeSingle();
        if (!current()) return;
        if (result.error) throw result.error;
        if (!result.data) throw new Error('다른 곳에서 소개글이 변경되었습니다. 다시 불러와 주세요.');
        rows = rows.filter(item => item.id !== result.data.id);
        if (!remove) rows.push(result.data);
        render();
        status.textContent = message;
      }, '소개글에 변경 사항을 반영하지 못했습니다.');
    }

    function update(row, values) {
      return source => source.update(values).eq('id', row.id).eq('revision', row.revision);
    }

    function render() {
      const published = rows.find(row => !row.archived_at);
      const editable = canEdit();
      section.hidden = !published && !editable;
      exports.hidden = !published;
      summary.textContent = published?.title || 'MBTI 학습법 소개글 관리';
      content.replaceChildren();
      for (const paragraph of (published?.body || '').split(/\n\s*\n/).filter(Boolean)) {
        const element = document.createElement(/^[1-6]\. /.test(paragraph) ? 'h3' : 'p');
        element.style.whiteSpace = 'pre-line';
        element.style.overflowWrap = 'anywhere';
        element.textContent = paragraph;
        content.append(element);
      }

      controls.hidden = !editable;
      form.hidden = true;
      form.reset();
      const actions = controls.querySelector('[data-mbti-intro-actions]');
      actions.replaceChildren();
      trashList.replaceChildren();
      trash.hidden = true;
      if (!editable) return;

      actions.append(button(published ? '소개글 수정' : '소개글 작성', () => {
        form.elements.title.value = published?.title || '';
        form.elements.body.value = published?.body || '';
        form.hidden = false;
        form.elements.title.focus();
      }));
      if (published) {
        actions.append(button('휴지통으로 이동', () => write(update(published, { archived_at: new Date().toISOString() }),
          '소개글을 휴지통으로 옮겼습니다.', { prompt: '소개글을 휴지통으로 옮기시겠어요?' })));
      }
      actions.append(button('다시 불러오기', load));

      const archived = rows.filter(row => row.archived_at)
        .sort((first, second) => second.archived_at.localeCompare(first.archived_at));
      trash.hidden = !archived.length;
      trash.querySelector('summary').textContent = '소개글 휴지통 (' + archived.length + ')';
      for (const row of archived) {
        const item = document.createElement('li');
        const preview = document.createElement('details');
        const label = document.createElement('summary');
        const body = document.createElement('p');
        label.textContent = row.title + ' · ' + new Date(row.archived_at).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });
        body.textContent = row.body;
        body.style.whiteSpace = 'pre-line';
        body.style.overflowWrap = 'anywhere';
        preview.append(label, body);
        const restore = button('복원', () => write(update(row, { archived_at: null }),
          '소개글을 복원했습니다.'));
        restore.disabled = Boolean(published);
        item.append(preview, restore, button('영구삭제', () => write(
          source => source.delete().eq('id', row.id).eq('revision', row.revision).not('archived_at', 'is', null),
          '소개글을 영구삭제했습니다.', { remove: true, prompt: '이 소개글을 영구삭제하면 복원할 수 없습니다. 삭제하시겠어요?' })));
        trashList.append(item);
      }
      controls.querySelector('[data-mbti-intro-trash-help]').hidden = !published;
    }

    function load() {
      return run(async (source, current) => {
        const { data, error } = await source.select(columns);
        if (!current()) return;
        if (error) throw error;
        rows = data;
        render();
      }, '소개글을 불러오지 못했습니다. 소개글을 닫았다가 다시 열어 주세요.');
    }

    function exportPublished(action) {
      const published = rows.find(row => !row.archived_at);
      if (busy || !published) return;
      try {
        action(published.title);
        status.textContent = '';
      } catch (error) {
        status.textContent = readable(error);
      }
    }

    exports.querySelector('[data-mbti-intro-print]').addEventListener('click', () => exportPublished(title => {
      if (!globalThis.CheonglaPrint?.node) throw new Error('인쇄 기능을 준비 중입니다. 잠시 후 다시 눌러 주세요.');
      globalThis.CheonglaPrint.node(title, content);
    }));
    exports.querySelector('[data-mbti-intro-pdf]').addEventListener('click', () => exportPublished(title => {
      const pdf = globalThis.CheonglaMBTIIntroductionPDF.create(document, title, content.children);
      const url = URL.createObjectURL(pdf);
      const link = document.createElement('a');
      link.href = url;
      link.download = '청라_MBTI학습법_소개글.pdf';
      document.body.append(link);
      try {
        link.click();
      } finally {
        link.remove();
        setTimeout(() => URL.revokeObjectURL(url), 60000);
      }
    }));

    section.addEventListener('toggle', () => {
      if (section.open && !section.hidden && !rows.length && controls.hidden) void load();
    });
    form.addEventListener('submit', event => {
      event.preventDefault();
      const title = form.elements.title.value.trim();
      const body = form.elements.body.value.trim();
      if (!title || !body) {
        status.textContent = '소개글 제목과 본문을 모두 입력해 주세요.';
        return;
      }
      const row = rows.find(item => !item.archived_at);
      const values = { title, body };
      void write(row ? update(row, values) : source => source.insert(values), '소개글을 저장했습니다.');
    });
    form.querySelector('[data-mbti-intro-cancel]').addEventListener('click', () => {
      form.hidden = true;
      form.reset();
    });

    return {
      load,
      reset() {
        request++;
        busy = false;
        rows = [];
        render();
        section.hidden = false;
        section.open = false;
        trash.open = false;
        controls.hidden = true;
        controls.disabled = false;
        summary.textContent = defaultTitle;
        status.textContent = '';
      }
    };
  }
};
