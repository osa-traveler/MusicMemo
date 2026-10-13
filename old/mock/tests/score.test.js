const test = require('node:test');
const assert = require('node:assert/strict');
globalThis.Core = require('../core.js');
const S = require('../score.js');

test('調号', () => {
  assert.equal(S.keySig('C'), 0);
  assert.equal(S.keySig('G'), 1);
  assert.equal(S.keySig('F'), -1);
  assert.equal(S.keySig('Am'), 0);
  assert.equal(S.keySig('Dm'), -1);
});

test('五線位置と臨時記号', () => {
  assert.deepEqual(S.spell(64, 0), { step: 30, show: null }); // E4 第1線
  assert.deepEqual(S.spell(60, 0), { step: 28, show: null }); // C4 下第1加線
  assert.deepEqual(S.spell(66, 1), { step: 31, show: null }); // G調のF#4は調号どおり
  assert.deepEqual(S.spell(65, 1), { step: 31, show: 0 });    // F4はナチュラル
  assert.deepEqual(S.spell(61, 0), { step: 28, show: 1 });    // C#4
  assert.deepEqual(S.spell(70, 0), { step: 34, show: -1 });   // Bb4
});

test('step から求めた音高は元の音高と半音以内', () => {
  for (const n of [0, 1, -2]) for (let p = 50; p < 85; p++) {
    assert.ok(Math.abs(p - S.pitchOf(S.spell(p, n).step, n, 0)) <= 1, `p=${p} n=${n}`);
  }
});
