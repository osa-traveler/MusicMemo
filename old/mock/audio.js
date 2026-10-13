// Web Audio による簡易ピアノ風音源（SwiftではAVAudioEngine + AVAudioUnitSamplerに対応）。
(function (root) {
  const { PPQ } = root.Core;

  class Player {
    constructor() { this.ctx = null; this.run = null; this.buses = []; }

    _ensure() {
      if (!this.ctx) this.ctx = new (root.AudioContext || root.webkitAudioContext)();
      if (this.ctx.state === 'suspended') this.ctx.resume();
    }

    _bus() {
      const master = this.ctx.createGain();
      master.gain.value = 0.5;
      const comp = this.ctx.createDynamicsCompressor();
      master.connect(comp);
      comp.connect(this.ctx.destination);
      const bus = { master, comp, oscs: [] };
      this.buses.push(bus);
      return bus;
    }

    _voice(bus, pitch, t, dur, vel) {
      const ctx = this.ctx;
      const f = 440 * Math.pow(2, (pitch - 69) / 12);
      const o1 = ctx.createOscillator(); o1.type = 'triangle'; o1.frequency.value = f;
      const o2 = ctx.createOscillator(); o2.type = 'sine'; o2.frequency.value = f * 2;
      const g2 = ctx.createGain(); g2.gain.value = 0.25;
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = Math.min(9000, f * 5 + 600);
      const env = ctx.createGain();
      const peak = 0.28 * (vel / 127);
      const hold = Math.max(dur, 0.12);
      env.gain.setValueAtTime(0.0001, t);
      env.gain.linearRampToValueAtTime(peak, t + 0.008);
      env.gain.exponentialRampToValueAtTime(peak * 0.25, t + hold);
      env.gain.exponentialRampToValueAtTime(0.0001, t + hold + 0.25);
      o1.connect(lp); o2.connect(g2); g2.connect(lp); lp.connect(env); env.connect(bus.master);
      o1.start(t); o2.start(t);
      o1.stop(t + hold + 0.3); o2.stop(t + hold + 0.3);
      bus.oscs.push(o1, o2);
    }

    _schedule(notes, tempo, t0) {
      const bus = this._bus();
      const sec = (ticks) => (ticks * 60) / (tempo * PPQ);
      for (const n of notes) this._voice(bus, n.pitch, t0 + sec(n.pos), sec(n.dur), n.vel ?? 90);
    }

    get playing() { return !!this.run; }

    // getSketch: 毎ループ最新のスケッチを取り直す（再生中の編集が次の周回で反映される）
    start(getSketch, { loop = false, onEnd } = {}) {
      this.stop();
      this._ensure();
      const run = { loop, onEnd, getSketch, stopped: false, t0: 0, tempo: 120, timer: null };
      this.run = run;
      this._pass(run, this.ctx.currentTime + 0.08);
    }

    _pass(run, t0) {
      const s = run.getSketch();
      const total = Root.lengthTicks(s);
      run.t0 = t0; run.tempo = s.tempo;
      this._schedule(root.Core.renderPlayback(s), s.tempo, t0);
      const dur = (total * 60) / (s.tempo * PPQ);
      const wait = (t0 + dur - this.ctx.currentTime) * 1000;
      run.timer = setTimeout(() => {
        if (run.stopped) return;
        if (run.loop) this._pass(run, t0 + dur);
        else { this.stop(); run.onEnd && run.onEnd(); }
      }, Math.max(0, wait - (run.loop ? 60 : -250)));
    }

    // 現在の周回内の位置（tick）。停止中はnull
    position() {
      if (!this.run) return null;
      const ticks = ((this.ctx.currentTime - this.run.t0) * this.run.tempo * PPQ) / 60;
      return Math.max(0, ticks);
    }

    stop() {
      if (this.run) { this.run.stopped = true; clearTimeout(this.run.timer); this.run = null; }
      if (!this.ctx) return;
      const now = this.ctx.currentTime;
      for (const b of this.buses) {
        b.master.gain.cancelScheduledValues(now);
        b.master.gain.setTargetAtTime(0, now, 0.015);
        b.oscs.forEach((o) => { try { o.stop(now + 0.08); } catch (e) { /* 既に停止 */ } });
        setTimeout(() => b.master.disconnect(), 300);
      }
      this.buses = [];
    }

    preview(notes, tempo) {
      this._ensure();
      this._schedule(notes, tempo, this.ctx.currentTime + 0.03);
    }
  }

  const Root = { lengthTicks: (s) => root.Core.lengthBars(s) * root.Core.barTicks(s) };
  root.Player = Player;
})(window);
