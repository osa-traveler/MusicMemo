// 譜面ビュー（3段: メロディ / コード / ベース）。SwiftではSwiftUI Canvasで描画する層に対応。
// 内部データは音高/位置/音価のみ。五線上の位置・臨時記号は描画のたびに計算する。
//  上段: メロディ（ト音記号）… タップで音を入力
//  中段: コード（ト音記号・ボイシング表示）… タップでコードを置く/選択
//  下段: ベース（ヘ音記号）… タップでそのコードのベース音(C/D)を指定
(function (root) {
  const C = root.Core;
  const NS = 'http://www.w3.org/2000/svg';
  const NAT = [0, 2, 4, 5, 7, 9, 11]; // C D E F G A B
  const SHARP_ORDER = [3, 0, 4, 1, 5, 2, 6];
  const FLAT_ORDER = [6, 2, 5, 1, 4, 0, 3];
  const SIG_BY_PC = { 0: 0, 7: 1, 2: 2, 9: 3, 4: 4, 11: 5, 6: 6, 5: -1, 10: -2, 3: -3, 8: -4, 1: -5 };
  // 調号の位置（step = オクターブ*7 + 音名。C4 = 28、E4 = 30）
  const SIG_STEPS = {
    treble: { sharp: [38, 35, 39, 36, 33, 37, 34], flat: [34, 37, 33, 36, 32, 35, 31] },
    bass: { sharp: [24, 21, 25, 22, 19, 23, 20], flat: [20, 23, 19, 22, 18, 21, 17] },
  };
  const SP = 5; // 半間隔(px)
  const SYS_H = 375;
  // bottomStep: 第1線の step / bottomY: その y（システム上端から）/ mid: 第3線（符幹の向きの境）
  const STAVES = {
    melody: { clef: 'treble', bottomStep: 30, bottomY: 100, mid: 34, from: 0, to: 150, min: 22, max: 44 },
    chord: { clef: 'treble', bottomStep: 30, bottomY: 228, mid: 34, from: 150, to: 265, min: 22, max: 40 },
    bass: { clef: 'bass', bottomStep: 18, bottomY: 335, mid: 22, from: 265, to: SYS_H, min: 12, max: 28 },
  };
  const DURS = [['全', 1920], ['2分', 960], ['4分', 480], ['8分', 240], ['16分', 120]];

  const mod = (n, m) => ((n % m) + m) % m;
  function keySig(key) {
    const k = C.parseChord(key) || C.parseChord('C');
    return SIG_BY_PC[k.quality === 'm' ? (k.root + 3) % 12 : k.root];
  }
  function keyAlt(n) {
    const a = [0, 0, 0, 0, 0, 0, 0];
    for (let i = 0; i < Math.abs(n); i++) a[(n > 0 ? SHARP_ORDER : FLAT_ORDER)[i]] = n > 0 ? 1 : -1;
    return a;
  }
  // 音高 → {step, show}（show: 描画する臨時記号 1/-1/0(ナチュラル)/null）
  function spell(pitch, n) {
    const alt = keyAlt(n), pc = mod(pitch, 12);
    const mk = (L, a) => ({ step: (Math.floor((pitch - a) / 12) - 1) * 7 + L, show: a !== alt[L] ? a : null });
    for (let L = 0; L < 7; L++) if (mod(NAT[L] + alt[L], 12) === pc) return mk(L, alt[L]);
    const flats = n < 0 || (n === 0 && [3, 8, 10].includes(pc));
    for (let L = 0; L < 7; L++) if (NAT[L] === pc) return mk(L, 0);
    for (let L = 0; L < 7; L++) if (NAT[L] + (flats ? -1 : 1) === pc) return mk(L, flats ? -1 : 1);
    return mk(0, 0);
  }
  function pitchOf(step, n, acc) {
    const L = mod(step, 7);
    return 12 * (Math.floor(step / 7) + 1) + NAT[L] + keyAlt(n)[L] + acc;
  }

  function create({ store, player, run, mount }) {
    const st = { sel: null /* 選択メロディ音のpos */, selChord: null /* 選択コードのpos */, dur: 480, dotted: false, acc: 0, armed: null, geo: null };

    mount.innerHTML = `
      <div class="tools">
        <h3>音価（タップで入力する長さ）</h3>
        <div class="row" id="scDur"></div>
        <h3>メロディ: 変化記号</h3>
        <div class="row" id="scAcc"></div>
        <h3>コード（中段）: タップで置くコード / 選択中のコードを変更</h3>
        <div class="row pal" id="scPal"></div>
        <h3>選択中</h3>
        <div class="row" id="scOps"></div>
      </div>
      <div id="scMsg" class="hint"></div>
      <div id="scStaff" class="staffwrap"></div>
      <p class="hint">上段: 五線タップでメロディ入力 / 中段: タップでコードを置く・選択 / 下段: タップでそのコードのベース音を指定（根音と同じ音なら解除）。↑↓: 音高 / Shift+↑↓: オクターブ / ←→: 前後の音 / Delete: 削除</p>`;
    const wrap = mount.querySelector('#scStaff');
    const msg = (t) => { mount.querySelector('#scMsg').textContent = t || ''; };

    const btn = (label, fn, cls = '') => {
      const b = document.createElement('button');
      b.textContent = label; b.className = cls; b.onclick = fn;
      return b;
    };
    const curDur = () => Math.round(st.dur * (st.dotted ? 1.5 : 1));
    const notes = () => store.sketch.notes;
    const chords = () => store.sketch.chords;
    const selNote = () => notes().find((n) => n.pos === st.sel) || null;
    const selIndex = () => notes().findIndex((n) => n.pos === st.sel);
    const selChordIndex = () => chords().findIndex((c) => c.pos === st.selChord);
    const sound = (pitch) => player.preview([{ pitch, pos: 0, dur: 480, vel: 90 }], store.sketch.tempo);
    const soundChord = (name) => player.preview(C.renderPreview(store.sketch, name), store.sketch.tempo);

    function renderTools() {
      const dur = mount.querySelector('#scDur'), acc = mount.querySelector('#scAcc');
      const pal = mount.querySelector('#scPal'), ops = mount.querySelector('#scOps');
      dur.textContent = acc.textContent = pal.textContent = ops.textContent = '';
      DURS.forEach(([l, v]) => dur.appendChild(btn(l, () => { st.dur = v; renderTools(); }, st.dur === v ? 'on' : '')));
      dur.appendChild(btn('付点', () => { st.dotted = !st.dotted; renderTools(); }, st.dotted ? 'on' : ''));
      [['♮', 0], ['♯', 1], ['♭', -1]].forEach(([l, v]) => acc.appendChild(btn(l, () => { st.acc = v; renderTools(); }, st.acc === v ? 'on' : '')));

      const ci = selChordIndex();
      const curName = ci >= 0 ? chords()[ci].chord : st.armed;
      C.diatonicChords(store.sketch.key).forEach((name) => {
        pal.appendChild(btn(name, () => {
          if (ci >= 0) { run({ command: 'changeChord', index: ci, chord: name }); soundChord(name); }
          else { st.armed = name; soundChord(name); renderTools(); }
        }, curName === name ? 'on' : ''));
      });

      const n = selNote();
      const o = (label, fn, enabled) => { const b = btn(label, fn); b.disabled = !enabled; ops.appendChild(b); };
      o('半音↑', () => shift(1), !!n); o('半音↓', () => shift(-1), !!n);
      o('8度↑', () => shift(12), !!n); o('8度↓', () => shift(-12), !!n);
      o('音価を適用', () => run({ command: 'putNote', pitch: n.pitch, pos: n.pos, dur: curDur(), vel: n.vel }), !!n);
      o('メロディ削除', del, !!n);
      o('コード削除', delChord, ci >= 0);
    }
    function shift(d) {
      const i = selIndex();
      if (i < 0) return;
      const p = notes()[i].pitch + d;
      if (run({ command: 'changeNote', index: i, pitch: p })) sound(p);
    }
    function del() {
      const i = selIndex();
      if (i < 0) return;
      const next = notes()[i + 1] || notes()[i - 1];
      run({ command: 'deleteNote', index: i });
      st.sel = next ? next.pos : null;
      render();
    }
    function delChord() {
      const i = selChordIndex();
      if (i < 0) return;
      run({ command: 'deleteChord', index: i });
      st.selChord = null;
      render();
    }

    // ---------- 描画 ----------
    const el = (tag, attrs, parent, text) => {
      const e = document.createElementNS(NS, tag);
      for (const k in attrs) e.setAttribute(k, attrs[k]);
      if (text != null) e.textContent = text;
      if (parent) parent.appendChild(e);
      return e;
    };
    const Y = (staff, top, step) => top + staff.bottomY - (step - staff.bottomStep) * SP;

    function layout(W) {
      const s = store.sketch, n = keySig(s.key), bt = C.barTicks(s);
      const hdr = 50 + Math.abs(n) * 9 + 24;
      const minBar = Math.max(120, 170 * (bt / 1920));
      const bps = Math.max(1, Math.floor((W - hdr - 8) / minBar));
      const barW = (W - hdr - 8) / bps;
      return { s, n, bt, hdr, bps, barW, bars: C.lengthBars(s), W };
    }
    const noteX = (g, pos) => {
      const b = Math.floor(pos / g.bt);
      return g.hdr + (b % g.bps) * g.barW + 14 + ((pos - b * g.bt) / g.bt) * (g.barW - 24);
    };
    const sysTop = (g, pos) => Math.floor(Math.floor(pos / g.bt) / g.bps) * SYS_H;

    function render() {
      renderTools();
      const W = Math.max(280, wrap.clientWidth || 600);
      const g = layout(W);
      st.geo = g;
      const sysCount = Math.ceil(g.bars / g.bps);
      wrap.textContent = '';
      const svg = el('svg', { width: W, height: sysCount * SYS_H, class: 'staff' }, wrap);
      const ink = 'var(--ink)';
      const keyFlat = g.n < 0;
      const FONT = '"Apple Symbols","Noto Music","Segoe UI Symbol",serif';

      for (let sy = 0; sy < sysCount; sy++) {
        const top = sy * SYS_H;
        const nb = Math.min(g.bps, g.bars - sy * g.bps);
        const x1 = g.hdr + nb * g.barW;
        for (const key of ['melody', 'chord', 'bass']) {
          const S = STAVES[key];
          for (let i = 0; i < 5; i++) {
            const y = Y(S, top, S.bottomStep + i * 2);
            el('line', { x1: 8, x2: x1, y1: y, y2: y, stroke: ink, 'stroke-width': 1 }, svg);
          }
          if (S.clef === 'treble') el('text', { x: 10, y: Y(S, top, 28) + 8, 'font-size': 56, fill: ink, 'font-family': FONT }, svg, '𝄞');
          else el('text', { x: 12, y: Y(S, top, 22) + 14, 'font-size': 44, fill: ink, 'font-family': FONT }, svg, '𝄢');
          const steps = SIG_STEPS[S.clef][keyFlat ? 'flat' : 'sharp'];
          for (let i = 0; i < Math.abs(g.n); i++) {
            el('text', { x: 46 + i * 9, y: Y(S, top, steps[i]) + 5, 'font-size': 16, fill: ink }, svg, keyFlat ? '♭' : '♯');
          }
          for (let c = 0; c <= nb; c++) {
            const x = g.hdr + c * g.barW;
            el('line', { x1: x, x2: x, y1: Y(S, top, S.bottomStep), y2: Y(S, top, S.bottomStep + 8), stroke: ink, 'stroke-width': c === 0 ? 1.5 : 1 }, svg);
          }
        }
        // 3段をつなぐ縦線 + 小節番号 + 拍子
        el('line', { x1: 8, x2: 8, y1: Y(STAVES.melody, top, 38), y2: Y(STAVES.bass, top, 18), stroke: ink, 'stroke-width': 1.5 }, svg);
        for (let c = 0; c < nb; c++) {
          el('text', { x: g.hdr + c * g.barW + 3, y: Y(STAVES.melody, top, 38) - 6, 'font-size': 10, fill: 'var(--sub)' }, svg, sy * g.bps + c + 1);
        }
        if (sy === 0) {
          const tx = 46 + Math.abs(g.n) * 9 + 6;
          for (const key of ['melody', 'chord', 'bass']) {
            const S = STAVES[key];
            el('text', { x: tx, y: Y(S, top, S.bottomStep + 4) + 1, 'font-size': 17, 'font-weight': 700, fill: ink }, svg, g.s.timeSig[0]);
            el('text', { x: tx, y: Y(S, top, S.bottomStep) + 1, 'font-size': 17, 'font-weight': 700, fill: ink }, svg, g.s.timeSig[1]);
          }
        }
      }

      // 中段・下段: コード記号 / ボイシング / ベース音（コード進行から導出）
      let prev = null;
      chords().forEach((c) => {
        if (c.pos >= g.bars * g.bt) return;
        const v = C.voicing(c.chord, prev);
        if (!v.length) return;
        prev = v;
        const top = sysTop(g, c.pos), x = noteX(g, c.pos);
        const sel = c.pos === st.selChord;
        const col = sel ? 'var(--accent)' : 'var(--ink)';
        el('text', { x: x - 4, y: top + STAVES.chord.bottomY - 52, 'font-size': 14, 'font-weight': 700, fill: 'var(--accent)' }, svg, c.chord);
        if (sel) {
          const x2 = noteX(g, Math.min(c.pos + c.dur, (Math.floor(c.pos / g.bt) + 1) * g.bt - 1)) + 4;
          el('rect', { x: x - 12, y: top + STAVES.chord.from + 2, width: Math.max(24, x2 - x + 12), height: STAVES.chord.to - STAVES.chord.from - 4, fill: 'var(--sel)', opacity: 0.5, rx: 6, 'pointer-events': 'none' }, svg);
        }
        drawHeads(svg, g, STAVES.chord, top, x, v, c.dur, col);
        drawNote(svg, g, STAVES.bass, top, { pitch: C.bassPitch(c.chord), pos: c.pos, dur: c.dur }, false);
      });

      // 上段: メロディ
      notes().forEach((nt) => {
        if (nt.pos >= g.bars * g.bt) return;
        drawNote(svg, g, STAVES.melody, sysTop(g, nt.pos), nt, nt.pos === st.sel);
      });

      st.head = el('line', { x1: 0, x2: 0, y1: 0, y2: 0, stroke: 'var(--accent)', 'stroke-width': 2, opacity: 0, 'pointer-events': 'none' }, svg);
      svg.addEventListener('pointerdown', (e) => { e.preventDefault(); onTap(svg, e); });
    }

    const baseDur = (d) => (d >= 1920 ? 1920 : d >= 960 ? 960 : d >= 480 ? 480 : d >= 240 ? 240 : 120);
    function ledger(grp, S, top, x, step) {
      for (let s = S.bottomStep - 2; s >= step; s -= 2) el('line', { x1: x - 10, x2: x + 10, y1: Y(S, top, s), y2: Y(S, top, s), 'stroke-width': 1 }, grp);
      for (let s = S.bottomStep + 10; s <= step; s += 2) el('line', { x1: x - 10, x2: x + 10, y1: Y(S, top, s), y2: Y(S, top, s), 'stroke-width': 1 }, grp);
    }
    function head(grp, x, y, hollow) {
      el('ellipse', { cx: x, cy: y, rx: 6.2, ry: 4.4, transform: `rotate(-20 ${x} ${y})`, fill: hollow ? 'var(--panel)' : 'currentColor', 'stroke-width': 1.6 }, grp);
    }

    function drawNote(svg, g, S, top, nt, selected) {
      const sp = spell(nt.pitch, g.n);
      const x = noteX(g, nt.pos), y = Y(S, top, sp.step);
      const col = selected ? 'var(--accent)' : 'var(--ink)';
      const grp = el('g', { fill: col, stroke: col, color: col }, svg);
      ledger(grp, S, top, x, sp.step);
      const base = baseDur(nt.dur);
      head(grp, x, y, base >= 960);
      if (base < 1920) {
        const up = sp.step < S.mid;
        const sx = up ? x + 5.6 : x - 5.6, ey = up ? y - 30 : y + 30;
        el('line', { x1: sx, x2: sx, y1: y, y2: ey, 'stroke-width': 1.5 }, grp);
        const flags = base === 240 ? 1 : base === 120 ? 2 : 0;
        for (let f = 0; f < flags; f++) {
          const fy = up ? ey + f * 6 : ey - f * 6, d = up ? 1 : -1;
          el('path', { d: `M${sx} ${fy} q8 ${6 * d} 5 ${14 * d}`, fill: 'none', 'stroke-width': 1.6 }, grp);
        }
      }
      if (Math.abs(nt.dur - base * 1.5) < 2) el('circle', { cx: x + 11, cy: y - (sp.step % 2 === 0 ? 3 : 0), r: 1.8, stroke: 'none' }, grp);
      if (sp.show != null) el('text', { x: x - 20, y: y + 5, 'font-size': 15, stroke: 'none' }, grp, ['♭', '♮', '♯'][sp.show + 1]);
    }

    // 和音: 符頭だけ（符幹なし）。2度は左右にずらす
    function drawHeads(svg, g, S, top, x, pitches, dur, col) {
      const grp = el('g', { fill: col, stroke: col, color: col }, svg);
      const base = baseDur(dur);
      const sp = pitches.map((p) => ({ p, ...spell(p, g.n) })).sort((a, b) => a.step - b.step);
      let lastOff = false, lastStep = -99, accN = 0;
      sp.forEach((e) => {
        const off = e.step - lastStep === 1 && !lastOff;
        const hx = x + (off ? 12 : 0);
        ledger(grp, S, top, hx, e.step);
        head(grp, hx, Y(S, top, e.step), base >= 960);
        if (e.show != null) el('text', { x: x - 20 - (accN++ % 2) * 11, y: Y(S, top, e.step) + 5, 'font-size': 15, stroke: 'none' }, grp, ['♭', '♮', '♯'][e.show + 1]);
        lastOff = off; lastStep = e.step;
      });
    }

    // ---------- 入力 ----------
    function chordAt(pos) { return chords().findIndex((c) => c.pos <= pos && pos < c.pos + c.dur); }

    function onTap(svg, e) {
      const g = st.geo, r = svg.getBoundingClientRect();
      const x = e.clientX - r.left, y = e.clientY - r.top;
      const sysI = Math.floor(y / SYS_H), top = sysI * SYS_H, ly = y - top;
      const col = Math.floor((x - g.hdr) / g.barW);
      if (col < 0 || col >= g.bps) return;
      const bar = sysI * g.bps + col;
      if (bar >= g.bars) return;
      msg('');
      const unit = st.dur;
      const frac = (x - (g.hdr + col * g.barW + 14)) / (g.barW - 24);
      let pos = bar * g.bt + Math.round((frac * g.bt) / unit) * unit;
      pos = Math.max(bar * g.bt, Math.min(pos, (bar + 1) * g.bt - Math.min(unit, g.bt)));
      const stepAt = (S) => Math.max(S.min, Math.min(S.max, S.bottomStep + Math.round((S.bottomY - ly) / SP)));

      if (ly < STAVES.melody.to) { // 上段
        const S = STAVES.melody;
        const hit = notes().find((nt) => {
          if (Math.floor(nt.pos / g.bt) >= g.bars) return false;
          return Math.abs(noteX(g, nt.pos) - x) < 11 && Math.abs(Y(S, sysTop(g, nt.pos), spell(nt.pitch, g.n).step) - y) < 9;
        });
        st.selChord = null;
        if (hit) { st.sel = hit.pos; sound(hit.pitch); render(); return; }
        const pitch = pitchOf(stepAt(S), g.n, st.acc);
        if (run({ command: 'putNote', pitch, pos, dur: curDur(), vel: 90 })) { st.sel = pos; st.acc = 0; sound(pitch); render(); }
      } else if (ly < STAVES.chord.to) { // 中段
        st.sel = null;
        const ci = chordAt(pos);
        if (ci >= 0) { st.selChord = chords()[ci].pos; soundChord(chords()[ci].chord); render(); return; }
        const name = st.armed || C.diatonicChords(store.sketch.key)[0];
        const dur = Math.min(curDur(), (bar + 1) * g.bt - pos);
        if (run({ command: 'insertChord', pos, dur, chord: name })) { st.selChord = pos; soundChord(name); render(); }
      } else { // 下段: ベース音 → オンコード
        const ci = chordAt(pos);
        if (ci < 0) { msg('先に中段でコードを置いてください'); return; }
        const c = chords()[ci], p = C.parseChord(c.chord);
        const pc = mod(pitchOf(stepAt(STAVES.bass), g.n, st.acc), 12);
        const name = C.formatChord({ ...p, bass: pc === p.root ? null : pc }, p.flat || g.n < 0);
        st.acc = 0;
        st.selChord = c.pos; st.sel = null;
        if (run({ command: 'changeChord', index: ci, chord: name })) { player.preview([{ pitch: C.bassPitch(name), pos: 0, dur: 480, vel: 90 }], store.sketch.tempo); render(); }
      }
    }

    function key(e) {
      const ns = notes(), i = selIndex();
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        if (i < 0) return false;
        const up = e.key === 'ArrowUp';
        if (e.shiftKey) shift(up ? 12 : -12);
        else {
          const g = st.geo, sp = spell(ns[i].pitch, g.n);
          shift(pitchOf(sp.step + (up ? 1 : -1), g.n, 0) - ns[i].pitch);
        }
        return true;
      }
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        if (!ns.length) return false;
        const j = i < 0 ? 0 : Math.max(0, Math.min(ns.length - 1, i + (e.key === 'ArrowRight' ? 1 : -1)));
        st.sel = ns[j].pos; st.selChord = null; sound(ns[j].pitch); render();
        return true;
      }
      if ((e.key === 'Delete' || e.key === 'Backspace')) {
        if (i >= 0) { del(); return true; }
        if (selChordIndex() >= 0) { delChord(); return true; }
      }
      return false;
    }

    function markPlaying(ticks) {
      if (!st.head || !st.geo) return;
      if (ticks == null || ticks >= st.geo.bars * st.geo.bt) { st.head.setAttribute('opacity', 0); return; }
      const g = st.geo, top = sysTop(g, ticks), x = noteX(g, ticks);
      st.head.setAttribute('x1', x); st.head.setAttribute('x2', x);
      st.head.setAttribute('y1', Y(STAVES.melody, top, 38) - 6);
      st.head.setAttribute('y2', Y(STAVES.bass, top, 18) + 6);
      st.head.setAttribute('opacity', 0.8);
    }

    return { render, markPlaying, key };
  }

  root.ScoreView = { create, spell, pitchOf, keySig };
  if (typeof module !== 'undefined' && module.exports) module.exports = { spell, pitchOf, keySig };
})(typeof window !== 'undefined' ? window : globalThis);
