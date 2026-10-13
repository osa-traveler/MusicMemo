(function () {
  const C = window.Core;
  const $ = (id) => document.getElementById(id);
  const STORAGE = 'musicmemo.mock.v1';

  // ---------- 永続化 ----------
  let library = { sketches: [], currentId: null };
  try { library = JSON.parse(localStorage.getItem(STORAGE)) || library; } catch (e) { /* 初回 */ }
  if (!library.sketches.length) {
    const s = C.newSketch('はじめてのスケッチ');
    s.chords = C.parseProgression('C | Am | F | G', s).chords;
    library.sketches.push(s);
    library.currentId = s.id;
  }
  const cur = () => library.sketches.find((s) => s.id === library.currentId) || library.sketches[0];
  const store = new C.Store(cur());
  const player = new window.Player();
  const ui = { sel: null /* {bar, chord} */, loop: false, view: 'chord' };
  const score = window.ScoreView.create({ store, player, run: (c) => run(c), mount: $('scoreMount') });

  function save() {
    const i = library.sketches.findIndex((s) => s.id === store.sketch.id);
    library.sketches[i] = store.sketch;
    library.currentId = store.sketch.id;
    try { localStorage.setItem(STORAGE, JSON.stringify(library)); } catch (e) { /* 容量/プライベートモード */ }
  }
  const run = (cmd) => {
    try { store.dispatch(cmd); return true; } catch (e) { setMsg(e.message, true); return false; }
  };

  // ---------- 再生 ----------
  function play() {
    if (player.playing) { player.stop(); return renderTransport(); }
    player.start(() => store.sketch, { loop: ui.loop, onEnd: renderTransport });
    renderTransport();
    tick();
  }
  function tick() {
    if (!player.playing) { markPlaying(null); return; }
    markPlaying(player.position());
    requestAnimationFrame(tick);
  }
  function markPlaying(ticks) {
    score.markPlaying(ticks);
    const s = store.sketch, bt = C.barTicks(s);
    document.querySelectorAll('.bar').forEach((el) => el.classList.toggle('playing', ticks != null && Math.floor(ticks / bt) === +el.dataset.bar));
    document.querySelectorAll('.chord').forEach((el) => {
      const c = s.chords[+el.dataset.idx];
      el.classList.toggle('playing', ticks != null && c && ticks >= c.pos && ticks < c.pos + c.dur);
    });
  }

  // ---------- 描画 ----------
  function setMsg(text, bad) { $('progMsg').textContent = text; $('progMsg').classList.toggle('bad', !!bad); }

  function renderGrid() {
    const s = store.sketch, bt = C.barTicks(s), grid = $('grid');
    grid.textContent = '';
    for (let b = 0; b < C.lengthBars(s); b++) {
      const bar = document.createElement('div');
      bar.className = 'bar' + (ui.sel && ui.sel.bar === b ? ' sel' : '');
      bar.dataset.bar = b;
      bar.innerHTML = `<span class="no">${b + 1}</span>`;
      const wrap = document.createElement('div');
      wrap.className = 'chords';
      s.chords.forEach((c, idx) => {
        if (Math.floor(c.pos / bt) !== b) return;
        const el = document.createElement('button');
        el.className = 'chord' + (ui.sel && ui.sel.bar === b && ui.sel.chord === idx ? ' sel' : '');
        el.dataset.idx = idx;
        el.style.flexGrow = c.dur;
        el.textContent = c.chord;
        el.onclick = (e) => { e.stopPropagation(); ui.sel = { bar: b, chord: idx }; previewChord(c.chord); render(); };
        wrap.appendChild(el);
      });
      bar.appendChild(wrap);
      bar.onclick = () => { ui.sel = { bar: b, chord: -1 }; render(); };
      grid.appendChild(bar);
    }
  }

  function renderPalette() {
    const pal = $('palette');
    pal.textContent = '';
    C.diatonicChords(store.sketch.key).forEach((name) => {
      const b = document.createElement('button');
      b.textContent = name;
      b.onclick = () => applyChord(name);
      pal.appendChild(b);
    });
    const q = $('qualities');
    q.textContent = '';
    ['m', '7', 'maj7', 'm7', '6', 'sus4', 'add9', 'dim', 'aug'].forEach((qual) => {
      const b = document.createElement('button');
      b.className = 'chip';
      b.textContent = qual;
      b.onclick = () => {
        const c = selectedChord();
        if (c) applyChord(C.withQuality(c.chord, qual));
      };
      q.appendChild(b);
    });
  }

  function renderBasses() {
    const box = $('basses');
    box.textContent = '';
    const flat = C.diatonicChords(store.sketch.key).some((n) => n.includes('b') && !n.startsWith('b')) || /b/.test(store.sketch.key);
    const c = selectedChord();
    const cur = c && C.parseChord(c.chord);
    for (let pc = 0; pc < 12; pc++) {
      const b = document.createElement('button');
      b.className = 'chip' + (cur && cur.bass === pc ? ' on' : '');
      b.textContent = '/' + C.pcName(pc, flat);
      b.disabled = !c;
      b.onclick = () => applyChord(C.withBass(c.chord, pc));
      box.appendChild(b);
    }
  }

  function renderTransport() {
    $('play').textContent = player.playing ? '■ 停止' : '▶ 再生';
    $('loop').classList.toggle('on', ui.loop);
  }

  function renderList() {
    const ul = $('sketchList');
    ul.textContent = '';
    [...library.sketches].sort((a, b) => b.updatedAt - a.updatedAt).forEach((s) => {
      const li = document.createElement('li');
      li.className = s.id === store.sketch.id ? 'cur' : '';
      const prog = s.id === store.sketch.id ? C.formatProgression(store.sketch) : C.formatProgression(s);
      li.innerHTML = '<div><span></span><small></small></div><button class="del" title="削除">✕</button>';
      li.querySelector('span').textContent = (s.id === store.sketch.id ? store.sketch.title : s.title) || '無題';
      li.querySelector('small').textContent = prog || '（空）';
      li.onclick = () => switchTo(s.id);
      li.querySelector('.del').onclick = (e) => { e.stopPropagation(); removeSketch(s.id); };
      ul.appendChild(li);
    });
  }

  function syncControls() {
    const s = store.sketch;
    const setVal = (el, v) => { if (document.activeElement !== el && el.value !== String(v)) el.value = v; };
    setVal($('title'), s.title);
    setVal($('tempo'), s.tempo);
    setVal($('timeSig'), s.timeSig.join('/'));
    setVal($('key'), s.key);
    setVal($('pattern'), s.pattern);
    setVal($('memo'), s.memo);
    if (document.activeElement !== $('prog')) { $('prog').value = C.formatProgression(s); $('prog').classList.remove('bad'); setMsg(''); }
    $('undo').disabled = !store.canUndo;
    $('redo').disabled = !store.canRedo;
    document.querySelectorAll('#barOps button').forEach((b) => { b.disabled = !ui.sel; });
  }

  function render() {
    const bars = C.lengthBars(store.sketch);
    if (ui.sel && ui.sel.bar >= bars) ui.sel = bars ? { bar: bars - 1, chord: -1 } : null;
    const isScore = ui.view === 'score';
    $('scoreView').hidden = !isScore;
    $('chordTop').hidden = isScore;
    $('chordTools').hidden = isScore;
    $('tabChord').classList.toggle('on', !isScore);
    $('tabScore').classList.toggle('on', isScore);
    syncControls(); renderList(); renderTransport();
    if (isScore) score.render(); else { renderGrid(); renderPalette(); renderBasses(); }
  }
  store.subscribe(() => { save(); render(); });

  // ---------- 操作 ----------
  function selectedChord() {
    if (!ui.sel) return null;
    const s = store.sketch, bt = C.barTicks(s);
    if (ui.sel.chord >= 0) return s.chords[ui.sel.chord];
    return s.chords.find((c) => Math.floor(c.pos / bt) === ui.sel.bar) || null;
  }
  function previewChord(name) {
    const s = store.sketch;
    player.preview(C.renderPreview(s, name), s.tempo);
  }
  function applyChord(name) {
    const s = store.sketch, bt = C.barTicks(s);
    previewChord(name);
    if (!ui.sel) {
      const bar = C.lengthBars(s);
      // 末尾が空小節ならそこへ、そうでなければ新しい小節
      const last = bar - 1;
      const lastEmpty = !s.chords.some((c) => Math.floor(c.pos / bt) === last);
      const at = lastEmpty && s.chords.length ? last : bar;
      if (run({ command: 'insertChord', pos: at * bt, dur: bt, chord: name })) ui.sel = { bar: at, chord: -1 };
      render();
      return;
    }
    const c = selectedChord();
    if (c) run({ command: 'changeChord', index: s.chords.indexOf(c), chord: name });
    else run({ command: 'insertChord', pos: ui.sel.bar * bt, dur: bt, chord: name });
  }

  function barOp(op) {
    if (!ui.sel) return;
    const b = ui.sel.bar + 1, n = C.lengthBars(store.sketch);
    const sel = (bar) => { ui.sel = { bar: bar - 1, chord: -1 }; };
    switch (op) {
      case 'dup': if (run({ command: 'copyBars', startBar: b, endBar: b, insertAtBar: b + 1 })) sel(b + 1); break;
      case 'repeat': run({ command: 'repeatBars', source: { startBar: b, endBar: b }, repeatCount: 1, insertAtBar: b + 1 }); sel(b + 1); break;
      case 'insert': run({ command: 'insertBars', atBar: b + 1, count: 1 }); sel(b + 1); break;
      case 'left': if (b > 1 && run({ command: 'moveBars', startBar: b, endBar: b, toBar: b - 1 })) sel(b - 1); break;
      case 'right': if (b < n && run({ command: 'moveBars', startBar: b, endBar: b, toBar: b + 1 })) sel(b + 1); break;
      case 'delete': if (n > 1) run({ command: 'deleteBars', startBar: b, endBar: b }); break;
      case 'up': run({ command: 'transpose', semitones: 1, target: 'chords' }); break;
      case 'down': run({ command: 'transpose', semitones: -1, target: 'chords' }); break;
    }
    render();
  }

  function switchTo(id) {
    player.stop();
    library.currentId = id;
    ui.sel = null;
    store.load(library.sketches.find((s) => s.id === id));
  }
  function removeSketch(id) {
    if (!confirm('このスケッチを削除しますか？')) return;
    library.sketches = library.sketches.filter((s) => s.id !== id);
    if (!library.sketches.length) library.sketches.push(C.newSketch());
    if (id === store.sketch.id) switchTo(library.sketches[0].id);
    else { save(); renderList(); }
  }

  // ---------- イベント ----------
  const prog = $('prog');
  prog.addEventListener('input', () => {
    const r = C.parseProgression(prog.value, store.sketch);
    prog.classList.toggle('bad', r.errors.length > 0);
    setMsg(r.errors.length ? `解釈できません: ${r.errors.join(', ')}` : `${r.bars} 小節`, r.errors.length > 0);
  });
  function commitProg(thenPlay) {
    const before = C.formatProgression(store.sketch);
    if (prog.value.trim() !== before && !run({ command: 'setChords', text: prog.value })) return;
    if (thenPlay) { player.stop(); play(); }
  }
  prog.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); commitProg(true); }
  });
  prog.addEventListener('blur', () => { commitProg(false); prog.classList.remove('bad'); render(); });

  $('tabChord').onclick = () => { ui.view = 'chord'; render(); };
  $('tabScore').onclick = () => { ui.view = 'score'; render(); };
  window.addEventListener('resize', () => { if (ui.view === 'score') score.render(); });

  $('play').onclick = () => { if (document.activeElement === prog) commitProg(false); play(); };
  $('loop').onclick = () => { ui.loop = !ui.loop; if (player.playing) { player.stop(); play(); } renderTransport(); };
  $('undo').onclick = () => store.undo();
  $('redo').onclick = () => store.redo();
  $('newSketch').onclick = () => {
    player.stop();
    const s = C.newSketch('無題');
    library.sketches.push(s);
    switchTo(s.id);
    prog.focus();
  };
  $('sideToggle').onclick = () => $('side').classList.toggle('hidden');
  $('title').oninput = (e) => run({ command: 'setTitle', title: e.target.value });
  $('memo').oninput = (e) => run({ command: 'setMemo', text: e.target.value });
  $('tempo').onchange = (e) => run({ command: 'setTempo', tempo: Math.round(+e.target.value) });
  $('timeSig').onchange = (e) => { const [num, den] = e.target.value.split('/').map(Number); run({ command: 'setTimeSig', num, den }); };
  $('key').onchange = (e) => run({ command: 'setKey', key: e.target.value });
  $('pattern').onchange = (e) => run({ command: 'setPattern', pattern: e.target.value });
  $('barOps').onclick = (e) => { if (e.target.dataset.op) barOp(e.target.dataset.op); };

  document.addEventListener('keydown', (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z' && !typing) {
      e.preventDefault(); e.shiftKey ? store.redo() : store.undo(); return;
    }
    if (typing) return;
    if (ui.view === 'score') {
      if (e.key === ' ') { e.preventDefault(); play(); return; }
      if (score.key(e)) e.preventDefault();
      return;
    }
    const n = C.lengthBars(store.sketch);
    if (e.key === ' ') { e.preventDefault(); play(); }
    else if (e.key === 'ArrowRight') { ui.sel = { bar: Math.min(n - 1, ui.sel ? ui.sel.bar + 1 : 0), chord: -1 }; render(); }
    else if (e.key === 'ArrowLeft') { ui.sel = { bar: Math.max(0, ui.sel ? ui.sel.bar - 1 : 0), chord: -1 }; render(); }
    else if (e.key === 'Delete' || e.key === 'Backspace') barOp('delete');
  });

  // セレクトの初期化
  ['2/4', '3/4', '4/4', '6/8', '5/4'].forEach((t) => $('timeSig').add(new Option(t, t)));
  const names = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
  names.forEach((n) => $('key').add(new Option(n, n)));
  names.forEach((n) => $('key').add(new Option(n + 'm', n + 'm')));
  Object.entries(C.PATTERN_LABELS).forEach(([k, v]) => $('pattern').add(new Option(v, k)));

  render();
})();
