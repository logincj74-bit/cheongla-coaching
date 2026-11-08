globalThis.CheonglaMBTIIntroduction = {
  mountPages(options) {
    const { document } = options;
    const pages = [...document.querySelectorAll('[data-mbti-page]')];
    const original = document.getElementById('mbtiIntroduction');
    const intro = this.mount(options);
    const articles = { mbti_intro: [intro], mbti_groups: [], mbti_parents: [] };
    for (const [page, category, label] of [
      ['mbti_groups', 'groups', 'MBTI 여섯 그룹 학습성향'],
      ['mbti_parents', 'parent_sj', 'SJ 기질의 부모'],
      ['mbti_parents', 'parent_sp', 'SP 기질의 부모'],
      ['mbti_parents', 'parent_nf', 'NF 기질의 부모'],
      ['mbti_parents', 'parent_nt', 'NT 기질의 부모']
    ]) {
      const section = original.cloneNode(true);
      section.id = 'mbtiArticle-' + category;
      section.querySelector('summary').textContent = label;
      section.querySelector('article').setAttribute('aria-label', label);
      section.querySelector('legend').textContent = '자료 관리 · 원장';
      section.querySelector('[data-mbti-intro-print]').textContent = '자료 인쇄';
      section.querySelector('button[type="submit"]').textContent = '저장';
      for (const control of section.querySelectorAll('input, textarea')) {
        section.querySelector('label[for="' + control.id + '"]').htmlFor = control.id + '-' + category;
        control.id += '-' + category;
      }
      pages.find(panel => panel.dataset.mbtiPage === page).append(section);
      articles[page].push(this.mount({ ...options, section, category, label }));
    }
    return {
      open(page) {
        for (const panel of pages) panel.hidden = panel.dataset.mbtiPage !== page;
        const visibleArticles = articles[page] || [];
        for (const article of visibleArticles) void article.load();
        if (visibleArticles.length === 1) visibleArticles[0].expand();
      },
      reset() {
        for (const article of Object.values(articles).flat()) article.reset();
      }
    };
  },

  mount({ document, client, canEdit, confirm, readable,
    section = document.getElementById('mbtiIntroduction'), category, label = 'MBTI 학습법 소개' }) {
    const summary = section.querySelector('summary');
    const status = section.querySelector('[role="status"]');
    const content = section.querySelector('article');
    const titleHeading = section.querySelector('[data-mbti-article-title]');
    const controls = section.querySelector('fieldset');
    const exports = section.querySelector('[data-mbti-intro-export]');
    const form = controls.querySelector('form');
    const trash = controls.querySelector('details');
    const trashList = trash.querySelector('ul');
    let request = 0;
    let busy = false;
    let rows = [];
    const table = category ? 'cheongla_mbti_learning_articles' : 'cheongla_mbti_introductions';
    const columns = 'id,title,body,archived_at,revision';
    const noun = category ? '자료' : '소개글';
    const objectLabel = category ? '자료를' : '소개글을';

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
            ? '이미 게시된 글이 있습니다. 해당 글을 휴지통으로 옮긴 뒤 다시 시도해 주세요.'
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
        if (prompt && !(await confirm(prompt, 'MBTI ' + noun + ' 관리'))) return;
        if (!current() || !canEdit()) return;
        const result = await change(source).select(columns).maybeSingle();
        if (!current()) return;
        if (result.error) throw result.error;
        if (!result.data) throw new Error('다른 곳에서 글이 변경되었습니다. 다시 불러와 주세요.');
        rows = rows.filter(item => item.id !== result.data.id);
        if (!remove) rows.push(result.data);
        render();
        status.textContent = message;
      }, '글에 변경 사항을 반영하지 못했습니다.');
    }

    function update(row, values) {
      return source => source.update(values).eq('id', row.id).eq('revision', row.revision);
    }

    function render() {
      const published = rows.find(row => !row.archived_at);
      const editable = canEdit();
      section.querySelector('[data-mbti-empty]').hidden = Boolean(published);
      exports.hidden = !published;
      summary.textContent = label;
      content.replaceChildren();
      titleHeading.hidden = !published;
      titleHeading.textContent = published?.title || '';
      for (const paragraph of (published?.body || '').split(/\n\s*\n/).filter(Boolean)) {
        const element = document.createElement(/^(?:\d+\. |\d+ \| |읽는 법$|한눈에 보는 NF 부모$|마무리$)/.test(paragraph) ? 'h3' : 'p');
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

      actions.append(button(noun + (published ? ' 수정' : ' 작성'), () => {
        form.elements.title.value = published?.title || '';
        form.elements.body.value = published?.body || '';
        form.hidden = false;
        form.elements.title.focus();
      }));
      if (published) {
        actions.append(button('휴지통으로 이동', () => write(update(published, { archived_at: new Date().toISOString() }),
          objectLabel + ' 휴지통으로 옮겼습니다.', { prompt: objectLabel + ' 휴지통으로 옮기시겠어요?' })));
      }
      actions.append(button('다시 불러오기', async () => {
        if (!form.hidden && !await confirm('작성 중인 변경 사항을 버리고 다시 불러올까요?', '다시 불러오기')) return;
        void load();
      }));

      const archived = rows.filter(row => row.archived_at)
        .sort((first, second) => second.archived_at.localeCompare(first.archived_at));
      trash.hidden = !archived.length;
      trash.querySelector('summary').textContent = noun + ' 휴지통 (' + archived.length + ')';
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
          objectLabel + ' 복원했습니다.'));
        restore.disabled = Boolean(published);
        item.append(preview, restore, button('영구삭제', () => write(
          source => source.delete().eq('id', row.id).eq('revision', row.revision).not('archived_at', 'is', null),
          objectLabel + ' 영구삭제했습니다.', { remove: true, prompt: '이 글을 영구삭제하면 복원할 수 없습니다. 삭제하시겠어요?' })));
        trashList.append(item);
      }
      controls.querySelector('[data-mbti-intro-trash-help]').hidden = !published;
    }

    function load() {
      return run(async (source, current) => {
        const query = source.select(columns);
        const { data, error } = await (category ? query.eq('category', category) : query);
        if (!current()) return;
        if (error) throw error;
        rows = data;
        render();
      }, '글을 불러오지 못했습니다. 닫았다가 다시 열어 주세요.');
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
      link.download = category ? '청라_' + title.replace(/[\\/:*?"<>|]/g, '_') + '.pdf' : '청라_MBTI학습법_소개글.pdf';
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
        status.textContent = '제목과 본문을 모두 입력해 주세요.';
        return;
      }
      const row = rows.find(item => !item.archived_at);
      const values = { title, body };
      void write(row ? update(row, values) : source => source.insert(category ? { ...values, category } : values), objectLabel + ' 저장했습니다.');
    });
    form.querySelector('[data-mbti-intro-cancel]').addEventListener('click', () => {
      form.hidden = true;
      form.reset();
    });

    return {
      load: () => form.hidden ? load() : undefined,
      expand: () => { section.open = true; },
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
        summary.textContent = label;
        status.textContent = '';
      }
    };
  }
};
