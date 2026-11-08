globalThis.CheonglaHomeFeatures = {
  mount({ document, client, profile, principal, confirm, readable }) {
    const bucket = 'cheongla-home-videos';
    const table = 'cheongla_home_features';
    const original = 'https://cheongla-winter-2027.logincj.chatgpt.site/videos/cheongla-tour.mp4';
    const $ = id => document.getElementById(id);
    const dialog = $('homeFeaturesDialog');
    const form = $('homeFeaturesForm');
    const fields = form.querySelector('fieldset');
    const entry = $('homeFeaturesManage');
    const status = $('homeFeaturesStatus');
    const close = $('homeFeaturesClose');
    const list = $('homeFeaturesTrash');
    const originalPoster = $('homeTourVideo').poster;
    let rows = [];
    let videoTrash = [];
    let selectedId = null;
    let busy = false;
    let kind = 'tour';
    let editing;
    let request = 0;

    const ordered = items => [...items].sort((a, b) =>
      a.sort_order - b.sort_order || a.title.localeCompare(b.title, 'ko') || a.id.localeCompare(b.id));
    const published = type => ordered(rows.filter(row => row.kind === type && !row.archived_at && !row.hidden));
    const representative = () => {
      const countdowns = published('countdown');
      return countdowns.find(row => row.featured) || countdowns[0];
    };
    const hasVideo = row => Boolean(row?.video_path || row?.original_video);
    const dateFormat = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'full', timeZone: 'Asia/Seoul' });
    const formatDate = date => dateFormat.format(new Date(date + 'T12:00:00+09:00'));

    function renderPublic() {
      const videos = $('homeTourSection');
      const schedules = $('homeDailyCountdown');
      const clock = $('homeClockExam');
      const countdown = representative();
      videos.replaceChildren();
      schedules.replaceChildren();

      function appendCard(container, template, row) {
        const card = $(template).content.firstElementChild.cloneNode(true);
        const play = card.querySelector('button');
        play.dataset.homeFeatureVideo = row.id;
        play.hidden = !hasVideo(row) || row.video_hidden;
        play.setAttribute('aria-label', row.title + ' 동영상 보기');
        container.append(card);
        return card;
      }

      for (const row of published('tour')) {
        const card = appendCard(videos, 'homeVideoCard', row);
        card.querySelector('h3').textContent = row.title;
        card.querySelector('p').textContent = row.description;
        card.querySelector('p').hidden = !row.description;
        if (row.original_video && !row.video_hidden) {
          const play = card.querySelector('button');
          play.classList.add('home-tour-open');
          const photo = document.createElement('img');
          photo.src = originalPoster;
          photo.alt = '';
          photo.loading = 'lazy';
          photo.width = 960;
          photo.height = 640;
          const caption = document.createElement('span');
          const title = document.createElement('strong');
          title.textContent = row.title + ' ▶';
          caption.append(title);
          play.replaceChildren(photo, caption);
        }
      }
      for (const row of published('countdown')) {
        const card = appendCard(schedules, 'homeCountdownCard', row);
        card.querySelector('[data-daily-dday]').dataset.dailyDday = row.target_date;
        card.querySelector('[data-countdown-title]').textContent = row.title;
        card.querySelector('[data-countdown-date]').textContent = formatDate(row.target_date);
        const description = card.querySelector('[data-countdown-description]');
        description.textContent = row.description;
        description.hidden = !row.description;
      }
      videos.hidden = !videos.children.length;
      schedules.hidden = !schedules.children.length;
      clock.hidden = !countdown;
      if (countdown) {
        clock.title = countdown.title + ' · ' + formatDate(countdown.target_date);
        clock.querySelector('.home-clock-label').textContent = countdown.title;
        $('homeClockExamDetail').textContent = formatDate(countdown.target_date);
      }
      document.dispatchEvent(new Event('cheongla-home-countdown'));
    }

    async function refresh() {
      entry.hidden = !principal();
      if (entry.hidden && dialog.open) dialog.close();
      const actor = profile();
      const token = ++request;
      try {
        const db = await client();
        const { data, error } = await db.from(table).select('*');
        if (error) throw error;
        const trash = dialog.open && principal()
          ? await db.from('cheongla_home_video_trash').select('*').order('archived_at', { ascending: false })
          : { data: [] };
        if (trash.error) throw trash.error;
        if (token !== request || actor !== profile()) return false;
        rows = data;
        videoTrash = trash.data;
        renderPublic();
        return true;
      } catch (error) {
        if (token === request && dialog.open) status.textContent = readable(error);
        return false;
      }
    }

    function button(label, action) {
      const element = document.createElement('button');
      element.type = 'button';
      element.className = 'secondary';
      element.textContent = label;
      element.addEventListener('click', action);
      return element;
    }

    function renderEditor() {
      const available = ordered(rows.filter(row => row.kind === kind && !row.archived_at));
      editing = selectedId === '' ? null : available.find(row => row.id === selectedId) || available[0] || null;
      selectedId = editing?.id || '';
      form.reset();
      form.elements.kind.value = kind;
      const chooser = $('homeFeaturesItem');
      chooser.replaceChildren();
      for (const [value, title] of [['', '새 콘텐츠 등록'], ...available.map(row =>
        [row.id, row.title + (row.hidden ? ' · 숨김' : row.featured ? ' · 대표 D-day' : '')])]) {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = title;
        chooser.append(option);
      }
      chooser.value = selectedId;
      $('homeFeaturesNewVisibility').hidden = Boolean(editing);
      form.elements.title.value = editing?.title || '';
      form.elements.description.value = editing?.description || '';
      form.elements.sortOrder.value = editing?.sort_order ?? 100;
      form.elements.targetDate.value = editing?.target_date || '';
      form.elements.targetDate.required = kind === 'countdown';
      $('homeFeaturesDateField').hidden = kind !== 'countdown';
      $('homeFeaturesCurrentVideo').textContent = hasVideo(editing)
        ? (editing.video_hidden ? '현재 영상은 숨김 상태입니다.' : '현재 연결된 영상이 있습니다.')
        : '현재 연결된 영상이 없습니다.';
      $('homeFeaturesHide').hidden = !editing;
      $('homeFeaturesHide').textContent = editing?.hidden ? '다시 공개' : '콘텐츠 숨기기';
      $('homeFeaturesFeatured').hidden = !editing || kind !== 'countdown' || editing.hidden || editing.featured;
      $('homeFeaturesHideVideo').hidden = !hasVideo(editing);
      $('homeFeaturesHideVideo').textContent = editing?.video_hidden ? '영상 다시 공개' : '영상 숨기기';
      $('homeFeaturesRemoveVideo').hidden = !hasVideo(editing);
      $('homeFeaturesArchive').hidden = !editing;
      list.replaceChildren();
      for (const row of rows.filter(item => item.kind === kind && item.archived_at)
        .sort((a, b) => b.archived_at.localeCompare(a.archived_at))) {
        const item = document.createElement('li');
        const title = document.createElement('p');
        title.textContent = row.title + ' · ' + new Date(row.archived_at).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });
        item.append(title, button('복원', () => change(row, { archived_at: null }, '콘텐츠를 복원했습니다.')),
          button('영구삭제', () => change(row, null, '영구삭제했습니다.', '이 콘텐츠와 연결된 영상을 영구삭제할까요?')));
        list.append(item);
      }
      $('homeFeaturesTrashHelp').textContent = list.children.length ? '복원하거나 영구삭제할 항목을 선택해 주세요.' : '휴지통이 비어 있습니다.';
      const videos = $('homeFeaturesVideoTrash');
      videos.replaceChildren();
      for (const row of videoTrash.filter(item => item.kind === kind)) {
        const item = document.createElement('li');
        const title = document.createElement('p');
        title.textContent = row.title + ' · ' + new Date(row.archived_at).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });
        const restore = button('선택한 콘텐츠에 복원', () => {
          if (editing) rpc('cheongla_manage_home_video_trash',
            { target: row.id, restore_to: editing.id, expected_revision: editing.revision },
            '영상을 복원했습니다.', '선택한 콘텐츠에 이 영상을 복원할까요? 기존 영상은 휴지통으로 이동합니다.');
        });
        restore.disabled = !editing;
        item.append(title, restore, button('영상 영구삭제', () => rpc('cheongla_manage_home_video_trash',
          { target: row.id }, '영상을 영구삭제했습니다.', '이 영상을 영구삭제할까요?')));
        videos.append(item);
      }
    }

    async function cleanup(db) {
      const queue = db.from('cheongla_home_video_cleanup');
      const { data, error } = await queue.select('path').limit(50);
      if (error) return false;
      if (!data.length) return true;
      const paths = data.map(row => row.path);
      const removed = await db.storage.from(bucket).remove(paths);
      if (removed.error) return false;
      const cleared = await db.from('cheongla_home_video_cleanup').delete().in('path', paths);
      return !cleared.error;
    }

    async function run(action) {
      if (busy || !principal()) return;
      const actor = profile();
      const current = () => actor === profile() && principal();
      busy = true;
      fields.disabled = true;
      close.disabled = true;
      try {
        const db = await client();
        if (!current()) return;
        const message = await action(db, current);
        if (!message || !current()) return;
        const refreshed = await refresh();
        if (!current()) return;
        if (refreshed) renderEditor();
        const cleaned = await cleanup(db).catch(() => false);
        if (current()) status.textContent = message +
          (refreshed ? '' : ' 홈 화면 확인을 위해 다시 열어 주세요.') +
          (cleaned ? '' : ' 이전 영상 파일 정리가 대기 중입니다. 관리 화면을 다시 열면 재시도합니다.');
      } catch (error) {
        if (current()) status.textContent = error?.code === '23505'
          ? '다른 곳에서 변경되었습니다. 관리 화면을 다시 열어 주세요.'
          : readable(error);
      } finally {
        busy = false;
        fields.disabled = false;
        close.disabled = false;
      }
    }

    async function update(db, row, values) {
      const source = db.from(table);
      const query = values ? source.update(values) : source.delete();
      const { data, error } = await query.eq('id', row.id).eq('revision', row.revision).select('id').maybeSingle();
      if (error) throw error;
      if (!data) throw new Error('다른 곳에서 항목이 변경되었습니다. 관리 화면을 다시 열어 주세요.');
    }

    function change(row, values, message, prompt) {
      if (!row) return;
      void run(async (db, current) => {
        if (prompt && !await confirm(prompt, '홈 화면 관리')) return;
        if (!current()) return;
        await update(db, row, values);
        return message;
      });
    }

    function rpc(name, args, message, prompt) {
      void run(async (db, current) => {
        if (prompt && !await confirm(prompt, '홈 화면 콘텐츠 관리')) return;
        if (!current()) return;
        const { error } = await db.rpc(name, args);
        if (error) throw error;
        return message;
      });
    }

    entry.addEventListener('click', async () => {
      if (!principal() || busy) return;
      dialog.showModal();
      fields.disabled = true;
      status.textContent = '게시 내용과 휴지통을 불러오는 중입니다…';
      const actor = profile();
      const refreshed = await refresh();
      if (!dialog.open || actor !== profile()) return;
      if (refreshed) {
        renderEditor();
        fields.disabled = false;
        status.textContent = '';
        const db = await client();
        if (actor === profile() && principal()) void cleanup(db).catch(() => {});
      }
    });
    close.addEventListener('click', () => dialog.close());
    dialog.addEventListener('cancel', event => { if (busy) event.preventDefault(); });
    form.elements.kind.addEventListener('change', event => {
      kind = event.target.value;
      selectedId = null;
      renderEditor();
      status.textContent = '';
    });
    $('homeFeaturesItem').addEventListener('change', event => {
      selectedId = event.target.value;
      renderEditor();
      status.textContent = '';
    });
    $('homeFeaturesHide').addEventListener('click', () => change(editing,
      { hidden: !editing?.hidden }, editing?.hidden ? '다시 공개했습니다.' : '콘텐츠를 숨겼습니다.'));
    $('homeFeaturesHideVideo').addEventListener('click', () => change(editing,
      { video_hidden: !editing?.video_hidden }, editing?.video_hidden ? '영상을 다시 공개했습니다.' : '영상을 숨겼습니다.'));
    $('homeFeaturesFeatured').addEventListener('click', () => {
      if (editing) rpc('cheongla_set_featured_home_countdown',
        { target: editing.id, expected_revision: editing.revision }, '대표 D-day를 지정했습니다.');
    });
    $('homeFeaturesArchive').addEventListener('click', () => change(editing,
      { archived_at: new Date().toISOString() }, '휴지통으로 옮겼습니다.', '이 항목을 홈 화면에서 내리고 휴지통으로 옮길까요?'));
    $('homeFeaturesRemoveVideo').addEventListener('click', () => change(editing,
      { video_path: null, original_video: false, video_hidden: false }, '영상을 휴지통으로 옮겼습니다.', '이 항목의 영상을 휴지통으로 옮길까요?'));
    form.addEventListener('submit', event => {
      event.preventDefault();
      const row = editing;
      const file = form.elements.video.files[0];
      const values = {
        title: form.elements.title.value.trim(),
        sort_order: Number(form.elements.sortOrder.value),
        description: form.elements.description.value.trim(),
        target_date: kind === 'countdown' ? form.elements.targetDate.value : null
      };
      if (!values.title) {
        status.textContent = '제목을 입력해 주세요.';
        return;
      }
      if (file && (!/\.mp4$/i.test(file.name) || file.size === 0 || file.size > 20 * 1024 * 1024)) {
        status.textContent = '20MB 이하의 MP4 파일을 선택해 주세요.';
        return;
      }
      void run(async (db, current) => {
        let path;
        const storage = db.storage.from(bucket);
        try {
          if (file) {
            status.textContent = '동영상을 업로드하는 중입니다…';
            path = crypto.randomUUID() + '.mp4';
            const { error } = await storage.upload(path, file, { contentType: 'video/mp4' });
            if (error) throw error;
            if (!current()) throw new Error('로그인 상태가 변경되었습니다.');
            values.video_path = path;
            if (row) {
              values.original_video = false;
              values.video_hidden = false;
            }
          }
          if (row) await update(db, row, values);
          else {
            const { data, error } = await db.from(table).insert({ ...values, kind, hidden: !form.elements.publishNow.checked }).select('id').single();
            if (error) throw error;
            if (current()) selectedId = data.id;
          }
          return '홈 화면에 저장했습니다.';
        } catch (error) {
          // Storage refuses to remove a file if the database save actually committed.
          if (path && current()) await storage.remove([path]).catch(() => {});
          throw error;
        }
      });
    });

    return {
      refresh,
      reset() {
        request++;
        rows = rows.filter(row => !row.archived_at && !row.hidden);
        videoTrash = [];
        selectedId = null;
        $('homeFeaturesVideoTrash').replaceChildren();
        entry.hidden = true;
        if (dialog.open) dialog.close();
        editing = null;
        list.replaceChildren();
        form.reset();
        fields.disabled = true;
        status.textContent = '';
      },
      countdown: representative,
      async video(id) {
        const row = rows.find(item => item.id === id && !item.archived_at && !item.hidden && !item.video_hidden);
        if (!row) return null;
        if (row.original_video) return { url: original, title: row.title, original: true };
        if (!row.video_path) return null;
        const db = await client();
        const { data, error } = await db.storage.from(bucket).createSignedUrl(row.video_path, 900);
        if (error) throw error;
        if (!rows.some(item => item.id === id && item.revision === row.revision && !item.archived_at && !item.hidden && !item.video_hidden)) return null;
        return { url: data.signedUrl, title: row.title };
      }
    };
  }
};
