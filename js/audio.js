// Procedural rally audio for the 899 cc four-cylinder. No external sound files required.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});

  class EngineAudio {
    constructor() {
      this.ctx = null;
      this.muted = false;
      this.lastGear = null;
      this.lastShift = 0;
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
      this.master.gain.value = this.muted ? 0 : 0.42;
      this.master.connect(ctx.destination);

      // A layered, slightly rough four-cylinder note: firing pulse, lower body and exhaust rasp.
      this.engineFilter = ctx.createBiquadFilter();
      this.engineFilter.type = 'lowpass';
      this.engineFilter.frequency.value = 1000;
      this.engineFilter.Q.value = 1.1;
      this.engineGain = ctx.createGain();
      this.engineGain.gain.value = 0;
      this.engineFilter.connect(this.engineGain).connect(this.master);
      this.oscillators = [];
      [1, 2, 3, 4].forEach((multiple, i) => {
        const osc = ctx.createOscillator();
        const level = ctx.createGain();
        osc.type = i === 0 ? 'sawtooth' : (i === 1 ? 'triangle' : 'square');
        level.gain.value = [0.62, 0.22, 0.075, 0.035][i];
        osc.connect(level).connect(this.engineFilter);
        osc.start();
        this.oscillators.push({ osc, multiple });
      });

      // Continuous filtered exhaust/induction noise adds texture without a harsh synthesized buzz.
      const noiseBuffer = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const noiseData = noiseBuffer.getChannelData(0);
      for (let i = 0; i < noiseData.length; i++) noiseData[i] = Math.random() * 2 - 1;
      this.noise = ctx.createBufferSource();
      this.noise.buffer = noiseBuffer;
      this.noise.loop = true;
      this.exhaustFilter = ctx.createBiquadFilter();
      this.exhaustFilter.type = 'bandpass';
      this.exhaustFilter.frequency.value = 650;
      this.exhaustFilter.Q.value = 0.7;
      this.exhaustGain = ctx.createGain();
      this.exhaustGain.gain.value = 0;
      this.noise.connect(this.exhaustFilter).connect(this.exhaustGain).connect(this.master);
      this.noise.start();

      const squealFilter = ctx.createBiquadFilter();
      squealFilter.type = 'bandpass';
      squealFilter.frequency.value = 1550;
      squealFilter.Q.value = 5;
      this.squeal = ctx.createGain();
      this.squeal.gain.value = 0;
      this.noise.connect(squealFilter).connect(this.squeal).connect(this.master);

      const limiterFilter = ctx.createBiquadFilter();
      limiterFilter.type = 'highpass';
      limiterFilter.frequency.value = 900;
      this.limiterGain = ctx.createGain();
      this.limiterGain.gain.value = 0;
      this.noise.connect(limiterFilter).connect(this.limiterGain).connect(this.master);
    }
    update(car, active) {
      if (!this.ctx) return;
      const t = this.ctx.currentTime;
      const rpm = Math.max(750, car.rpm || 750);
      // Two firing events per crank revolution on a four-cylinder four-stroke.
      const firingHz = Math.max(25, (rpm / 60) * 2);
      this.oscillators.forEach(({ osc, multiple }) => osc.frequency.setTargetAtTime(firingHz * multiple, t, 0.025));
      const load = active ? Math.max(0, Math.min(1, car.throttle || 0)) : 0;
      const rev = Math.max(0, Math.min(1, (rpm - 900) / 5700));
      this.engineFilter.frequency.setTargetAtTime(520 + rev * 1450 + load * 650, t, 0.045);
      this.engineGain.gain.setTargetAtTime(active ? 0.105 + rev * 0.065 + load * 0.055 : 0, t, 0.07);
      this.exhaustFilter.frequency.setTargetAtTime(420 + rev * 800, t, 0.06);
      this.exhaustGain.gain.setTargetAtTime(active ? 0.018 + rev * (0.035 + load * 0.035) : 0, t, 0.08);

      const slip = Math.max(0, (car.slip || 0) - 0.45);
      const understeer = Math.max(0, (car.understeer || 0) - 1);
      const squeal = active ? Math.min(0.085, slip * 0.055 + understeer * 0.035) : 0;
      this.squeal.gain.setTargetAtTime(squeal, t, 0.08);

      // Brief stutter at the limiter gives the tiny engine a rally-game edge.
      const limiter = active && rpm > 6500 ? Math.min(0.11, (rpm - 6500) / 900 * 0.11) : 0;
      this.limiterGain.gain.setTargetAtTime(limiter, t, 0.015);

      if (active && this.lastGear !== null && car.gear !== this.lastGear) this.shift(car.gear > this.lastGear, load, t);
      this.lastGear = active ? car.gear : null;
      this.lastShift = car.shiftT || 0;
    }
    shift(up, load, t) {
      // Short gearbox clack and a low thump, with a little exhaust pop on a loaded upshift.
      const ctx = this.ctx;
      const hit = (freq, endFreq, duration, volume, type) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = type;
        osc.frequency.setValueAtTime(freq, t);
        osc.frequency.exponentialRampToValueAtTime(Math.max(20, endFreq), t + duration);
        gain.gain.setValueAtTime(0.0001, t);
        gain.gain.exponentialRampToValueAtTime(volume, t + 0.006);
        gain.gain.exponentialRampToValueAtTime(0.0001, t + duration);
        osc.connect(gain).connect(this.master);
        osc.start(t);
        osc.stop(t + duration + 0.01);
      };
      hit(up ? 150 : 105, 48, 0.075, 0.11, 'triangle');
      hit(up ? 1250 : 760, 240, 0.045, 0.045, 'square');
      if (up && load > 0.35) hit(680, 90, 0.055, 0.035, 'sawtooth');
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
        g.gain.exponentialRampToValueAtTime(0.12, t0 + 0.01);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
        o.connect(g).connect(this.master);
        o.start(t0);
        o.stop(t0 + dur + 0.05);
      }
    }
    toggleMute() {
      this.muted = !this.muted;
      if (this.master) this.master.gain.setTargetAtTime(this.muted ? 0 : 0.42, this.ctx.currentTime, 0.025);
      return this.muted;
    }
  }

  SC.EngineAudio = EngineAudio;
})();
