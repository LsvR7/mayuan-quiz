(function () {
  const STORAGE_KEY = 'mayuan-review-state-v1';
  const questions = Array.isArray(window.QUESTION_BANK) ? window.QUESTION_BANK : [];
  const typeNames = { single: '单项选择', multiple: '多项选择', judge: '判断题' };

  const state = loadState();
  let filtered = [];
  let currentIndex = 0;
  let submitted = false;

  const els = {
    totalCount: document.getElementById('totalCount'),
    wrongCount: document.getElementById('wrongCount'),
    modeSelect: document.getElementById('modeSelect'),
    chapterSelect: document.getElementById('chapterSelect'),
    typeSelect: document.getElementById('typeSelect'),
    startInput: document.getElementById('startInput'),
    jumpButton: document.getElementById('jumpButton'),
    positionText: document.getElementById('positionText'),
    tagText: document.getElementById('tagText'),
    questionText: document.getElementById('questionText'),
    answerForm: document.getElementById('answerForm'),
    answerPanel: document.getElementById('answerPanel'),
    prevButton: document.getElementById('prevButton'),
    submitButton: document.getElementById('submitButton'),
    showAnswerButton: document.getElementById('showAnswerButton'),
    nextButton: document.getElementById('nextButton'),
    historyText: document.getElementById('historyText'),
    clearProgressButton: document.getElementById('clearProgressButton'),
    clearWrongButton: document.getElementById('clearWrongButton')
  };

  init();

  function init() {
    fillChapters();
    els.modeSelect.value = state.filters.mode;
    els.chapterSelect.value = state.filters.chapter;
    els.typeSelect.value = state.filters.type;
    els.startInput.value = state.filters.start || 1;
    bindEvents();
    applyFilters(true);
  }

  function loadState() {
    const defaults = {
      filters: { mode: 'study', chapter: 'all', type: 'all', start: 1 },
      positions: {},
      history: {},
      wrong: {}
    };
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      return {
        ...defaults,
        ...saved,
        filters: { ...defaults.filters, ...(saved.filters || {}) },
        positions: saved.positions || defaults.positions,
        history: saved.history || defaults.history,
        wrong: saved.wrong || defaults.wrong
      };
    } catch (error) {
      return defaults;
    }
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function fillChapters() {
    const chapters = [...new Set(questions.map((q) => q.chapter))].filter(Boolean);
    els.chapterSelect.innerHTML = '<option value="all">全部章节</option>' +
      chapters.map((chapter) => `<option value="${escapeAttr(chapter)}">${escapeHtml(chapter)}</option>`).join('');
  }

  function bindEvents() {
    [els.modeSelect, els.chapterSelect, els.typeSelect].forEach((control) => {
      control.addEventListener('change', () => applyFilters(false));
    });
    els.jumpButton.addEventListener('click', jumpToStart);
    els.prevButton.addEventListener('click', () => move(-1));
    els.nextButton.addEventListener('click', () => move(1));
    els.submitButton.addEventListener('click', submitAnswer);
    els.showAnswerButton.addEventListener('click', () => showAnswer());
    els.clearProgressButton.addEventListener('click', clearProgress);
    els.clearWrongButton.addEventListener('click', clearWrong);
  }

  function applyFilters(restorePosition) {
    state.filters.mode = els.modeSelect.value;
    state.filters.chapter = els.chapterSelect.value;
    state.filters.type = els.typeSelect.value;
    state.filters.start = Number(els.startInput.value) || 1;

    filtered = questions.filter((q) => {
      const chapterOk = state.filters.chapter === 'all' || q.chapter === state.filters.chapter;
      const typeOk = state.filters.type === 'all' || q.type === state.filters.type;
      const wrongOk = state.filters.mode !== 'wrong' || Boolean(state.wrong[q.id]);
      return chapterOk && typeOk && wrongOk;
    });

    const key = positionKey();
    const savedIndex = restorePosition ? state.positions[key] || 0 : 0;
    currentIndex = clamp(savedIndex, 0, Math.max(filtered.length - 1, 0));
    submitted = false;
    savePosition();
    saveState();
    render();
  }

  function jumpToStart() {
    const target = Number(els.startInput.value) || 1;
    currentIndex = clamp(target - 1, 0, Math.max(filtered.length - 1, 0));
    state.filters.start = target;
    submitted = false;
    savePosition();
    saveState();
    render();
  }

  function move(delta) {
    currentIndex = clamp(currentIndex + delta, 0, Math.max(filtered.length - 1, 0));
    submitted = false;
    savePosition();
    saveState();
    render();
  }

  function render() {
    els.totalCount.textContent = `${questions.length} 题`;
    els.wrongCount.textContent = `错题 ${Object.keys(state.wrong).length}`;

    if (!filtered.length) {
      els.positionText.textContent = '第 0 / 0 题';
      els.tagText.textContent = state.filters.mode === 'wrong' ? '错题重练为空' : '没有匹配题目';
      els.questionText.textContent = state.filters.mode === 'wrong'
        ? '错题重练组里暂时没有题目。'
        : '当前筛选条件下没有题目。';
      els.answerForm.innerHTML = '';
      hideAnswer();
      updateButtons();
      renderHistory(null);
      return;
    }

    const q = filtered[currentIndex];
    els.positionText.textContent = `第 ${currentIndex + 1} / ${filtered.length} 题`;
    els.tagText.textContent = `${q.goal || '未分目标'} · ${typeNames[q.type] || q.type}`;
    els.questionText.textContent = q.question;
    els.answerForm.innerHTML = renderOptions(q);
    hideAnswer();

    if (state.filters.mode === 'study') {
      showAnswer();
    }

    updateButtons();
    renderHistory(q);
  }

  function renderOptions(q) {
    if (q.type === 'judge') {
      return ['是', '否'].map((value) => optionHtml(q, value, value)).join('');
    }
    return q.options.map((option) => optionHtml(q, option.key, `${option.key}. ${option.text}`)).join('');
  }

  function optionHtml(q, value, label) {
    const inputType = q.type === 'multiple' ? 'checkbox' : 'radio';
    return `<label class="option">
      <input type="${inputType}" name="answer" value="${escapeAttr(value)}">
      <span>${escapeHtml(label)}</span>
    </label>`;
  }

  function submitAnswer() {
    if (!filtered.length || submitted) { return; }
    const q = filtered[currentIndex];
    const selected = getSelectedAnswers();
    if (!selected.length) {
      showAnswer('请先选择答案，再提交。', 'bad', false);
      return;
    }
    const correct = sameAnswer(selected, q.answer);
    recordAnswer(q, correct);
    submitted = true;
    showAnswer(correct ? '回答正确。' : '回答错误。', correct ? 'good' : 'bad', true);
    saveState();
    renderHistory(q);
    updateButtons();
    els.wrongCount.textContent = `错题 ${Object.keys(state.wrong).length}`;
  }

  function getSelectedAnswers() {
    return [...els.answerForm.querySelectorAll('input:checked')]
      .map((input) => input.value)
      .sort();
  }

  function sameAnswer(left, right) {
    const a = [...left].sort().join('');
    const b = [...right].sort().join('');
    return a === b;
  }

  function recordAnswer(q, correct) {
    const item = state.history[q.id] || { correct: 0, wrong: 0, streak: 0, lastAnsweredAt: '' };
    if (correct) {
      item.correct += 1;
      item.streak += 1;
      if (state.wrong[q.id]) {
        state.wrong[q.id].streak = item.streak;
        if (item.streak >= 2) {
          delete state.wrong[q.id];
        }
      }
    } else {
      item.wrong += 1;
      item.streak = 0;
      state.wrong[q.id] = { addedAt: new Date().toISOString(), streak: 0 };
    }
    item.lastAnsweredAt = new Date().toISOString();
    state.history[q.id] = item;
  }

  function showAnswer(prefix, kind, includeResult) {
    if (!filtered.length) { return; }
    const q = filtered[currentIndex];
    const answerText = formatAnswer(q);
    const intro = prefix ? `<strong>${escapeHtml(prefix)}</strong><br>` : '';
    const result = includeResult ? `你的答案：${escapeHtml(getSelectedAnswers().join('、') || '未选择')}<br>` : '';
    els.answerPanel.className = `answer-panel ${kind || ''}`;
    els.answerPanel.innerHTML = `${intro}${result}正确答案：${escapeHtml(answerText)}`;
  }

  function hideAnswer() {
    els.answerPanel.className = 'answer-panel hidden';
    els.answerPanel.textContent = '';
  }

  function formatAnswer(q) {
    if (q.type === 'judge') { return q.answer.join('、'); }
    const detail = q.answer.map((key) => {
      const option = q.options.find((item) => item.key === key);
      return option ? `${key}. ${option.text}` : key;
    });
    return detail.join('；');
  }

  function renderHistory(q) {
    if (!q) {
      els.historyText.textContent = '还没有作答记录。';
      return;
    }
    const item = state.history[q.id];
    if (!item) {
      els.historyText.textContent = '这道题还没有作答记录。';
      return;
    }
    const wrongStatus = state.wrong[q.id] ? '，仍在错题组' : '';
    els.historyText.textContent = `答对 ${item.correct} 次，答错 ${item.wrong} 次，连续答对 ${item.streak} 次${wrongStatus}。`;
  }

  function updateButtons() {
    const hasQuestions = filtered.length > 0;
    els.prevButton.disabled = !hasQuestions || currentIndex === 0;
    els.nextButton.disabled = !hasQuestions || currentIndex >= filtered.length - 1;
    els.submitButton.disabled = !hasQuestions || state.filters.mode === 'study' || submitted;
    els.showAnswerButton.disabled = !hasQuestions || state.filters.mode === 'study';
  }

  function clearProgress() {
    if (!confirm('确定清空当前位置和全部作答记录吗？错题记录也会清空。')) { return; }
    state.positions = {};
    state.history = {};
    state.wrong = {};
    currentIndex = 0;
    submitted = false;
    saveState();
    render();
  }

  function clearWrong() {
    if (!confirm('确定清空错题记录吗？作答次数会保留。')) { return; }
    state.wrong = {};
    if (state.filters.mode === 'wrong') {
      applyFilters(false);
    } else {
      saveState();
      render();
    }
  }

  function savePosition() {
    state.positions[positionKey()] = currentIndex;
  }

  function positionKey() {
    return `${state.filters.mode}|${state.filters.chapter}|${state.filters.type}`;
  }

  function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    }[char]));
  }

  function escapeAttr(value) {
    return escapeHtml(value);
  }
})();
