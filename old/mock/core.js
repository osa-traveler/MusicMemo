// 楽曲モデル + 編集コマンド + 伴奏生成。UI・音源に依存しない（SwiftではModel/Commands層に対応）。
(function (root) {
  const PPQ = 480; // 4分音符 = 480 tick

  // ---------- コード解析 ----------
  const ROOTS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
  const SHARP = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  const FLAT = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
  const QUALITIES = {
    '': [0, 4, 7], m: [0, 3, 7], 7: [0, 4, 7, 10], maj7: [0, 4, 7, 11], m7: [0, 3, 7, 10],
    dim: [0, 3, 6], aug: [0, 4, 8], sus4: [0, 5, 7], sus2: [0, 2, 7], 6: [0, 4, 7, 9],
    m6: [0, 3, 7, 9], 9: [0, 4, 7, 10, 14], maj9: [0, 4, 7, 11, 14], m9: [0, 3, 7, 10, 14],
    add9: [0, 4, 7, 14], m7b5: [0, 3, 6, 10], dim7: [0, 3, 6, 9], '7sus4': [0, 5, 7, 10],
    mMaj7: [0, 3, 7, 11],
  };
  const ALIASES = { M: '', maj: '', min: 'm', '-': 'm', M7: 'maj7', '△7': 'maj7', '°': 'dim', '°7': 'dim7', ø: 'm7b5', '+': 'aug', mM7: 'mMaj7', '-7': 'm7' };
  const mod = (n, m) => ((n % m) + m) % m;
  const acc = (s) => (s === '#' || s === '♯' ? 1 : s === 'b' || s === '♭' ? -1 : 0);

  function parseChord(str) {
    const m = /^([A-G])([#b♯♭]?)([^/]*)(?:\/([A-G])([#b♯♭]?))?$/.exec(String(str).trim());
    if (!m) return null;
    let q = m[3];
    if (ALIASES[q] !== undefined) q = ALIASES[q];
    if (!QUALITIES[q]) return null;
    return {
      root: mod(ROOTS[m[1]] + acc(m[2]), 12),
      quality: q,
      bass: m[4] ? mod(ROOTS[m[4]] + acc(m[5]), 12) : null,
      flat: m[2] === 'b' || m[2] === '♭' || m[5] === 'b' || m[5] === '♭',
    };
  }
  const pcName = (pc, flat) => (flat ? FLAT : SHARP)[mod(pc, 12)];
  const preferFlat = (pc) => [1, 3, 8, 10].includes(mod(pc, 12));
  function formatChord(c, flat) {
    return pcName(c.root, flat) + c.quality + (c.bass != null ? '/' + pcName(c.bass, flat) : '');
  }
  function transposeChord(name, n) {
    const c = parseChord(name);
    if (!c) return name;
    const flat = c.flat || preferFlat(c.root + n);
    return formatChord({ ...c, root: mod(c.root + n, 12), bass: c.bass == null ? null : mod(c.bass + n, 12) }, flat);
  }
  function withQuality(name, quality) {
    const c = parseChord(name);
    if (!c) return name;
    return formatChord({ ...c, quality: c.quality === quality ? '' : quality }, c.flat);
  }

  // ベース音（オンコード）の付け外し。同じ音をもう一度指定すると外す
  function withBass(name, pc) {
    const c = parseChord(name);
    if (!c) return name;
    const bass = pc == null || c.bass === pc || pc === c.root ? null : pc;
    return formatChord({ ...c, bass }, c.flat || preferFlat(pc == null ? 0 : pc));
  }

  // キーから対角線上のダイアトニックコードを返す
  function diatonicChords(key) {
    const k = parseChord(key) || parseChord('C');
    const minor = k.quality === 'm';
    const steps = minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11];
    const quals = minor ? ['m', 'dim', '', 'm', 'm', '', ''] : ['', 'm', 'm', '', '', 'm', 'dim'];
    const flat = k.flat || preferFlat(minor ? k.root + 3 : k.root) || (!minor && k.root === 5);
    return steps.map((s, i) => pcName(k.root + s, flat) + quals[i]);
  }

  // ---------- スケッチ ----------
  let idSeq = 0;
  const newId = () => 's' + Date.now().toString(36) + (idSeq++).toString(36) + Math.random().toString(36).slice(2, 5);
  function newSketch(title = '無題') {
    return {
      id: newId(), title, tempo: 120, timeSig: [4, 4], key: 'C', bars: 4,
      chords: [], notes: [], pattern: 'block', memo: '', updatedAt: Date.now(),
    };
  }
  const barTicks = (s) => (PPQ * 4 * s.timeSig[0]) / s.timeSig[1];
  const beatTicks = (s) => (PPQ * 4) / s.timeSig[1];
  function extentTicks(s) {
    let e = 0;
    for (const x of s.chords) e = Math.max(e, x.pos + x.dur);
    for (const x of s.notes) e = Math.max(e, x.pos + x.dur);
    return e;
  }
  const lengthBars = (s) => Math.max(1, s.bars || 0, Math.ceil(extentTicks(s) / barTicks(s)));

  // 「C | Am Dm | F | G」→ chords/bars
  function parseProgression(text, s) {
    const bt = barTicks(s);
    let segs = text.split('|').map((x) => x.trim());
    while (segs.length && segs[0] === '') segs.shift();
    while (segs.length && segs[segs.length - 1] === '') segs.pop();
    const chords = [];
    const errors = [];
    segs.forEach((seg, bar) => {
      const toks = seg.split(/\s+/).filter(Boolean);
      toks.forEach((tok, i) => {
        if (!parseChord(tok)) { errors.push(tok); return; }
        const pos = bar * bt + Math.round((bt * i) / toks.length);
        const end = bar * bt + Math.round((bt * (i + 1)) / toks.length);
        chords.push({ pos, dur: end - pos, chord: tok });
      });
    });
    return { chords, bars: Math.max(1, segs.length), errors };
  }
  function formatProgression(s) {
    const bt = barTicks(s);
    const out = [];
    for (let b = 0; b < lengthBars(s); b++) {
      out.push(s.chords.filter((c) => Math.floor(c.pos / bt) === b).map((c) => c.chord).join(' '));
    }
    return out.join(' | ');
  }

  // ---------- 編集コマンド（小節番号は1始まり・終端含む。Concept.md §8 に合わせる） ----------
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const fail = (m) => { throw new Error(m); };
  const int = (v, name, min = 0) => (Number.isInteger(v) && v >= min ? v : fail(`${name} が不正です: ${v}`));

  function extract(d, t0, t1) {
    const pick = (arr) => arr.filter((e) => e.pos >= t0 && e.pos < t1).map((e) => ({ ...e, pos: e.pos - t0, dur: Math.min(e.dur, t1 - e.pos) }));
    return { chords: pick(d.chords), notes: pick(d.notes) };
  }
  function insertSpace(d, t, len) {
    const total = lengthBars(d); // 移動前の長さ（移動後に測ると二重加算になる）
    for (const arr of [d.chords, d.notes]) {
      for (const e of arr) {
        if (e.pos < t && e.pos + e.dur > t) e.dur = t - e.pos;
        else if (e.pos >= t) e.pos += len;
      }
    }
    d.bars = total + len / barTicks(d);
  }
  function removeSpace(d, t0, t1) {
    const len = t1 - t0;
    const keep = (arr) => arr.filter((e) => !(e.pos >= t0 && e.pos < t1)).map((e) => {
      if (e.pos < t0 && e.pos + e.dur > t0) e.dur = t0 - e.pos;
      else if (e.pos >= t1) e.pos -= len;
      return e;
    });
    const total = lengthBars(d);
    d.chords = keep(d.chords);
    d.notes = keep(d.notes);
    d.bars = Math.max(1, total - len / barTicks(d));
  }
  function place(d, block, at) {
    for (const c of block.chords) d.chords.push({ ...c, pos: c.pos + at });
    for (const n of block.notes) d.notes.push({ ...n, pos: n.pos + at });
  }
  function range(d, cmd) {
    const bt = barTicks(d);
    const a = int(cmd.startBar, 'startBar', 1), b = int(cmd.endBar, 'endBar', a);
    return { t0: (a - 1) * bt, t1: b * bt, a, b };
  }
  // コードを置くとき、重なる既存コードを切り詰める/消す
  function placeChord(d, pos, dur, chord) {
    const end = pos + dur;
    d.chords = d.chords.filter((c) => !(c.pos >= pos && c.pos + c.dur <= end)).map((c) => {
      if (c.pos < pos && c.pos + c.dur > pos) return { ...c, dur: pos - c.pos };
      if (c.pos >= pos && c.pos < end) return { ...c, dur: c.pos + c.dur - end, pos: end };
      return c;
    });
    d.chords.push({ pos, dur, chord });
  }
  const needChord = (name) => parseChord(name) ? name : fail(`コードを解釈できません: ${name}`);

  const COMMANDS = {
    setChords(d, { text }) {
      const r = parseProgression(text, d);
      if (r.errors.length) fail(`コードを解釈できません: ${r.errors.join(', ')}`);
      d.chords = r.chords;
      d.bars = r.bars;
    },
    insertChord(d, { pos, dur, chord }) { placeChord(d, int(pos, 'pos'), int(dur, 'dur', 1), needChord(chord)); },
    changeChord(d, { index, chord }) {
      const c = d.chords[index] || fail(`コードがありません: ${index}`);
      c.chord = needChord(chord);
    },
    deleteChord(d, { index }) {
      if (!d.chords[index]) fail(`コードがありません: ${index}`);
      d.chords.splice(index, 1);
    },
    insertBars(d, { atBar, count = 1 }) {
      int(atBar, 'atBar', 1); int(count, 'count', 1);
      insertSpace(d, (atBar - 1) * barTicks(d), count * barTicks(d));
    },
    deleteBars(d, cmd) { const r = range(d, cmd); removeSpace(d, r.t0, r.t1); },
    copyBars(d, cmd) {
      const r = range(d, cmd);
      const at = (int(cmd.insertAtBar, 'insertAtBar', 1) - 1) * barTicks(d);
      const block = extract(d, r.t0, r.t1);
      insertSpace(d, at, r.t1 - r.t0);
      place(d, block, at);
    },
    repeatBars(d, cmd) {
      const src = cmd.source || cmd;
      const r = range(d, src);
      const n = int(cmd.repeatCount, 'repeatCount', 1);
      const len = r.t1 - r.t0;
      const at = (int(cmd.insertAtBar, 'insertAtBar', 1) - 1) * barTicks(d);
      const block = extract(d, r.t0, r.t1);
      insertSpace(d, at, len * n);
      for (let i = 0; i < n; i++) place(d, block, at + len * i);
    },
    // toBar: 移動後にブロックの先頭が来る小節番号（ブロックを抜いた後の並びで数える）
    moveBars(d, cmd) {
      const r = range(d, cmd);
      const len = r.t1 - r.t0;
      const block = extract(d, r.t0, r.t1);
      const at = (int(cmd.toBar, 'toBar', 1) - 1) * barTicks(d);
      removeSpace(d, r.t0, r.t1);
      insertSpace(d, at, len);
      place(d, block, at);
    },
    insertNote(d, { pitch, pos, dur, vel = 90 }) {
      d.notes.push({ pitch: int(pitch, 'pitch'), pos: int(pos, 'pos'), dur: int(dur, 'dur', 1), vel });
    },
    // メロディは単旋律として置く: 範囲内で始まる音は置き換え、手前から伸びる音は切り詰める
    putNote(d, { pitch, pos, dur, vel = 90 }) {
      int(pitch, 'pitch'); int(pos, 'pos'); int(dur, 'dur', 1);
      const end = pos + dur;
      d.notes = d.notes
        .filter((n) => !(n.pos >= pos && n.pos < end))
        .map((n) => (n.pos < pos && n.pos + n.dur > pos ? { ...n, dur: pos - n.pos } : n));
      d.notes.push({ pitch, pos, dur, vel });
    },
    changeNote(d, { index, ...fields }) {
      const n = d.notes[index] || fail(`ノートがありません: ${index}`);
      for (const k of ['pitch', 'pos', 'dur', 'vel']) if (fields[k] !== undefined) n[k] = fields[k];
    },
    deleteNote(d, { index }) {
      if (!d.notes[index]) fail(`ノートがありません: ${index}`);
      d.notes.splice(index, 1);
    },
    // target: 'all' | 'chords' | 'notes'
    transpose(d, { semitones, target = 'all' }) {
      int(semitones + 1000, 'semitones');
      if (target !== 'notes') {
        d.chords.forEach((c) => { c.chord = transposeChord(c.chord, semitones); });
        if (target === 'all') {
          const k = parseChord(d.key);
          if (k) d.key = formatChord({ ...k, root: mod(k.root + semitones, 12) }, preferFlat(k.root + semitones));
        }
      }
      if (target !== 'chords') d.notes.forEach((n) => { n.pitch += semitones; });
    },
    setTempo(d, { tempo }) { d.tempo = Math.min(300, Math.max(30, int(tempo, 'tempo', 1))); },
    setTimeSig(d, { num, den }) {
      if (![2, 4, 8].includes(den) || num < 1 || num > 12) fail('拍子が不正です');
      const oldBt = barTicks(d); // 小節数を保ったまま再配置はしない（位置はtickのまま）
      d.timeSig = [num, den];
      d.bars = Math.max(1, Math.ceil((d.bars * oldBt) / barTicks(d)));
    },
    setKey(d, { key }) { if (!parseChord(key)) fail('キーが不正です'); d.key = key; },
    setPattern(d, { pattern }) { if (!PATTERNS[pattern]) fail('伴奏パターンが不正です'); d.pattern = pattern; },
    setTitle(d, { title }) { d.title = String(title); },
    setMemo(d, { text }) { d.memo = String(text); },
  };

  function applyCommand(sketch, cmd) {
    const fn = COMMANDS[cmd.command] || fail(`未知のコマンド: ${cmd.command}`);
    const d = clone(sketch);
    fn(d, cmd);
    d.chords.sort((a, b) => a.pos - b.pos);
    d.notes.sort((a, b) => a.pos - b.pos || a.pitch - b.pitch);
    d.bars = lengthBars(d);
    d.updatedAt = Date.now();
    return d;
  }

  // UIもAIもここを通す。配列はひとつのトランザクション（Undo 1回で戻る）。
  class Store {
    constructor(sketch = newSketch()) {
      this.sketch = sketch; this.undoStack = []; this.redoStack = []; this.listeners = new Set();
    }
    load(sketch) { this.sketch = sketch; this.undoStack = []; this.redoStack = []; this._emit(); }
    subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
    _emit() { this.listeners.forEach((f) => f(this.sketch)); }
    dispatch(cmd) {
      const cmds = Array.isArray(cmd) ? cmd : [cmd];
      let next = this.sketch;
      for (const c of cmds) next = applyCommand(next, c); // 途中で失敗したら何も変えない
      this.undoStack.push(this.sketch);
      this.redoStack = [];
      this.sketch = next;
      this._emit();
    }
    undo() { if (!this.undoStack.length) return; this.redoStack.push(this.sketch); this.sketch = this.undoStack.pop(); this._emit(); }
    redo() { if (!this.redoStack.length) return; this.undoStack.push(this.sketch); this.sketch = this.redoStack.pop(); this._emit(); }
    get canUndo() { return this.undoStack.length > 0; }
    get canRedo() { return this.redoStack.length > 0; }
    // 読み取りAPI
    getSketch() { return this.sketch; }
    getChords() { return this.sketch.chords; }
    getNotes() { return this.sketch.notes; }
    getSongStructure() {
      const s = this.sketch, bt = barTicks(s);
      return Array.from({ length: lengthBars(s) }, (_, i) => ({
        bar: i + 1,
        chords: s.chords.filter((c) => Math.floor(c.pos / bt) === i).map((c) => c.chord),
      }));
    }
  }

  // ---------- 伴奏生成 ----------
  // 直前のボイシングに近い転回形を選ぶ
  function voicing(chord, prev) {
    const c = parseChord(chord);
    if (!c) return [];
    const base = c.root;
    const tones = QUALITIES[c.quality].map((i) => base + i); // 昇順
    let best = null, bestScore = Infinity;
    for (let inv = 0; inv < tones.length; inv++) {
      const rot = tones.slice(inv).concat(tones.slice(0, inv).map((t) => t + 12));
      let lo = rot[0];
      while (lo < 55) { rot.forEach((_, i) => { rot[i] += 12; }); lo = rot[0]; }
      while (lo > 66) { rot.forEach((_, i) => { rot[i] -= 12; }); lo = rot[0]; }
      const avg = rot.reduce((a, b) => a + b, 0) / rot.length;
      const score = Math.abs(avg - (prev ? prev.reduce((a, b) => a + b, 0) / prev.length : 63));
      if (score < bestScore) { bestScore = score; best = rot.slice(); }
    }
    return best;
  }
  const bassPitch = (chord) => {
    const c = parseChord(chord);
    return 36 + mod((c.bass != null ? c.bass : c.root) - 36, 12);
  };

  const PATTERNS = {
    block(s, ch, v, out) {
      out.push({ pitch: bassPitch(ch.chord), pos: ch.pos, dur: ch.dur, vel: 80, track: 'bass' });
      v.forEach((p) => out.push({ pitch: p, pos: ch.pos, dur: ch.dur, vel: 70, track: 'chord' }));
    },
    arpeggio(s, ch, v, out) {
      out.push({ pitch: bassPitch(ch.chord), pos: ch.pos, dur: ch.dur, vel: 80, track: 'bass' });
      const seq = v.length > 2 ? v.concat(v.slice(1, -1).reverse()) : v;
      const step = PPQ / 2;
      for (let t = 0, i = 0; t < ch.dur; t += step, i++) {
        out.push({ pitch: seq[i % seq.length], pos: ch.pos + t, dur: Math.min(step * 2, ch.dur - t), vel: 64, track: 'chord' });
      }
    },
    rhythm(s, ch, v, out) {
      out.push({ pitch: bassPitch(ch.chord), pos: ch.pos, dur: beatTicks(s), vel: 80, track: 'bass' });
      const mask = [1, 0, 1, 1, 1, 0, 1, 1];
      const step = PPQ / 2;
      for (let t = 0, i = 0; t < ch.dur; t += step, i++) {
        if (!mask[i % 8]) continue;
        v.forEach((p) => out.push({ pitch: p, pos: ch.pos + t, dur: Math.min(step * 0.9, ch.dur - t), vel: i % 2 ? 56 : 72, track: 'chord' }));
      }
    },
    bassChord(s, ch, v, out) {
      const c = parseChord(ch.chord);
      const bt = beatTicks(s);
      const root = bassPitch(ch.chord);
      const fifth = c.bass != null ? root : root + (c.quality.startsWith('dim') || c.quality === 'm7b5' ? 6 : 7);
      for (let t = 0, i = 0; t < ch.dur; t += bt, i++) {
        const len = Math.min(bt, ch.dur - t);
        if (i % 2 === 0) out.push({ pitch: i % 4 === 0 ? root : fifth, pos: ch.pos + t, dur: len, vel: 82, track: 'bass' });
        else v.forEach((p) => out.push({ pitch: p, pos: ch.pos + t, dur: len * 0.9, vel: 66, track: 'chord' }));
      }
    },
  };
  const PATTERN_LABELS = { block: 'Block Chord', arpeggio: 'Arpeggio', rhythm: 'Rhythm Chord', bassChord: 'Bass + Chord' };

  function renderAccompaniment(s) {
    const out = [];
    let prev = null;
    for (const ch of s.chords) {
      const v = voicing(ch.chord, prev);
      if (!v.length) continue;
      prev = v;
      PATTERNS[s.pattern](s, ch, v, out);
    }
    return out;
  }
  function renderPlayback(s) {
    const mel = s.notes.map((n) => ({ ...n, track: 'melody' }));
    return renderAccompaniment(s).concat(mel).sort((a, b) => a.pos - b.pos);
  }
  // 単発試聴用（パレットのコードをタップしたとき）
  function renderPreview(s, chord) {
    const t = { ...s, chords: [{ pos: 0, dur: barTicks(s), chord }], notes: [], bars: 1 };
    return renderAccompaniment(t);
  }

  const api = {
    PPQ, QUALITIES, PATTERN_LABELS, parseChord, formatChord, transposeChord, withQuality, withBass, pcName, bassPitch, diatonicChords,
    newSketch, barTicks, beatTicks, lengthBars, parseProgression, formatProgression,
    applyCommand, Store, voicing, renderAccompaniment, renderPlayback, renderPreview,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.Core = api;
})(typeof window !== 'undefined' ? window : globalThis);
