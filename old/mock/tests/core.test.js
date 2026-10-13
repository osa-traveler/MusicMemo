const test = require('node:test');
const assert = require('node:assert/strict');
const C = require('../core.js');

const mk = (text) => {
  const store = new C.Store(C.newSketch('t'));
  store.dispatch({ command: 'setChords', text });
  return store;
};
const prog = (store) => C.formatProgression(store.sketch);

test('コード解析', () => {
  assert.deepEqual(C.parseChord('Am7'), { root: 9, quality: 'm7', bass: null, flat: false });
  assert.equal(C.parseChord('C/E').bass, 4);
  assert.equal(C.parseChord('Bbmaj7').root, 10);
  assert.equal(C.parseChord('H'), null);
  assert.equal(C.parseChord('Cfoo'), null);
});

test('進行テキストの往復と小節内分割', () => {
  const s = mk('| C | Am Dm | F | G |');
  assert.equal(s.sketch.bars, 4);
  assert.equal(prog(s), 'C | Am Dm | F | G');
  assert.equal(s.sketch.chords[1].dur, 960);
  assert.throws(() => s.dispatch({ command: 'setChords', text: 'C | Xyz' }), /Xyz/);
  assert.equal(prog(s), 'C | Am Dm | F | G'); // 失敗時は変更なし
});

test('空小節を含む未完成スケッチ', () => {
  const s = mk('C | | G');
  assert.equal(C.lengthBars(s.sketch), 3);
  assert.deepEqual(s.getSongStructure().map((b) => b.chords), [['C'], [], ['G']]);
});

test('repeatBars（Concept.mdの例）', () => {
  const s = mk('C | Am | F | G');
  s.dispatch({ command: 'repeatBars', source: { startBar: 1, endBar: 4 }, repeatCount: 2, insertAtBar: 5 });
  assert.equal(prog(s), 'C | Am | F | G | C | Am | F | G | C | Am | F | G');
});

test('copyBars は挿入（後続は後ろへ）', () => {
  const s = mk('C | Am | F | G');
  s.dispatch({ command: 'copyBars', startBar: 1, endBar: 2, insertAtBar: 2 });
  assert.equal(prog(s), 'C | C | Am | Am | F | G');
});

test('deleteBars / insertBars', () => {
  const s = mk('C | Am | F | G');
  s.dispatch({ command: 'deleteBars', startBar: 2, endBar: 3 });
  assert.equal(prog(s), 'C | G');
  s.dispatch({ command: 'insertBars', atBar: 2, count: 1 });
  assert.equal(prog(s), 'C |  | G'); // 空小節は空文字で表現
});

test('moveBars', () => {
  const s = mk('C | Am | F | G');
  s.dispatch({ command: 'moveBars', startBar: 4, endBar: 4, toBar: 1 });
  assert.equal(prog(s), 'G | C | Am | F');
  s.dispatch({ command: 'moveBars', startBar: 1, endBar: 1, toBar: 2 });
  assert.equal(prog(s), 'C | G | Am | F');
});

test('小節操作はメロディも一緒に動く', () => {
  const s = mk('C | G');
  s.dispatch({ command: 'insertNote', pitch: 72, pos: 1920, dur: 480 });
  s.dispatch({ command: 'moveBars', startBar: 2, endBar: 2, toBar: 1 });
  assert.equal(s.sketch.notes[0].pos, 0);
});

test('putNote は単旋律として置き換え・切り詰め', () => {
  const s = mk('C | G');
  s.dispatch({ command: 'putNote', pitch: 60, pos: 0, dur: 960 });
  s.dispatch({ command: 'putNote', pitch: 62, pos: 480, dur: 480 }); // 60を480に切り詰め
  assert.deepEqual(s.sketch.notes.map((n) => [n.pitch, n.pos, n.dur]), [[60, 0, 480], [62, 480, 480]]);
  s.dispatch({ command: 'putNote', pitch: 64, pos: 0, dur: 960 }); // 範囲内の2音を置き換え
  assert.deepEqual(s.sketch.notes.map((n) => [n.pitch, n.pos, n.dur]), [[64, 0, 960]]);
});

test('changeChord / insertChord / deleteChord', () => {
  const s = mk('C | Am | F | G');
  s.dispatch({ command: 'changeChord', index: 3, chord: 'G7' });
  assert.equal(prog(s), 'C | Am | F | G7');
  s.dispatch({ command: 'insertChord', pos: 960, dur: 960, chord: 'Dm7' });
  assert.equal(prog(s), 'C Dm7 | Am | F | G7'); // 重なるCは半分に切り詰め
  s.dispatch({ command: 'deleteChord', index: 0 });
  assert.equal(prog(s), 'Dm7 | Am | F | G7');
  assert.throws(() => s.dispatch({ command: 'changeChord', index: 0, chord: 'Q' }));
});

test('transpose', () => {
  const s = mk('C | Am | Bb | G/B');
  s.dispatch({ command: 'transpose', semitones: 2, target: 'chords' });
  assert.equal(prog(s), 'D | Bm | C | A/C#');
  s.dispatch({ command: 'transpose', semitones: -2, target: 'chords' });
  assert.equal(prog(s), 'C | Am | Bb | G/B');
});

test('Undo / Redo とトランザクション', () => {
  const s = mk('C | Am');
  s.dispatch([
    { command: 'changeChord', index: 0, chord: 'F' },
    { command: 'changeChord', index: 1, chord: 'G' },
  ]);
  assert.equal(prog(s), 'F | G');
  s.undo();
  assert.equal(prog(s), 'C | Am'); // 1回で両方戻る
  s.redo();
  assert.equal(prog(s), 'F | G');
  assert.throws(() => s.dispatch([{ command: 'changeChord', index: 0, chord: 'C' }, { command: 'nope' }]));
  assert.equal(prog(s), 'F | G'); // 全体ロールバック
});

test('ダイアトニックコード', () => {
  assert.deepEqual(C.diatonicChords('C'), ['C', 'Dm', 'Em', 'F', 'G', 'Am', 'Bdim']);
  assert.deepEqual(C.diatonicChords('F'), ['F', 'Gm', 'Am', 'Bb', 'C', 'Dm', 'Edim']);
  assert.deepEqual(C.diatonicChords('Am'), ['Am', 'Bdim', 'C', 'Dm', 'Em', 'F', 'G']);
});

test('伴奏: 全パターンが範囲内の音を出す', () => {
  for (const pattern of Object.keys(C.PATTERN_LABELS)) {
    const s = mk('C | Am | F | G');
    s.dispatch({ command: 'setPattern', pattern });
    const notes = C.renderAccompaniment(s.sketch);
    assert.ok(notes.length >= 4, pattern);
    const total = C.lengthBars(s.sketch) * C.barTicks(s.sketch);
    for (const n of notes) {
      assert.ok(n.pos >= 0 && n.pos + n.dur <= total + 1, `${pattern} 範囲外`);
      assert.ok(n.pitch >= 30 && n.pitch <= 90, `${pattern} 音域外 ${n.pitch}`);
    }
  }
});

test('ボイシング: Cコードの構成音', () => {
  const v = C.voicing('C');
  assert.deepEqual(v.map((p) => p % 12).sort((a, b) => a - b), [0, 4, 7]);
});

test('オンコード（ベース指定）', () => {
  const s = mk('C/D | Am/G | C/E');
  assert.equal(prog(s), 'C/D | Am/G | C/E');
  assert.equal(C.withBass('C', 2), 'C/D');
  assert.equal(C.withBass('C/D', 2), 'C');     // 同じ音で解除
  assert.equal(C.withBass('C', 0), 'C');       // ルートと同じなら付けない
  assert.equal(C.withBass('Am7', 10), 'Am7/Bb');
  assert.equal(C.parseChord('C/D').bass, 2);
  const bass = C.renderAccompaniment(s.sketch).filter((n) => n.track === 'bass')[0];
  assert.equal(bass.pitch % 12, 2); // ベース音はD
});
