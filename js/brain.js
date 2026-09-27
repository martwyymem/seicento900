// Learning AI. Each bot drives by a pace it has learned for every 30 m section of the track. It finds its
// limit by trial and error (push a little, back off after a moment) and studies the player: how fast you
// take each corner, the line you use, where and on which side you pass, whether you block, and how cleanly
// you race. Everything learned is kept per track in localStorage, so the field gets to know you over time.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const KEY = 'seicento-brain-v1';
  const VER = 1;
  const BIN = 30; // metres per learned section
  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

  // ---------------- persistent memory ----------------
  let store = null;
  const hasLS = () => typeof localStorage !== 'undefined';
  function loadStore() {
    if (store) return store;
    try {
      store = hasLS() ? JSON.parse(localStorage.getItem(KEY) || 'null') : null;
    } catch (e) {
      store = null;
    }
    if (!store || store.v !== VER) store = { v: VER, tracks: {} };
    return store;
  }
  function saveStore() {
    try {
      if (hasLS()) localStorage.setItem(KEY, JSON.stringify(store));
    } catch (e) {
      /* quota or private mode: learning still works for this session */
    }
  }
  // ratios are stored as integers (×10⁴) to keep the JSON small
  const enc = (a, k = 1e4) => Array.from(a, (x) => Math.round(x * k));
  const dec = (a, n, k = 1e4) => {
    const out = new Float32Array(n);
    if (Array.isArray(a) && a.length === n) for (let i = 0; i < n; i++) out[i] = (a[i] || 0) / k;
    return out;
  };

  function trackMemory(key, nb) {
    const raw = (loadStore().tracks[key] || {});
    const ok = raw.nb === nb;
    return {
      nb,
      pr: dec(ok && raw.pr, nb), // player's pace in each section, as a fraction of the grip limit
      pn: dec(ok && raw.pn, nb, 1), // samples behind it
      pd: dec(ok && raw.pd, nb, 100), // player's usual offset from the racing line (m)
      aS: dec(ok && raw.aS, nb, 100), // where you overtake: sum of sides (+1 right, −1 left)
      aN: dec(ok && raw.aN, nb, 1),
      laps: raw.laps || 0,
      races: raw.races || 0,
      block: raw.block != null ? raw.block : 0.3, // how often you cover the side a bot goes for
      rough: raw.rough || 0, // how often contact is your fault (0 clean … 1 dodgem)
      bots: (ok && raw.bots) || {},
    };
  }

  class Brain {
    constructor(race, opts = {}) {
      this.race = race;
      this.persist = !!opts.persist;
      const tr = (this.tr = race.track);
      this.key = race.s.track;
      this.nb = Math.ceil(tr.L / BIN);
      this.mem = trackMemory(this.key, this.nb);
      // how much each section is grip-limited: 0 on flat-out straights, 1 in corners and braking zones
      this.W = new Float32Array(this.nb);
      this.vRef = new Float32Array(this.nb);
      for (let b = 0; b < this.nb; b++) {
        let lo = Infinity;
        for (let s = b * BIN; s < Math.min(tr.L, (b + 1) * BIN); s += tr.step) lo = Math.min(lo, tr.sample(tr.PROF, s));
        this.vRef[b] = lo;
        this.W[b] = clamp((40 - lo) / 6, 0, 1);
      }
      this.gaps = new Map();
      this.obs = null;
      this.lastSay = -99;
      this.lastContact = -99;
      this.lastCommit = 0;
      this.playerLap = null;
      this.bots = [];
    }

    bin(s) {
      return Math.floor(this.tr.wrap(s) / BIN) % this.nb;
    }

    // ---------------- bots ----------------
    addBot(car, spread) {
      const rng = this.race.rng;
      // talent: the pace this driver can hold without mistakes; learning can push a little beyond it
      const talent = Math.min(0.999, car.skill + 0.008 + (spread + 0.006) * rng());
      const cap = Math.min(1.004, talent + 0.012);
      const floor = car.skill - 0.04;
      const e = new Float32Array(this.nb).fill(car.skill);
      const saved = this.mem.bots[car.name];
      if (saved && saved.length === this.nb)
        for (let i = 0; i < this.nb; i++) if (saved[i]) e[i] = clamp(saved[i] / 1e4, floor, cap);
      car.brain = {
        e, e0: Float32Array.from(e), talent, cap, floor,
        bin: -1, dirty: false, mind: 'race', thinkT: rng() * 0.4, zone: -1, boostT: 0,
        att: null, lastSaid: -99, said: new Set(), copied: 0, copyGain: 0, mistakes: 0,
      };
      this.bots.push(car);
    }

    // Learned pace (fraction of the grip limit) at s, blended between sections, plus the current state of mind.
    paceAt(car, s) {
      const b = car.brain;
      const u = this.tr.wrap(s) / BIN - 0.5;
      const i = ((Math.floor(u) % this.nb) + this.nb) % this.nb;
      const f = u - Math.floor(u);
      let p = b.e[i] + (b.e[(i + 1) % this.nb] - b.e[i]) * f;
      if (b.mind === 'attack' && b.zone >= 0 && Math.abs(this.binDist(this.bin(s), b.zone)) <= 2) p += 0.005;
      if (b.boostT > 0) p += 0.003; // fired up after being passed
      if (b.mind === 'manage') p -= 0.004;
      return p;
    }

    binDist(a, b) {
      let d = a - b;
      if (d > this.nb / 2) d -= this.nb;
      if (d < -this.nb / 2) d += this.nb;
      return d;
    }

    // Called every rail step. noLearn: the section wasn't driven freely (traffic, pits), so it teaches nothing.
    railStep(car, dt, noLearn) {
      const b = car.brain;
      const race = this.race;
      if (b.boostT > 0) b.boostT -= dt;
      if ((b.thinkT -= dt) <= 0) {
        b.thinkT = 0.4;
        this.think(car);
      }
      const i = this.bin(car.s);
      if (noLearn) b.dirty = true;
      if (i === b.bin) return;
      if (b.bin >= 0 && !b.dirty && race.phase === 'racing') this.learn(car, b.bin);
      b.bin = i;
      b.dirty = noLearn;
      if (race.phase !== 'racing' || car.mode !== 'race' || car.finished || this.W[i] <= 0) return;
      // over the limit there is a chance of a moment: a lock-up or running wide
      const over = (this.paceAt(car, i * BIN + BIN / 2) - b.talent) / 0.01;
      if (over > 0) {
        const p = 0.006 * over * over * this.W[i] * (1 + 1.5 * race.weather.wet);
        if (race.rng() < p) this.mistake(car, i);
      }
    }

    mistake(car, i) {
      const b = car.brain;
      const tr = this.tr;
      const race = this.race;
      b.dirty = true;
      b.mistakes++;
      race.botMistake(car);
      // learn from it: this section, and a little either side, is taken more carefully from now on
      for (let j = -1; j <= 1; j++) {
        const q = (i + j + this.nb) % this.nb;
        b.e[q] = clamp(b.e[q] - (j === 0 ? 0.015 : 0.007), b.floor, b.cap);
      }
      if (this.near(car, 3)) this.say(car, `${short(car)} runs wide at ${this.where(i)} — pushing too hard, backing off there next lap`, 'wide');
    }

    learn(car, i) {
      const b = car.brain;
      const w = this.W[i];
      if (w <= 0) return;
      let e = b.e[i];
      // trial and error: creep towards the limit; slower once above it, where mistakes start
      const gap = b.talent - e;
      e += gap > 0 ? 0.015 * gap * w + 0.00004 : 0.00004 * w;
      // imitation: you showed that this section can be taken faster
      const m = this.mem;
      if (m.pn[i] >= 1 && m.pr[i] > e) {
        const before = e;
        e += 0.35 * w * (Math.min(m.pr[i], b.cap) - e);
        if (e - before > 0.002) {
          b.copied++;
          b.copyGain += ((e - before) / e) * (BIN / Math.max(8, this.vRef[i] * e));
        }
      }
      b.e[i] = clamp(e, b.floor, b.cap);
    }

    // ---------------- thinking ----------------
    think(car) {
      const b = car.brain;
      const race = this.race;
      const p = race.player;
      const tr = this.tr;
      const L = tr.L;
      b.mind = 'race';
      if (car.mode !== 'race' || car.finished || race.phase !== 'racing') return;
      const live = p.mode === 'race' && !p.finished && !p.dnf;
      const gap = live ? p.lap * L + p.s - (car.lap * L + car.s) : Infinity;
      if (gap > 0 && gap < 80) {
        // chasing you: look for where you are slower than me in the next ~600 m
        b.mind = 'attack';
        if (b.zone < 0 || this.binDist(b.zone, this.bin(car.s)) < -2) {
          b.zone = -1;
          const i0 = this.bin(car.s);
          let best = 0.02;
          for (let j = 2; j < 600 / BIN; j++) {
            const q = (i0 + j) % this.nb;
            if (this.mem.pn[q] < 1 || this.W[q] < 0.5) continue;
            const deficit = b.e[q] - this.mem.pr[q];
            if (deficit > best) {
              best = deficit;
              b.zone = q;
            }
          }
          if (b.zone >= 0 && gap < 40 && this.near(car, 2))
            this.say(car, `${short(car)} has noticed you're slow through ${this.where(b.zone)} — expect an attack there`, 'zone');
        }
      } else if (gap < 0 && gap > -35) {
        const pv = Math.hypot(p.vx, p.vy);
        if (gap > -14 || pv > car.v + 0.5) b.mind = 'defend';
      } else {
        b.zone = -1;
        // alone on track with worn tyres: look after them
        const ahead = race.order[car.pos - 2];
        const behind = race.order[car.pos];
        const clear = (o) => !o || Math.abs(o.lap * L + o.s - (car.lap * L + car.s)) > 110;
        if (car.tyre.wear < 0.55 && clear(ahead) && clear(behind)) b.mind = 'manage';
      }
      // judge an attack on you: did you move across to cover it?
      if (b.att && !b.att.judged && race.clock - b.att.t > 1.2) {
        b.att.judged = true;
        const moved = (p.d - b.att.d0) * b.att.side > 0.7;
        this.mem.block = this.mem.block * 0.88 + (moved ? 0.12 : 0);
      }
    }

    // Adjust a bot's lateral target (after traffic logic): cover the side you're likely to attack,
    // or switch sides when you block its move.
    adjust(car, t, lim) {
      const b = car.brain;
      const race = this.race;
      const p = race.player;
      const tr = this.tr;
      if (b.mind === 'defend' && car.overtakeT <= 0) {
        const i = this.bin(car.s);
        let hist = 0;
        let n = 0;
        for (let j = 0; j < 6; j++) {
          const q = (i + j) % this.nb;
          hist += this.mem.aS[q];
          n += this.mem.aN[q];
        }
        const now = Math.sign(p.d - car.d);
        const inside = Math.sign(tr.sample(tr.KC, car.s + 40));
        let pred = n >= 2 ? (0.6 * hist) / n + 0.4 * now : 0.5 * now + 0.3 * inside;
        if (Math.abs(pred) > 0.25) {
          const rl = tr.sample(tr.RLD, car.s);
          const want = clamp(rl + Math.sign(pred) * 1.3, -lim, lim);
          t.dT = t.dT + (want - t.dT) * 0.8;
          if (!b.covering && n >= 2 && this.near(car, 1)) {
            b.covering = true;
            this.say(car, `${short(car)} is covering the ${pred > 0 ? 'right' : 'left'} — it has learned where you like to pass`, 'cover');
          }
        }
      } else b.covering = false;
      // attacking you: remember the attempt, and switch back if you close the door
      if (car.overtakeT > 0 && this.aheadIs(car, p)) {
        if (!b.att || b.att.id !== car.overtakeT0) {
          b.att = { id: car.overtakeT0, t: race.clock, d0: p.d, side: Math.sign(car.overtakeD - p.d) || 1, judged: false, switched: false };
        }
        const a = b.att;
        if (!a.switched && (p.d - a.d0) * a.side > 0.9) {
          a.switched = true;
          if (race.rng() < clamp(0.25 + this.mem.block, 0, 0.9)) {
            const other = p.d - a.side * 2.4;
            if (Math.abs(other) <= lim) {
              car.overtakeD = other;
              car.overtakeT = 3;
              t.dT = other;
              if (this.near(car, 1)) this.say(car, `${short(car)} saw the block coming and switches to the ${other > p.d ? 'right' : 'left'}`, 'switch');
            }
          }
        }
      }
      return t;
    }

    aheadIs(car, o) {
      const g = this.tr.rel(o.s - car.s);
      return g > 0 && g < 30 && o.mode === 'race';
    }

    // Extra lateral room bots leave next to someone who keeps leaning on them.
    margin(o) {
      return o.isPlayer ? 0.9 * this.mem.rough : 0;
    }

    // ---------------- watching the player ----------------
    observe() {
      const race = this.race;
      const p = race.player;
      const tr = this.tr;
      if (race.phase !== 'racing') return;
      if (this.persist && race.raceTime - this.lastCommit > 120) this.commit();
      const driving = p.control === 'free' && !p.autopilot && p.mode === 'race' && !p.finished && !p.dnf;
      if (!driving) {
        this.obs = null;
        this.gaps.clear();
        return;
      }
      if (this.playerLap !== p.lap) {
        if (this.playerLap != null && p.lap > this.playerLap) {
          this.mem.laps++;
          this.mem.rough *= 0.9;
        }
        this.playerLap = p.lap;
      }
      const i = this.bin(p.s);
      const o = this.obs;
      if (o && o.bin !== i) {
        const m = this.mem;
        if (o.ok && o.max > 0.55 && Math.abs(this.binDist(i, o.bin)) === 1) {
          const a = m.pn[o.bin] < 1 ? 1 : 0.4;
          m.pr[o.bin] = m.pr[o.bin] * (1 - a) + Math.min(1.03, o.max) * a;
          m.pn[o.bin] = Math.min(99, m.pn[o.bin] + 1);
        }
        if (o.n > 0) {
          const a = m.pn[o.bin] <= 1 ? 1 : 0.3;
          m.pd[o.bin] = m.pd[o.bin] * (1 - a) + (o.dsum / o.n) * a;
        }
      }
      if (!o || o.bin !== i) this.obs = { bin: i, max: 0, ok: true, dsum: 0, n: 0 };
      const ob = this.obs;
      const v = Math.hypot(p.vx, p.vy);
      const mu = SC.Tyres.tyreGrip(p.tyre, race.weather.wet);
      const lim = tr.sample(tr.PROF, p.s) * Math.sqrt(mu);
      if (lim < 40) ob.max = Math.max(ob.max, v / lim);
      ob.dsum += p.d - tr.sample(tr.RLD, p.s);
      ob.n++;
      // only clean, unhindered driving teaches the field anything
      const ch = Math.cos(p.heading), sh = Math.sin(p.heading);
      const slipAng = v > 3 ? Math.abs(Math.atan2(-sh * p.vx + ch * p.vy, ch * p.vx + sh * p.vy)) : 0;
      if (Math.abs(p.d) > tr.half + 0.3 || p.rev || slipAng > 0.14 || race.clock - this.lastContact < 2) ob.ok = false;
      else if (race.cars.some((c) => c !== p && !c.dnf && c.mode === 'race' && tr.rel(c.s - p.s) > 0 && tr.rel(c.s - p.s) < 22 && Math.abs(c.d - p.d) < 2.2))
        ob.ok = false;

      // overtakes between you and the bots
      const L = tr.L;
      const pp = p.lap * L + p.s;
      for (const c of this.bots) {
        if (c.dnf || c.finished || c.mode !== 'race') {
          this.gaps.delete(c);
          continue;
        }
        const g = c.lap * L + c.s - pp;
        const prev = this.gaps.get(c);
        if (Math.abs(g) > 15) {
          this.gaps.delete(c);
          continue;
        }
        this.gaps.set(c, g);
        if (prev == null) continue;
        if (prev > 0 && g <= 0) {
          const side = Math.sign(p.d - c.d) || 1;
          this.mem.aS[i] += side;
          this.mem.aN[i] += 1;
          c.brain.boostT = 20;
          this.say(c, `You passed ${short(c)} on the ${side > 0 ? 'right' : 'left'} at ${this.where(i)} — it'll remember that`, 'passed');
        } else if (prev < 0 && g >= 0 && c.brain.mind === 'attack' && c.brain.zone >= 0) {
          this.say(c, `${short(c)} got you where it planned to, at ${this.where(i)}`, 'got');
        }
      }
    }

    // Car contact: work out who closed in on whom.
    contact(a, b, nx, ny) {
      if (!a.isPlayer && !b.isPlayer) return;
      const p = a.isPlayer ? a : b;
      const o = a.isPlayer ? b : a;
      const sgn = a.isPlayer ? 1 : -1; // (nx, ny) points from a to b
      const pIn = (p.vx * nx + p.vy * ny) * sgn;
      const oIn = -(o.vx * nx + o.vy * ny) * sgn;
      this.lastContact = this.race.clock;
      if (pIn > oIn + 0.5) {
        const before = this.mem.rough;
        this.mem.rough = Math.min(1, before + 0.2);
        if (before < 0.5 && this.mem.rough >= 0.5) this.say(o, 'The field has decided you are a bit rough — they will leave you extra room', 'rough');
      }
    }

    // A bot crossed the line: tell you what it picked up from you.
    lap(car) {
      const b = car.brain;
      if (!b) return;
      if (b.copied >= 3 && b.copyGain > 0.1 && this.near(car, 3))
        this.say(car, `${short(car)} copied your speed in ${b.copied} places last lap (≈${b.copyGain.toFixed(1)} s)`, 'copy');
      b.copied = 0;
      b.copyGain = 0;
    }

    // ---------------- feed ----------------
    near(car, n) {
      const p = this.race.player;
      return !p.dnf && Math.abs(car.pos - p.pos) <= n;
    }

    // Post a thought to the feed; each kind of remark only once per bot per race, and not too often.
    say(car, text, kind) {
      const race = this.race;
      const b = car.brain;
      if (race.clock - this.lastSay < 10 || (b && (race.clock - b.lastSaid < 45 || b.said.has(kind)))) return;
      this.lastSay = race.clock;
      if (b) {
        b.lastSaid = race.clock;
        b.said.add(kind);
      }
      race.log(`🧠 ${text}`, 'ai');
    }

    where(i) {
      const s = i * BIN + BIN / 2;
      const name = this.tr.sectorName ? this.tr.sectorName(s) : '';
      return name ? name : `the ${(s / 1000).toFixed(1)} km mark`;
    }

    // Time per lap each bot has gained by learning this race (s), fastest learner first.
    progress() {
      return this.bots
        .map((c) => {
          const b = c.brain;
          let t = 0;
          for (let i = 0; i < this.nb; i++) {
            if (!this.W[i]) continue;
            const v = Math.max(8, this.vRef[i] * b.e[i]);
            t += (BIN / v) * ((b.e[i] - b.e0[i]) / b.e[i]);
          }
          return { car: c, gain: t };
        })
        .sort((x, y) => y.gain - x.gain);
    }

    // Write what was learned to localStorage.
    commit(final) {
      if (!this.persist) return;
      this.lastCommit = this.race.raceTime;
      const m = this.mem;
      const st = loadStore();
      const prev = st.tracks[this.key] || {};
      const bots = Object.assign({}, prev.nb === this.nb ? prev.bots : {});
      for (const c of this.bots) bots[c.name] = enc(c.brain.e);
      st.tracks[this.key] = {
        nb: this.nb, pr: enc(m.pr), pn: enc(m.pn, 1), pd: enc(m.pd, 100), aS: enc(m.aS, 100), aN: enc(m.aN, 1),
        laps: m.laps, races: m.races + (final ? 1 : 0), block: +m.block.toFixed(3), rough: +m.rough.toFixed(3), bots,
      };
      if (final) m.races++;
      saveStore();
    }

    // For the menu: what the AI knows about you on a track.
    static summary(key) {
      const t = loadStore().tracks[key];
      if (!t) return null;
      let n = 0;
      let sum = 0;
      if (Array.isArray(t.pr))
        t.pr.forEach((x, i) => {
          if (x && t.pn[i]) {
            n++;
            sum += x / 1e4;
          }
        });
      return { laps: t.laps || 0, races: t.races || 0, sections: n, pace: n ? sum / n : null, block: t.block, rough: t.rough };
    }

    static forget(key) {
      const st = loadStore();
      if (key) delete st.tracks[key];
      else st.tracks = {};
      saveStore();
    }
  }

  const short = (car) => car.name.split(' ').pop();

  SC.Brain = Brain;
})();
