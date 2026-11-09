globalThis.CheonglaMBTIOperations = {
  mount({ document, profile, canEdit, client, confirm, readable, appendReference }) {
    const $ = id => document.getElementById(id);
    const student = $('mbtiOperationStudent');
    const status = $('mbtiOperationStatus');
    const reference = $('mbtiOperationReference');
    const printReference = $('mbtiOperationReferencePrint');
    printReference.addEventListener('click', () => {
      if (!canEdit() || !reference.children.length) return;
      try {
        if (!globalThis.CheonglaPrint?.node) throw new Error('인쇄 기능을 준비 중입니다.');
        globalThis.CheonglaPrint.node(code + ' · 학습 운영 참고 자료', reference);
      } catch (error) { status.textContent = readable(error); }
    });
    const section = $('mbtiIntroduction').cloneNode(true);
    section.id = 'mbtiPrescriptionArticle';
    section.querySelector('article').setAttribute('aria-label', '학생별 학습 처방');
    section.querySelector('legend').textContent = '학습 처방 관리 · 원장·실장';
    section.querySelector('[data-mbti-intro-print]').textContent = '학습 처방 인쇄';
    section.querySelector('button[type="submit"]').textContent = '학습 처방 저장';
    for (const control of section.querySelectorAll('input, textarea')) {
      section.querySelector('label[for="' + control.id + '"]').htmlFor = control.id + '-prescription';
      control.id += '-prescription';
    }
    $('mbtiPrescription').append(section);
    let code = '';
    let generation = 0;
    let students = null;
    let selected = '';
    let actor;
    const editor = globalThis.CheonglaMBTIIntroduction.mount({
      document, client, confirm, readable, section,
      label: '학생별 학습 처방', noun: '처방', table: 'cheongla_mbti_prescriptions',
      canEdit: () => canEdit() && Boolean(selected && code),
      scope: () => ({ student_id: selected, mbti: code }),
      documentTitle: title => (students?.find(row => row.id === selected)?.full_name || '재원생') + ' · ' + code + ' · ' + title
    });

    function selectStudent() {
      editor.reset();
      selected = student.value;
      section.hidden = !selected || !canEdit();
      if (!section.hidden) {
        editor.expand();
        void editor.load();
      }
    }

    student.addEventListener('change', selectStudent);

    function reset() {
      generation++;
      actor = null;
      code = '';
      students = null;
      selected = '';
      student.length = 1;
      student.value = '';
      student.disabled = false;
      reference.replaceChildren();
      printReference.hidden = true;
      status.textContent = '';
      editor.reset();
      section.hidden = true;
      $('mbtiOperations').hidden = true;
    }

    async function open(nextCode) {
      if (!canEdit()) return;
      if (actor === profile() && code === nextCode) return;
      const token = ++generation;
      actor = profile();
      code = nextCode;
      const current = () => token === generation && actor === profile() && canEdit();
      selectStudent();
      reference.replaceChildren();
      printReference.hidden = true;
      status.textContent = '학생 목록과 참고 자료를 불러오는 중입니다…';
      student.disabled = true;
      try {
        const db = await client();
        if (!current()) return;
        const [roster, guide] = await Promise.all([
          students ? Promise.resolve({ data: students }) : db.rpc('cheongla_mbti_operation_students'),
          db.from('cheongla_mbti_operation_references').select('sections').eq('mbti', nextCode).maybeSingle()
        ]);
        if (!current()) return;
        if (!roster.error && !students) {
          students = roster.data || [];
          for (const row of students) {
            const option = document.createElement('option');
            option.value = row.id;
            option.textContent = (row.full_name || '이름 미등록') + ' · ' + row.id.slice(0, 8);
            student.append(option);
          }
        }
        if (!guide.error) {
          for (const item of guide.data?.sections || []) appendReference(reference, item, true);
          printReference.hidden = !reference.children.length;
        }
        status.textContent = roster.error || guide.error
          ? '일부 자료를 불러오지 못했습니다. 다시 확인을 눌러 주세요.'
          : students.length ? '' : '승인된 재원생이 없습니다.';
        if (roster.error || guide.error) actor = null;
      } catch (error) {
        if (current()) {
          status.textContent = readable(error);
          actor = null;
        }
      } finally {
        if (token === generation) student.disabled = false;
      }
    }
    reset();
    return { open, reset };
  }
};
