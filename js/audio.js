// Tiny WebAudio engine note for the 899 cc four-cylinder, plus pit-radio beeps.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});

  class EngineAudio {
    constructor() {
      this.ctx = null;
      this.muted = false;
    }
    start() {
      if (this.ctx) {
        this.ctx.resume();
        return;
      }
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      const ctx = (this.ctx = new AC());
      this.master = ctx.createGain();
      this.master.gain.value = this.muted ? 0 : 0.5;
      this.master.connect(ctx.destination);
      this.filter = ctx.createBiquadFilter();
      this.filter.type = 'lowpass';
      this.filter.frequency.value = 900;
      this.filter.Q.value = 3;
      this.gain = ctx.createGain();
      this.gain.gain.value = 0;
      this.o1 = ctx.createOscillator();
      this.o1.type = 'sawtooth';
      this.o2 = ctx.createOscillator();
      this.o2.type = 'square';
      const g2 = ctx.createGain();
      g2.gain.value = 0.35;
      this.o1.connect(this.filter);
      this.o2.connect(g2).connect(this.filter);
      this.filter.connect(this.gain).connect(this.master);
      this.o1.start();
      this.o2.start();
      // tyre squeal: filtered noise
      const buf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const data = buf.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      this.noise = ctx.createBufferSource();
      this.noise.buffer = buf;
      this.noise.loop = true;
      const bp = ctx.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 1400;
      bp.Q.value = 8;
      this.squeal = ctx.createGain();
      this.squeal.gain.value = 0;
      this.noise.connect(bp).connect(this.squeal).connect(this.master);
      this.noise.start();
    }
    update(car, active) {
      if (!this.ctx) return;
      const t = this.ctx.currentTime;
      const f = Math.max(20, (car.rpm / 60) * 2); // 4-cylinder: two firing pulses per revolution
      this.o1.frequency.setTargetAtTime(f, t, 0.03);
      this.o2.frequency.setTargetAtTime(f / 2, t, 0.03);
      this.filter.frequency.setTargetAtTime(500 + car.throttle * 1400 + car.rpm * 0.15, t, 0.05);
      const vol = active ? 0.06 + 0.12 * car.throttle : 0;
      this.gain.gain.setTargetAtTime(vol, t, 0.05);
      const sq = active ? Math.min(0.12, Math.max(0, (car.understeer - 1) * 0.08) + Math.max(0, car.slip - 0.6) * 0.05) : 0;
      this.squeal.gain.setTargetAtTime(sq, t, 0.05);
    }
    beep(freq = 880, dur = 0.12, times = 2) {
      if (!this.ctx || this.muted) return;
      for (let i = 0; i < times; i++) {
        const o = this.ctx.createOscillator();
        const g = this.ctx.createGain();
        o.frequency.value = freq;
        o.type = 'square';
        const t0 = this.ctx.currentTime + i * dur * 1.6;
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.exponentialRampToValueAtTime(0.15, t0 + 0.01);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
        o.connect(g).connect(this.master);
        o.start(t0);
        o.stop(t0 + dur + 0.05);
      }
    }
    toggleMute() {
      this.muted = !this.muted;
      if (this.master) this.master.gain.value = this.muted ? 0 : 0.5;
      return this.muted;
    }
  }

  SC.EngineAudio = EngineAudio;
})();
