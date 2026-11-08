globalThis.CheonglaHomeFeatures = {
  mount({ document, client, profile, principal, confirm, readable }) {
    const bucket = 'cheongla-home-videos';
    const table = 'cheongla_home_features';
    const original = 'https://cheongla-winter-2027.logincj.chatgpt.site/videos/cheongla-tour.mp4';
    const labels = { tour: '청라 내부투어', countdown: '수능 D-day' };
    const $ = id => document.getElementById(id);
    const dialog = $('homeFeaturesDialog');
    const form = $('homeFeaturesForm');
    const fields = form.querySelector('fieldset');
    const entry = $('homeFeaturesManage');
    const status = $('homeFeaturesStatus');
    const close = $('homeFeaturesClose');
    const list = $('homeFeaturesTrash');
    let rows = [];
    let busy = false;
    let kind = 'tour';
    let editing;
    let request = 0;

    const published = type => rows.find(row => row.kind === type && !row.archived_at);

    function renderPublic() {
      const tour = published('tour');
      const countdown = published('countdown');
      $('homeTourSection').hidden = !tour;
      $('homeTourOpen').hidden = !tour?.video_path && !tour?.original_video;
      if (tour) {
        $('homeTourTitle').textContent = tour.title;
        $('homeTourDescription').textContent = tour.description;
      }
      $('homeClockExam').hidden = !countdown;
      $('homeDailyCountdown').hidden = !countdown;
      $('homeCountdownVideo').hidden = !countdown?.video_path;
      if (countdown) {
        const date = new Intl.DateTimeFormat('ko-KR', {
          dateStyle: 'full', timeZone: 'Asia/Seoul'
        }).format(new Date(countdown.target_date + 'T12:00:00+09:00'));
        $('homeCountdownTitle').textContent = countdown.title;
        $('homeCountdownDate').textContent = date;
        $('homeCountdownDescription').textContent = countdown.description;
        $('homeCountdownDescription').hidden = !countdown.description;
        $('homeClockExam').title = countdown.title + ' · ' + date;
        $('homeClockExamDetail').textContent = countdown.title + ' · ' + date;
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
        if (token !== request || actor !== profile()) return false;
        rows = data;
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
      editing = published(kind);
      form.reset();
      form.elements.kind.value = kind;
      form.elements.title.value = editing?.title || '';
      form.elements.description.value = editing?.description || '';
      form.elements.targetDate.value = editing?.target_date || '';
      form.elements.targetDate.required = kind === 'countdown';
      $('homeFeaturesDateField').hidden = kind !== 'countdown';
      $('homeFeaturesCurrentVideo').textContent = editing?.video_path ? '현재 업로드한 영상이 있습니다.'
        : editing?.original_video ? '현재 기본 내부투어 영상이 연결되어 있습니다.' : '현재 연결된 영상이 없습니다.';
      $('homeFeaturesRemoveVideo').hidden = !editing?.video_path && !editing?.original_video;
      $('homeFeaturesArchive').hidden = !editing;
      list.replaceChildren();
      for (const row of rows.filter(item => item.kind === kind && item.archived_at)
        .sort((a, b) => b.archived_at.localeCompare(a.archived_at))) {
        const item = document.createElement('li');
        const title = document.createElement('p');
        title.textContent = row.title + ' · ' + new Date(row.archived_at).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' });
        const restore = button('복원', () => change(row, { archived_at: null }, '홈 화면에 복원했습니다.'));
        restore.disabled = Boolean(editing);
        item.append(title, restore, button('영구삭제', () => change(row, null, '영구삭제했습니다.',
          '이 항목과 업로드한 영상을 영구삭제할까요?')));
        list.append(item);
      }
      $('homeFeaturesTrashHelp').textContent = list.children.length
        ? (editing ? '현재 게시된 항목을 휴지통으로 옮긴 뒤 복원할 수 있습니다.' : '복원하거나 영구삭제할 항목을 선택해 주세요.')
        : '휴지통이 비어 있습니다.';
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
          ? '이미 게시된 항목이 있습니다. 현재 항목을 휴지통으로 옮긴 뒤 복원해 주세요.'
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
      renderEditor();
      status.textContent = '';
    });
    $('homeFeaturesArchive').addEventListener('click', () => change(editing,
      { archived_at: new Date().toISOString() }, '휴지통으로 옮겼습니다.', '이 항목을 홈 화면에서 내리고 휴지통으로 옮길까요?'));
    $('homeFeaturesRemoveVideo').addEventListener('click', () => change(editing,
      { video_path: null, original_video: false }, '영상 연결을 삭제했습니다.', '이 항목의 영상만 삭제할까요?'));
    form.addEventListener('submit', event => {
      event.preventDefault();
      const row = editing;
      const file = form.elements.video.files[0];
      const values = {
        title: form.elements.title.value.trim(),
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
            if (row) values.original_video = false;
          }
          if (row) await update(db, row, values);
          else {
            const { error } = await db.from(table).insert({ ...values, kind });
            if (error) throw error;
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
        rows = rows.filter(row => !row.archived_at);
        entry.hidden = true;
        if (dialog.open) dialog.close();
        editing = null;
        list.replaceChildren();
        form.reset();
        fields.disabled = true;
        status.textContent = '';
      },
      countdown: () => published('countdown'),
      async video(type) {
        const row = published(type);
        if (!row) return null;
        if (row.original_video) return { url: original, title: labels[type] };
        if (!row.video_path) return null;
        const db = await client();
        const { data, error } = await db.storage.from(bucket).createSignedUrl(row.video_path, 900);
        if (error) throw error;
        if (published(type) !== row) return null;
        return { url: data.signedUrl, title: row.title };
      }
    };
  }
};
