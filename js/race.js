// Race simulation: field, AI drivers, player physics, pit stops, weather, timing and collisions.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const { CAR } = SC.Car;
  const T = SC.Tyres;
  const S = SC.Strategy;
  const G = SC.G;
  const { mulberry32, smoothstep } = SC.util;

  const BOTS = [
    ['Giancarlo Bianchi', '#1d4fa3'], ['Marek Kowalski', '#f2c318'], ['Luca Ferraro', '#f4f4f4'],
    ['Zbigniew Nowak', '#2e8b57'], ['Paolo Esposito', '#ff7f11'], ['Krzysztof Wiśniewski', '#7b2cbf'],
    ['Matteo Romano', '#00a6d6'], ['Tomasz Wójcik', '#c9184a'], ['Hans Becker', '#404040'],
    ['Jan Kamiński', '#9bd13b'], ['Sofia Greco', '#ff66b3'], ['Agnieszka Lewandowska', '#8d6e63'],
    ['Klaus Schmidt', '#1b998b'], ['Andrzej Zieliński', '#b5838d'], ['Francesca Ricci', '#6a994e'],
  ];

  // band: how hard the field is pulled back towards the player when a gap opens (rubber-band pace, ±).
  // A single mistake shouldn't hand the win to someone three seconds a lap off your pace, so the bots
  // give a little of that back the way real opposition would — pushing harder when they're behind,
  // backing off a fraction when they've broken clear. It fades out on Hard and is off on Alien.
  const DIFFICULTY = {
    easy: { skill: 0.93, spread: 0.035, mistakes: 0.12, band: 0.05 },
    medium: { skill: 0.955, spread: 0.028, mistakes: 0.07, band: 0.035 },
    hard: { skill: 0.975, spread: 0.02, mistakes: 0.04, band: 0.015 },
    alien: { skill: 0.995, spread: 0.01, mistakes: 0.02, band: 0 },
  };

  const trackCache = {};
  SC.getTrack = (key) => trackCache[key] || (trackCache[key] = new SC.Track(key));

  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

  // grip multiplier and extra rolling drag (fraction of the wheel load) per surface
  const SURF = {
    track: { grip: 1, drag: 0 },
    asphalt: { grip: 0.9, drag: 0.004 },
    grass: { grip: 0.5, drag: 0.07 },
    gravel: { grip: 0.42, drag: 0.22 },
  };

  // ---------------- weather ----------------
  class Weather {
    constructor(mode, duration, rng) {
      this.mode = mode;
      this.rain = 0;
      this.wet = 0;
      if (mode === 'wet') {
        this.rain = 0.7;
        this.wet = 0.85;
      }
      this.showers = [];
      if (mode === 'variable') {
        if (duration < 5400) {
          const start = duration * (0.22 + 0.3 * rng());
          this.showers.push({ start, end: start + duration * (0.22 + 0.25 * rng()), intensity: 0.6 + 0.4 * rng() });
        } else {
          // endurance races: a shower every few hours, each 20–80 minutes long
          let t = 1800 + rng() * 5400;
          while (t < duration - 1200) {
            const len = 1200 + rng() * 3600;
            this.showers.push({ start: t, end: Math.min(duration, t + len), intensity: 0.45 + 0.55 * rng() });
            t += len + 3600 * (2 + rng() * 4);
          }
        }
      }
    }
    update(dt, t) {
      if (this.mode === 'variable') {
        let r = 0;
        for (const sh of this.showers) r = Math.max(r, sh.intensity * smoothstep((t - sh.start) / 60) * smoothstep((sh.end - t) / 60));
        this.rain = r;
      }
      if (this.mode === 'dry') return;
      const target = Math.min(1, this.rain * 1.2);
      if (this.rain > 0.05 && target > this.wet) this.wet = Math.min(target, this.wet + (this.rain * dt) / 140);
      else this.wet = Math.max(0, this.wet - dt / 420);
    }
    forecast(t) {
      if (this.mode === 'dry') return 'Dry all race';
      if (this.mode === 'wet') return 'Rain all race';
      const sh = this.showers.find((x) => t < x.end);
      const mins = (x) => {
        const m = Math.max(1, Math.round(x / 60));
        return m < 90 ? `~${m} min` : `~${(m / 60).toFixed(1)} h`;
      };
      if (!sh) return this.showers.length ? 'Rain has passed — dry to the flag' : 'Dry all race';
      if (t < sh.start - 20) return `Rain expected in ${mins(sh.start - t)}`;
      return `Raining — easing in ${mins(sh.end - t)}`;
    }
  }

  function sat(a, b) {
    const hl = CAR.length / 2;
    const hw = CAR.width / 2;
    const ca = Math.cos(a.heading), sa = Math.sin(a.heading);
    const cb = Math.cos(b.heading), sb = Math.sin(b.heading);
    const axes = [[ca, sa], [-sa, ca], [cb, sb], [-sb, cb]];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    let best = Infinity;
    let bn = null;
    for (const [ax, ay] of axes) {
      const ra = hl * Math.abs(ca * ax + sa * ay) + hw * Math.abs(-sa * ax + ca * ay);
      const rb = hl * Math.abs(cb * ax + sb * ay) + hw * Math.abs(-sb * ax + cb * ay);
      const dist = dx * ax + dy * ay;
      const o = ra + rb - Math.abs(dist);
      if (o <= 0) return null;
      if (o < best) {
        best = o;
        bn = dist < 0 ? [-ax, -ay] : [ax, ay];
      }
    }
    return { nx: bn[0], ny: bn[1], depth: best };
  }

  // Offset from a car's centre to its corner furthest along (nx, ny).
  function corner(car, nx, ny) {
    const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
    const fx = ((ch * nx + sh * ny) >= 0 ? 1 : -1) * CAR.length / 2;
    const fy = ((-sh * nx + ch * ny) >= 0 ? 1 : -1) * CAR.width / 2;
    return [fx * ch - fy * sh, fx * sh + fy * ch];
  }

  class Race {
    constructor(settings, playerPlan) {
      this.s = settings;
      this.track = SC.getTrack(settings.track);
      this.cal = S.calibrate(this.track);
      this.fpl = this.cal.fuelPerLap * settings.fuelMult;
      // timed races (up to 24 h) finish when the leader crosses the line after the clock runs out;
      // R is then a running estimate of the leader's total laps
      this.timed = settings.format === 'time';
      this.duration = this.timed ? settings.hours * 3600 : null;
      this.R = this.timed ? S.estimateLaps(this.track, this.duration, settings) : settings.laps;
      this.startHour = settings.startHour != null ? settings.startHour : 14;
      this.rng = mulberry32((Math.random() * 2 ** 31) | 0);
      this.rules = { mandatoryStop: settings.mandatoryStop, twoCompounds: settings.twoCompounds, refuel: settings.refuel };
      this.clock = 0;
      this.greenAt = Infinity;
      this.lightsOutAt = 6 + this.rng() * 2;
      this.phase = 'countdown';
      this.events = [];
      this.eventSeq = 0;
      this.cp = [];
      this.cpStep = 25;
      this.finishCount = 0;
      this.winner = null;
      this.fastest = null;
      this.penaltyTime = Math.round(this.cal.pitDriveLoss + 15);
      this.weather = new Weather(settings.weather, this.timed ? this.duration : this.R * this.cal.T0 * 1.08, this.rng);
      this.planWetStart = this.weather.wet;
      this.cars = [];
      // bots drive the same four-wheel physics as the player; the UI sets warp, and anything faster than
      // real time (or the menu demo) runs them on the cheaper rail model
      this.physBots = !settings.demo && settings.botPhysics !== 'off';
      this.warp = 1;
      // learning AI (off: every bot drives one fixed pace everywhere, as before)
      this.brain = settings.aiLearning !== 'off' && SC.Brain ? new SC.Brain(this, { persist: !settings.demo }) : null;
      this.buildField(playerPlan);
      this.order = this.cars.slice();
    }

    get raceTime() {
      return this.clock - this.greenAt;
    }

    // local time of day in hours (0–24): the clock starts at startHour and runs in real time
    get timeOfDay() {
      return (((this.startHour + Math.max(0, this.raceTime) / 3600) % 24) + 24) % 24;
    }

    get timeLeft() {
      return this.timed ? Math.max(0, this.duration - Math.max(0, this.raceTime)) : null;
    }

    log(text, kind = 'info') {
      this.events.push({ id: ++this.eventSeq, t: this.clock, text, kind });
      if (this.events.length > 60) this.events.shift();
    }

    planOpts(extra) {
      return Object.assign(
        {
          track: this.track, laps: this.R, wet: this.weather.wet, wearMult: this.s.wearMult, fuelMult: this.s.fuelMult,
          rules: this.rules, crew: this.s.crew, parallel: this.s.parallel,
        },
        extra
      );
    }

    makeCar(id, name, color, number, isPlayer) {
      return {
        id, name, color, number, isPlayer,
        skill: 1, agg: 1, pace: 1, reaction: 0,
        s: 0, lap: 0, d: 0, v: 0, x: 0, y: 0, heading: 0, vx: 0, vy: 0, yawRate: 0, steer: 0, dKick: 0,
        mode: 'race', control: isPlayer ? 'free' : 'rail', autopilot: false,
        tyre: { c: 'M', wear: 1, temp: 0.6 }, fuel: 10, usedMask: 0,
        plan: [], stintIdx: 0, stintStartLap: 0, stops: 0, history: [],
        pitRequest: false, service: null, serviceEdited: false, pit: null, planWet: this.weather.wet,
        gear: 0, rpm: CAR.idleRpm, throttle: 0, brakeOn: false, shiftT: 0, slip: 0, understeer: 0,
        lapStart: 0, lastLap: null, bestLap: null, lapTimes: [], invalidLap: false,
        finished: false, finishOrder: 0, finishTime: null, penalty: 0, penalties: [], dnf: false,
        gap: 0, cpIdx: -1, pos: 0, overtakeD: null, overtakeT: 0, slowT: 0, mistakeP: null,
        offTarget: 0,
      };
    }

    applyPlan(car, p) {
      car.plan = p.stints.map((st) => ({ c: st.c, laps: st.laps }));
      car.stintIdx = 0;
      car.tyre = { c: p.stints[0].c, wear: 1, temp: 0.6 };
      car.usedMask = T.compoundBit(p.stints[0].c);
      car.history = [p.stints[0].c];
      car.fuel = Math.min(CAR.tank, p.stints[0].fuel || S.fuelNeed(this.R, this.fpl));
    }

    buildField(playerPlan) {
      const diff = DIFFICULTY[this.s.difficulty];
      const rng = this.rng;
      const options = S.plan(this.planOpts({ diverse: true }));
      const fallback = { stints: [{ c: this.weather.wet > 0.4 ? 'W' : 'M', laps: this.R, fuel: Math.min(CAR.tank, S.fuelNeed(this.R, this.fpl)) }] };
      const bots = [];
      const numbers = [3, 5, 8, 11, 14, 17, 21, 23, 27, 33, 44, 55, 63, 77, 88];
      for (let i = 0; i < this.s.opponents; i++) {
        const [name, color] = BOTS[i];
        const car = this.makeCar(i + 1, name, color, numbers[i], false);
        car.skill = diff.skill + (rng() - 0.6) * diff.spread;
        car.stripes = rng() < 0.3;
        car.agg = 0.9 + rng() * 0.2;
        car.mistakeRate = diff.mistakes;
        if (this.brain) this.brain.addBot(car, diff.spread);
        car.wetThreshold = 0.36 + rng() * 0.14;
        let pick = options[0] || fallback;
        if (options.length > 1) {
          const pool = options.filter((o) => o.time < options[0].time * 1.012);
          pick = rng() < 0.2 ? options[Math.floor(rng() * Math.min(4, options.length))] : pool[Math.floor(Math.pow(rng(), 1.5) * pool.length)];
        }
        this.applyPlan(car, pick);
        car.strategyLabel = S.label(pick);
        car.quali = car.skill + (rng() - 0.5) * 0.02;
        bots.push(car);
      }
      bots.sort((a, b) => b.quali - a.quali);

      const player = this.makeCar(0, this.s.playerName || 'You', this.s.playerColor, this.s.playerNumber, true);
      player.skill = 0.97; // used only while on autopilot
      this.applyPlan(player, playerPlan || options[0] || fallback);
      player.strategyLabel = S.label(playerPlan || options[0] || fallback);
      this.player = player;

      let slot;
      const n = bots.length + 1;
      if (this.s.grid === 'pole') slot = 0;
      else if (this.s.grid === 'back') slot = n - 1;
      else if (this.s.grid === 'middle') slot = Math.floor(n / 2);
      else slot = Math.floor(rng() * n);
      const field = bots.slice();
      field.splice(slot, 0, player);

      const tr = this.track;
      field.forEach((car, k) => {
        car.grid = k + 1;
        car.box = k;
        car.s = -(9 + k * 6.5);
        car.d = (k % 2 === 0 ? -1 : 1) * tr.half * 0.36;
        const p = tr.pos(car.s, car.d);
        car.x = p.x;
        car.y = p.y;
        car.heading = tr.heading(car.s);
        car.reaction = 0.18 + rng() * 0.35 + (1 - car.skill) * 2;
        car.pace = 1;
        this.cars.push(car);
      });
      this.log(`Grid set — you start P${player.grid} of ${field.length}`);
    }

    // ---------------- main step ----------------
    step(dt, input) {
      this.clock += dt;
      if (this.phase === 'countdown' && this.clock >= this.lightsOutAt) {
        this.phase = 'racing';
        this.greenAt = this.clock;
        this.log('Lights out — go go go!', 'good');
      }
      if (this.phase === 'racing') {
        const before = this.weather.rain;
        this.weather.update(dt, this.raceTime);
        if (before <= 0.05 && this.weather.rain > 0.05) this.log('Rain is falling!', 'warn');
        if (before > 0.05 && this.weather.rain <= 0.05) this.log('Rain has stopped — the track will dry', 'info');
      }

      for (const car of this.cars) {
        car.px = car.x;
        car.py = car.y;
        car.ph = car.heading;
        car.ps = car.s;
        if (car.dnf) continue;
        const prevP = this.track.rel(car.s);
        if (!car.isPlayer) this.botControl(car);
        if (car.control === 'free') this.stepFree(car, dt, car.isPlayer ? input : this.botInput(car, dt));
        else this.stepRail(car, dt);
        this.afterMove(car, prevP);
      }
      if (this.s.collisions) this.collide();
      this.updateOrder();
      if (this.brain) this.brain.observe();
      this.rubberBand(dt);

      if (this.winner && this.phase === 'racing') {
        const waiting = this.cars.filter((c) => !c.finished && !c.dnf);
        const cap = Math.max(240, this.cal.T0 * 1.6);
        if (!waiting.length || this.raceTime - this.winner.finishTime > cap) {
          for (const c of waiting) this.finish(c, true);
          this.phase = 'finished';
          if (this.brain) this.brain.commit(true);
        }
      }
    }

    // Draw cars between the last two physics ticks (alpha 0..1) so motion is smooth at any frame rate.
    // Returns a function that restores the simulated state.
    interpolate(alpha) {
      const tr = this.track;
      // this.cars is fixed once the grid is set, so the snapshot pool and the restore
      // closure below are built once and reused every frame instead of allocating anew
      if (!this._interpSaved) {
        this._interpSaved = this.cars.map((c) => ({ c, x: 0, y: 0, heading: 0, s: 0 }));
        this._interpRestore = () => {
          for (const rec of this._interpSaved) {
            rec.c.x = rec.x;
            rec.c.y = rec.y;
            rec.c.heading = rec.heading;
            rec.c.s = rec.s;
          }
        };
      }
      for (const rec of this._interpSaved) {
        rec.x = rec.c.x;
        rec.y = rec.c.y;
        rec.heading = rec.c.heading;
        rec.s = rec.c.s;
      }
      if (alpha > 0 && alpha < 1) {
        for (const c of this.cars) {
          if (c.px == null) continue;
          const b = 1 - alpha;
          c.x = c.px * b + c.x * alpha;
          c.y = c.py * b + c.y * alpha;
          c.heading -= SC.util.wrapAngle(c.heading - c.ph) * b;
          c.s = tr.wrap(c.s - tr.rel(c.s - c.ps) * b);
        }
      }
      return this._interpRestore;
    }

    moveS(car, ds) {
      const L = this.track.L;
      car.s += ds;
      if (car.s >= L) {
        car.s -= L;
        car.lap++;
        this.onLine(car);
      } else if (car.s < 0 && car.lap > 0) {
        car.s += L;
        car.lap--;
        car.invalidLap = true;
      }
    }

    onLine(car) {
      if (this.phase === 'countdown') return;
      const rt = this.raceTime;
      const lt = rt - car.lapStart;
      car.lapStart = rt;
      car.lastLap = lt;
      car.lapTimes.push(lt);
      if (!car.invalidLap) {
        if (car.bestLap == null || lt < car.bestLap) car.bestLap = lt;
        if (!this.fastest || lt < this.fastest.t) {
          this.fastest = { t: lt, car };
          if (car.lap > 1) this.log(`Fastest lap: ${car.name} ${SC.fmtTime(lt)}`, 'purple');
        }
      }
      car.invalidLap = false;
      car.pace = 1 + (this.rng() - 0.5) * 0.008;
      car.mistakeP = this.rng() < (car.mistakeRate || 0) ? this.rng() * this.track.L : null;
      if (this.brain) this.brain.lap(car);
      if (car.finished) return;
      if (this.timed && !this.winner && car === this.order[0]) {
        // re-estimate the race distance from the leader's recent pace
        const recent = car.lapTimes.slice(-3);
        const avg = recent.reduce((a, b) => a + b, 0) / recent.length;
        const left = this.duration - rt;
        this.R = left <= 0 ? car.lap : car.lap + Math.max(1, Math.ceil(left / avg));
        if (left <= 0) this.log('🏁 Time is up — the leader takes the chequered flag', 'good');
      }
      const done = this.timed ? car === this.order[0] && rt >= this.duration : car.lap >= this.R;
      if (!this.winner && done) {
        this.winner = car;
        this.finish(car);
      } else if (this.winner) this.finish(car);
    }

    finish(car, running) {
      car.finished = true;
      car.finishLap = car.lap;
      car.finishOrder = ++this.finishCount;
      car.finishTime = running ? null : this.raceTime;
      car.running = !!running;
      if (this.rules.mandatoryStop && car.stops === 0) car.penalties.push(['No mandatory pit stop', this.penaltyTime]);
      if (this.rules.twoCompounds && !(car.usedMask & T.compoundBit('W'))) {
        const dry = ['S', 'M', 'H'].filter((c) => car.usedMask & T.compoundBit(c)).length;
        if (dry < 2) car.penalties.push(['Used only one tyre compound', this.penaltyTime]);
      }
      car.penalty = car.penalties.reduce((a, p) => a + p[1], 0);
      if (!running) {
        if (car === this.winner) this.log(`🏁 ${car.name} wins the race!`, 'good');
        if (car.isPlayer) this.log(`🏁 You finished P${car.pos}`, 'good');
      }
      // the cool-down lap is driven on rails
      if (car.control === 'free') {
        this.toRail(car);
        car.v = Math.max(car.v, Math.hypot(car.vx, car.vy));
      }
    }

    afterMove(car, prevP) {
      const tr = this.track;
      const cfg = tr.cfg;
      const p = tr.rel(car.s);
      const crossed = (x) => prevP < x && p >= x && p - prevP < 60;
      if (this.phase === 'racing' && car.mode === 'race' && !car.finished) {
        if (crossed(cfg.pitEntry - 280)) this.decide(car);
        if (car.pitRequest && crossed(cfg.pitEntry)) this.enterPit(car);
      }
      if (car.mode === 'pit' && car.pit.phase === 'out' && p >= cfg.pitExit && p - cfg.pitExit < 60) this.exitPit(car);
      if (car.mistakeP != null && Math.abs(tr.wrap(car.s) - car.mistakeP) < 3) {
        car.mistakeP = null;
        this.botMistake(car, 1.3);
      }
      if (this.phase === 'racing') {
        const prog = car.lap * tr.L + car.s;
        const k = Math.floor(prog / this.cpStep);
        if (k > car.cpIdx && k >= 0) {
          car.cpIdx = k;
          if (this.cp[k] == null) this.cp[k] = this.raceTime;
          car.gap = this.raceTime - this.cp[k];
        }
      }
      if (car.fuel <= 0 && !car.outOfFuel && !car.finished) {
        car.outOfFuel = true;
        this.log(`${car.name} has run out of fuel!`, 'bad');
      }
      if (car.outOfFuel && car.v < 0.2 && Math.hypot(car.vx, car.vy) < 0.2 && car.mode !== 'pit' && !car.finished) {
        car.dnf = true;
        car.dnfReason = 'Out of fuel';
        this.log(`${car.name} retires — out of fuel`, 'bad');
      }
    }

    // ---------------- strategy decisions ----------------
    decide(car) {
      const remAfter = this.R - (car.lap + 1);
      if (remAfter <= 0 || this.winner) return;
      const wet = this.weather.wet;
      const cur = car.tyre.c;
      const perLapWear = this.track.L * T.wearPerMetre(cur, wet, this.s.wearMult) * car.agg;
      const lapsInStint = car.lap + 1 - car.stintStartLap;
      const wearEnd = car.tyre.wear - perLapWear * 0.15;
      const fuelEnd = car.fuel - this.fpl * 0.15;
      let reason = null;

      const cur0 = car.plan[car.stintIdx];
      const plannedNow = cur0 && car.stintIdx < car.plan.length - 1 && lapsInStint >= cur0.laps;
      const weatherShift = Math.abs(wet - car.planWet) > 0.12 || (cur !== 'W' && wet > car.wetThreshold) || (cur === 'W' && wet < 0.18);
      const tyreTrouble = !plannedNow && wearEnd - perLapWear < 0.02;
      const fuelTrouble = !plannedNow && fuelEnd - this.fpl < S.RESERVE * 0.5;
      if (weatherShift || tyreTrouble || fuelTrouble || car.planStale) {
        car.planStale = false;
        car.planWet = wet;
        const opts = S.plan(this.planOpts({
          laps: remAfter, wet, agg: car.agg, maxStops: 4,
          current: { c: cur, wear: Math.max(0, wearEnd), fuel: Math.max(0, fuelEnd), mask: car.usedMask, stopsDone: car.stops },
        }));
        if (opts.length) {
          const best = opts[0];
          const done = car.plan.slice(0, car.stintIdx);
          const first = best.stints[0];
          if (first && first.cont) {
            car.plan = done.concat([{ c: cur, laps: lapsInStint + first.laps }], best.stints.slice(1).map((x) => ({ c: x.c, laps: x.laps })));
          } else {
            car.plan = done.concat([{ c: cur, laps: lapsInStint }], best.stints.map((x) => ({ c: x.c, laps: x.laps })));
            reason = weatherShift ? (best.stints[0].c === 'W' ? 'Wets — it is raining' : 'Slicks — track drying') : tyreTrouble ? 'tyres are finished' : fuelTrouble ? 'fuel' : 'new strategy';
          }
          if (car.isPlayer) car.serviceEdited = false;
        }
      }
      const st = car.plan[car.stintIdx];
      if (!reason && st && car.stintIdx < car.plan.length - 1 && lapsInStint >= st.laps) reason = 'planned stop';
      if (!car.isPlayer || !car.serviceEdited) car.service = this.defaultService(car);
      if (!reason) return;
      if (car.isPlayer) {
        const sv = car.service;
        const text = `Strategist: box this lap (${reason}) → ${sv.c ? T.COMPOUNDS[sv.c].name : 'no tyres'}${sv.litres > 0.05 ? `, +${sv.litres.toFixed(1)} L` : ''}`;
        if (this.s.autoStrategist || car.autopilot) {
          car.pitRequest = true;
          this.log(text, 'box');
        } else this.log(text.replace('box this lap', 'suggests boxing') + ' — press P', 'box');
      } else car.pitRequest = true;
    }

    // Fuel and tyres for the car's next stop, from its plan.
    defaultService(car) {
      const remAfter = Math.max(1, this.R - (car.lap + 1));
      const next = car.plan[car.stintIdx + 1] || { c: car.tyre.c, laps: remAfter };
      const isLast = car.stintIdx + 1 >= car.plan.length - 1;
      const laps = isLast ? remAfter : Math.min(next.laps, remAfter);
      const fuelTarget = Math.min(CAR.tank, S.fuelNeed(laps, this.fpl));
      return this.makeService(car, next.c, fuelTarget);
    }

    makeService(car, c, fuelTarget) {
      const arrival = Math.max(0, car.fuel - this.fpl * 0.1);
      const litres = this.rules.refuel ? clamp(fuelTarget - arrival, 0, CAR.tank - arrival) : 0;
      return { c, fuelTarget, litres, time: S.serviceTime(this.s.crew, this.s.parallel, !!c, litres) };
    }

    enterPit(car) {
      car.mode = 'pit';
      car.pit = { phase: 'in', enteredAt: this.raceTime };
      car.pitRequest = false;
      if (!car.service) car.service = this.defaultService(car);
      if (car.control === 'free') this.toRail(car);
      if (car.isPlayer) this.log('Pit lane — limiter on, the crew is ready', 'box');
    }

    startService(car) {
      car.v = 0;
      car.s += this.track.rel(this.track.boxS(car.box) - car.s);
      const sv = this.makeService(car, car.service.c, car.service.fuelTarget);
      car.service = sv;
      car.pit.phase = 'service';
      car.pit.left = sv.time;
      car.pit.total = sv.time;
    }

    finishService(car) {
      const sv = car.service;
      const old = car.tyre.c;
      if (sv.c) {
        car.tyre = { c: sv.c, wear: 1, temp: 0.3 };
        car.usedMask |= T.compoundBit(sv.c);
        car.history.push(sv.c);
      }
      car.fuel = Math.min(CAR.tank, car.fuel + sv.litres);
      car.outOfFuel = false;
      car.stops++;
      const p = this.track.rel(car.s);
      car.stintStartLap = p < 0 ? car.lap + 1 : car.lap;
      car.stintIdx++;
      const planned = car.plan[car.stintIdx];
      if (!planned || planned.c !== car.tyre.c) {
        car.plan = car.plan.slice(0, car.stintIdx).concat([{ c: car.tyre.c, laps: Math.max(1, this.R - car.stintStartLap) }]);
        car.planStale = true;
      } else if (car.stintIdx >= car.plan.length - 1 && this.R - car.stintStartLap > planned.laps + 1) {
        // long races are planned a few stints ahead: extend the plan once its horizon is reached
        car.planStale = true;
      }
      const tyres = sv.c ? `${old}→${sv.c}` : 'no tyres';
      const fuel = sv.litres > 0.05 ? `, +${sv.litres.toFixed(1)} L` : '';
      this.log(`${car.isPlayer ? 'Your stop' : car.name}: ${tyres}${fuel} — ${sv.time.toFixed(1)} s`, car.isPlayer ? 'box' : 'pit');
      car.service = null;
      car.serviceEdited = false;
      car.pit.phase = 'out';
    }

    exitPit(car) {
      car.mode = 'race';
      car.pit = null;
      if (car.isPlayer && !car.autopilot && !car.finished) this.toFree(car);
      car.service = this.defaultService(car);
    }

    toRail(car) {
      car.control = 'rail';
      car.v = Math.max(0, car.vx * Math.cos(car.heading) + car.vy * Math.sin(car.heading));
      car.dKick = 0;
      car.latV = 0;
      car.err = null;
    }

    toFree(car) {
      car.control = 'free';
      car.vx = Math.cos(car.heading) * car.v;
      car.vy = Math.sin(car.heading) * car.v;
      car.yawRate = 0;
      car.phys = null;
      car.rev = false;
    }

    // ---------------- AI / rail driving ----------------
    traffic(car, vT, rl, dt) {
      const tr = this.track;
      const lim = tr.half - 1;
      let ahead = null;
      let aheadGap = Infinity;
      let drag = 1;
      for (const o of this.cars) {
        if (o === car || o.dnf || o.finished) continue;
        if (o.mode === 'pit' && tr.pitBlend(o.s) > 0.4) continue;
        const gap = tr.rel(o.s - car.s);
        const lat = o.d - car.d;
        if (gap > 0 && gap < 45 && Math.abs(lat) < 2.0 && gap < aheadGap) {
          ahead = o;
          aheadGap = gap;
        }
      }
      const side = this.sideRoom(car);
      if (!ahead) {
        if (car.overtakeT > 0) car.overtakeT -= dt;
        const t = { vT, dT: car.overtakeT > 0 ? car.overtakeD : rl, drag };
        return this.applySideRoom(car, t, side);
      }
      const lat = ahead.d - car.d;
      const aheadV = ahead.control === 'free' ? Math.hypot(ahead.vx, ahead.vy) : ahead.v;
      if (aheadGap < 30 && Math.abs(lat) < 1.3) drag = 1 - 0.3 * (1 - aheadGap / 30);
      const wantsBy = vT > aheadV + 0.4 || car.v > aheadV + 0.6;
      if (wantsBy && aheadGap < 24 && car.overtakeT <= 0) {
        const sides = [ahead.d - 2.4, ahead.d + 2.4]
          .filter((d) => Math.abs(d) <= lim)
          .filter((d) => !this.cars.some((c) => c !== car && c !== ahead && !c.finished && c.mode !== 'pit' &&
            Math.abs(c.d - d) < 2 && Math.abs(tr.rel(c.s - car.s) - 3) < 11))
          .sort((a, b) => Math.abs(a - rl) - Math.abs(b - rl));
        if (sides.length) {
          car.overtakeD = sides[0];
          car.overtakeT = 3.5;
          car.overtakeT0 = (car.overtakeT0 || 0) + 1;
        }
      }
      let dT = rl;
      if (car.overtakeT > 0) {
        car.overtakeT -= dt;
        dT = car.overtakeD;
      }
      if (Math.abs(lat) < 1.8) {
        vT = Math.min(vT, aheadV + Math.max(0, aheadGap - 6) * 0.7);
        if (aheadGap < 5) vT = Math.min(vT, aheadV - 0.6);
      }
      return this.applySideRoom(car, { vT, dT, drag }, side);
    }

    // Lateral space left by cars running alongside: [lo, hi] offsets this car may steer to without
    // leaning on anyone, plus the speed of whoever is squeezing it.
    sideRoom(car) {
      const tr = this.track;
      const gapMin = CAR.width + 0.55;
      let lo = -Infinity;
      let hi = Infinity;
      let squeezeV = null;
      for (const o of this.cars) {
        if (o === car || o.dnf || o.finished || o.mode === 'pit') continue;
        const gap = tr.rel(o.s - car.s);
        if (Math.abs(gap) > CAR.length + 1.2) continue;
        const lat = o.d - car.d;
        const gm = gapMin + (this.brain ? this.brain.margin(o) : 0);
        if (Math.abs(lat) > gm + 1.2) continue;
        if (lat >= 0) hi = Math.min(hi, o.d - gm);
        else lo = Math.max(lo, o.d + gm);
        const ov = o.control === 'free' ? Math.hypot(o.vx, o.vy) : o.v;
        if (gap > -0.5) squeezeV = squeezeV == null ? ov : Math.min(squeezeV, ov);
      }
      return { lo, hi, squeezeV };
    }

    applySideRoom(car, t, side) {
      if (this.brain && car.brain) t = this.brain.adjust(car, t, this.track.half - 1);
      if (side.lo === -Infinity && side.hi === Infinity) return t;
      const lim = this.track.half + this.track.cfg.runoff - 1.2;
      const lo = Math.max(side.lo, -lim);
      const hi = Math.min(side.hi, lim);
      if (lo <= hi) t.dT = clamp(t.dT, lo, hi);
      else {
        // no room alongside: stay in the middle of the gap and drop back rather than lean on anyone
        t.dT = clamp((side.lo + side.hi) / 2, -lim, lim);
        if (side.squeezeV != null) t.vT = Math.min(t.vT, side.squeezeV - 1.5);
      }
      if (car.overtakeT > 0 && (car.overtakeD < lo - 0.3 || car.overtakeD > hi + 0.3)) car.overtakeT = 0;
      return t;
    }

    // Follow the car ahead in the pit lane instead of driving through it.
    pitTraffic(car, vT) {
      const tr = this.track;
      for (const o of this.cars) {
        if (o === car || o.mode !== 'pit' || o.dnf) continue;
        const gap = tr.rel(o.s - car.s);
        if (gap <= 0 || gap > 20 || Math.abs(o.d - car.d) > 1.9) continue;
        // a car still parked in its box isn't in the way of someone in the fast lane
        if (o.pit.phase !== 'in' && o.v < 0.5 && Math.abs(o.d - tr.cfg.pitOffset) > 2.5) continue;
        vT = Math.min(vT, Math.max(0, o.v + (gap - 6) * 0.8));
        if (gap < 4.5) vT = Math.min(vT, Math.max(0, o.v - 0.8));
      }
      // pulling out of the box: give way to anyone moving down the fast lane beside or just behind,
      // but only while still parked in the box lane, and never for more than a few seconds
      const lane = tr.cfg.pitOffset;
      const boxLane = lane + Math.sign(lane) * 3.6;
      if (car.pit.phase === 'out' && Math.abs(car.d - boxLane) < 0.8 && (car.pit.wait || 0) < 4) {
        const blocked = this.cars.some((o) => {
          if (o === car || o.mode !== 'pit' || o.dnf || o.v < 1 || Math.abs(o.d - lane) > 1.5) return false;
          const behind = tr.rel(car.s - o.s);
          return behind > -4.5 && behind < 14;
        });
        if (blocked) vT = 0;
      }
      return vT;
    }

    // Unsafe-release check: hold a serviced car while someone is coming down the fast lane.
    pitLaneClear(car) {
      const tr = this.track;
      const lane = tr.cfg.pitOffset;
      if ((car.pit.hold || 0) > 5) return true;
      return !this.cars.some((o) => {
        if (o === car || o.mode !== 'pit' || o.dnf || o.pit.phase === 'service' || o.v < 1) return false;
        const behind = tr.rel(car.s - o.s);
        return behind > -4 && behind < 28 && Math.abs(o.d - lane) < 2.2;
      });
    }

    pitSpeed(car, vRace) {
      const tr = this.track;
      const p = tr.rel(car.s);
      const boxP = tr.boxS(car.box);
      let vT = vRace;
      if (car.pit.phase === 'in') {
        const toLane = tr.laneStart - p;
        vT = Math.min(vT, toLane > 0 ? Math.sqrt(S.PIT_SPEED ** 2 + 2 * 5.5 * toLane) : S.PIT_SPEED);
        const toBox = boxP - p;
        vT = Math.min(vT, Math.max(0.8, Math.sqrt(Math.max(0, 2 * 4.5 * (toBox - 0.3)))));
      } else if (p < tr.laneEnd) vT = Math.min(vT, S.PIT_SPEED);
      return vT;
    }

    pitLateral(car, rl) {
      const tr = this.track;
      const po = tr.cfg.pitOffset;
      const p = tr.rel(car.s);
      // swing into the box only in the last few metres, clear of the neighbouring boxes
      const near = smoothstep(1 - Math.max(0, Math.abs(p - tr.boxS(car.box)) - 1.5) / 6);
      const lane = po + Math.sign(po) * 3.6 * near;
      return rl + (lane - rl) * tr.pitBlend(car.s);
    }

    // What a racing car wants right now: speed, lateral position and slipstream, from its pace, the
    // car ahead and anyone alongside. Shared by bots on rails and bots driving the full physics.
    targets(car, dt, mu, phys) {
      const tr = this.track;
      const rl = tr.sample(tr.RLD, car.s);
      const br = this.brain && car.brain ? this.brain : null;
      const v = phys ? Math.max(0, car.speed || 0) : car.v;
      const look = car.s + v * 0.12;
      let K = Math.sqrt(mu) * (br ? br.paceAt(car, look) : car.skill) * car.pace * (car.paceScale || 1);
      if (car.err && car.err.kind === 'late') K *= 1.05;
      let vT = tr.sample(tr.PROF, look) * K;
      let dT = rl;
      let drag = 1;
      let hindered = car.finished || car.slowT > 0 || !!car.err;
      if (car.finished) vT *= 0.8;
      if (car.slowT > 0) {
        car.slowT -= dt;
        vT *= 0.82;
      }
      if (!car.finished) {
        const t = this.traffic(car, vT, rl, dt);
        if (t.vT < vT - 0.3 || car.overtakeT > 0) hindered = true;
        vT = t.vT;
        dT = t.dT;
        drag = t.drag;
      }
      if (this.phase !== 'racing' || this.raceTime < car.reaction) vT = 0;
      if (br) br.railStep(car, dt, hindered);
      return { vT, dT, drag, K, err: car.err };
    }

    stepRail(car, dt) {
      const tr = this.track;
      const wet = this.weather.wet;
      if (car.mode === 'pit' && car.pit.phase === 'service') {
        car.v = 0;
        car.throttle = 0;
        car.rpm = CAR.idleRpm;
        car.pit.left -= dt;
        if (car.pit.left <= 0) car.pit.hold = (car.pit.hold || 0) + dt;
        if (car.pit.left <= 0 && this.pitLaneClear(car)) this.finishService(car);
        return;
      }
      const mu = T.tyreGrip(car.tyre, wet);
      const mass = SC.Car.massWithFuel(car.fuel);
      const rl = tr.sample(tr.RLD, car.s);
      let vT, dT, drag;
      if (car.mode === 'pit') {
        vT = this.pitTraffic(car, this.pitSpeed(car, tr.sample(tr.PROF, car.s + car.v * 0.12) * Math.sqrt(mu)));
        dT = this.pitLateral(car, rl);
        drag = 1;
        if (car.pit.phase === 'out' && car.v < 0.5) car.pit.wait = (car.pit.wait || 0) + dt;
        if (car.pit.phase === 'in' && tr.rel(car.s) >= tr.boxS(car.box) - 0.6) {
          this.startService(car);
          return;
        }
        if (this.phase !== 'racing') vT = 0;
        if (this.brain && car.brain) this.brain.railStep(car, dt, true);
      } else {
        const tg = this.targets(car, dt, mu, false);
        vT = tg.vT;
        dT = tg.dT;
        drag = tg.drag;
        vT *= 1 - 0.012 * Math.abs(car.d - rl);
        if (Math.abs(car.d) > tr.half + 0.3) vT *= 0.75;
      }

      let a = 0;
      const climb = G * tr.sample(tr.GRADE, car.s) + (car.mode === 'pit' ? 0 : SC.Car.scrub(car.v, tr.sample(tr.RK, car.s), mu));
      const aMax = SC.Car.maxAccel(car.v, mass, mu, drag) - climb;
      if (car.v < vT && car.fuel > 0 && aMax > 0) a = Math.min(aMax, (vT - car.v) / dt);
      else if (car.v > vT) a = -Math.min(mu * G + climb, (car.v - vT) / dt);
      else a = -SC.Car.resistance(car.v, mass, drag) / mass - climb;
      car.brakeOn = a < -2.5;
      car.v = Math.max(0, car.v + a * dt);
      const force = a >= -climb ? mass * 1.05 * a + SC.Car.resistance(car.v, mass, drag) + mass * climb : 0;
      car.gear = SC.Car.bestGear(car.v);
      const fMax = Math.max(1, SC.Car.wheelForce(car.v, car.gear, 1));
      car.throttle = clamp(force / fMax, 0, 1);
      car.rpm = SC.Car.engineRpm(car.v, car.gear, car.throttle);
      car.fuel = Math.max(0, car.fuel - SC.Car.fuelRate((force * car.v) / CAR.efficiency) * dt * this.s.fuelMult);

      const inPit = car.mode === 'pit';
      const latMax = inPit ? 5 : 1.2 + 0.1 * car.v;
      // follow the line's own sideways drift, correct the error smoothly, and never jerk sideways
      const ff = inPit ? 0 : (tr.sample(tr.RLD, car.s + 1) - tr.sample(tr.RLD, car.s)) * car.v;
      const want = clamp(ff + (dT - car.d) * (inPit ? 5 : 2), -latMax, latMax);
      const aLat = inPit ? 14 : 4 + 0.12 * car.v;
      car.latV = (car.latV || 0) + clamp(want - (car.latV || 0), -aLat * dt, aLat * dt);
      const dd = car.latV + car.dKick;
      car.dKick *= Math.exp(-5 * dt);
      car.d += dd * dt;
      if (car.mode !== 'pit') {
        const lim = tr.half + tr.cfg.runoff - 1;
        car.d = clamp(car.d, -lim, lim);
      }
      this.moveS(car, car.v * dt * tr.sRate(car.s, car.d));
      const q = tr.pos(car.s, car.d);
      car.x = q.x;
      car.y = q.y;
      car.heading = tr.heading(car.s) + Math.atan2(dd, Math.max(3, car.v));
      car.vx = Math.cos(car.heading) * car.v;
      car.vy = Math.sin(car.heading) * car.v;
      car.speed = car.v;
      this.wearTyres(car, car.v * dt, car.mode === 'pit' ? 0.3 : car.agg * (car.brain && car.brain.mind === 'manage' ? 0.85 : 1));
    }

    wearTyres(car, dist, factor) {
      const t = car.tyre;
      t.wear = Math.max(0, t.wear - dist * T.wearPerMetre(t.c, this.weather.wet, this.s.wearMult) * factor);
      t.temp = Math.min(1, t.temp + dist / 1500);
      if (t.wear <= 0 && !t.dead && !car.finished) {
        t.dead = true;
        this.log(`${car.isPlayer ? 'Your' : car.name + "'s"} tyres are completely worn out!`, 'bad');
        if (!car.isPlayer || this.s.autoStrategist || car.autopilot) car.planStale = true;
      }
    }

    // ---------------- player physics ----------------
    // Grip and rolling drag under one wheel, from its lateral offset on the track.
    surfaceAt(car, x, y) {
      const tr = this.track;
      const d = car.d + (x - car.x) * tr.sample(tr.NX, car.s) + (y - car.y) * tr.sample(tr.NY, car.s);
      const ad = Math.abs(d);
      if (ad <= tr.half + 0.3) return SURF.track;
      const c = tr.cfg;
      const p = tr.rel(car.s);
      if (Math.sign(d) === Math.sign(c.pitOffset) && p > c.pitEntry - 20 && p < c.pitExit + 20) return SURF.asphalt;
      return SURF[c.runoffSurface] || SURF.grass;
    }

    stepFree(car, dt, input) {
      const tr = this.track;
      const P = SC.Physics;
      const hold = this.phase !== 'racing';
      let thr = input.throttle;
      let brk = input.brake;
      if (car.fuel <= 0) thr = 0;
      const mass = SC.Car.massWithFuel(car.fuel);
      const ch = Math.cos(car.heading);
      const sh = Math.sin(car.heading);
      const vF = car.vx * ch + car.vy * sh;

      // reverse: hold the brake at a standstill; throttle selects first again
      if (!car.rev && brk > 0.3 && thr < 0.05 && Math.abs(vF) < 0.4 && !hold) {
        car.rev = true;
        car.gear = 0;
      } else if (car.rev && thr > 0.05) {
        if (vF < -0.5) {
          brk = thr;
          thr = 0;
        } else car.rev = false;
      }
      if (car.rev) {
        const t = thr;
        thr = brk;
        brk = t;
      }

      if (!car.rev && (!car.isPlayer || this.s.gearbox === 'auto')) this.autoShift(car, vF, thr, brk);
      else if (!car.rev) {
        if (input.shiftUp && car.gear < CAR.gears.length - 1) {
          car.gear++;
          car.shiftT = 0.18;
        }
        if (input.shiftDown && car.gear > 0) {
          car.gear--;
          car.shiftT = 0.18;
        }
      }
      input.shiftUp = input.shiftDown = false;

      if (hold) {
        car.rpm += (CAR.idleRpm + thr * 5200 - car.rpm) * Math.min(1, dt * 6);
        car.throttle = thr;
        car.vx = car.vy = car.yawRate = 0;
        car.phys = null;
        return;
      }

      const grade = G * tr.sample(tr.GRADE, car.s);
      const tx = tr.sample(tr.TX, car.s);
      const ty = tr.sample(tr.TY, car.s);
      // bots run the same driving-aid setting the player chose — no free assist the player didn't pick
      const assists = this.s.assists || 'full';
      const dragMul = car.isPlayer ? this.slipstream(car) : car.slipDrag || 1;
      const mu = T.tyreGrip(car.tyre, this.weather.wet);
      const steer = car.isPlayer ? this.steerAssist(car, input.steer, mu, assists) : input.steer;
      const out = P.step(
        car,
        { throttle: thr, brake: brk, steer },
        {
          mu,
          mass,
          surface: (x, y) => this.surfaceAt(car, x, y),
          gx: -grade * tx,
          gy: -grade * ty,
          dragMul,
          abs: assists !== 'off',
          tc: assists === 'full',
          esc: assists === 'full',
        },
        dt
      );
      car.shiftT = Math.max(0, car.shiftT - dt);

      const pr = tr.project(car.x, car.y, car.s);
      this.moveS(car, tr.rel(pr.s - car.s));
      car.d = pr.d;
      this.barrierContact(car, mass);

      car.fuel = Math.max(0, car.fuel - SC.Car.fuelRate(out.enginePower) * dt * this.s.fuelMult);
      // wear follows the energy the tyres dissipate while sliding, on top of normal running
      const muG = T.tyreGrip(car.tyre, this.weather.wet) * G;
      const acc = Math.hypot(car.phys.axF, car.phys.ayF);
      const u = Math.min(1.5, acc / muG);
      const slide = Math.min(3, out.slidePower / (mass * muG * 1.5));
      const offTrack = Math.abs(car.d) > tr.half + 0.5;
      const factor = (0.45 + 1.1 * u * u + 0.5 * slide) * (offTrack ? 1.4 : 1);
      this.wearTyres(car, Math.abs(car.speed) * dt, factor);
    }

    // Automatic gearbox, shared by the player's auto option and every bot.
    autoShift(car, vF, thr, brk) {
      const F = (gear) => SC.Car.wheelForce(Math.max(0, vF), gear, 1);
      const top = CAR.gears.length - 1;
      let g = car.gear;
      if (vF < 1) g = 0;
      // upshift at the point where the next gear pulls harder, or just before the limiter
      else if (g < top && (car.rpm > 6150 || F(g + 1) > F(g)) && SC.Car.rpmFor(vF, g + 1) > 2800) g++;
      // on the power, drop a gear as soon as it pulls clearly harder; on the brakes, keep the revs up for the exit
      else if (g > 0 && SC.Car.rpmFor(vF, g - 1) < 5900 && (F(g - 1) > F(g) * 1.06 || (brk > 0.1 && SC.Car.rpmFor(vF, g) < 3200)))
        g--;
      if (g !== car.gear) {
        // part-throttle or braking shifts are quicker to settle than a flat-out upshift
        car.shiftT = g > car.gear ? 0.15 : 0.12;
        car.gear = g;
      }
    }

    // A digital key (or a twitchy pad) asks for full lock the instant it's pressed — the bots never do
    // that; their pure-pursuit steering only ever asks for exactly the angle the coming curvature needs.
    // On the Full driving-aid tier, hold the player to the same standard: cap steering to a bit more than
    // that ideal angle, so mashing the key on a gentle bend doesn't ask for more lock than the corner
    // wants and throw the car into a slide the bots would never suffer for the same corner. It only caps
    // steering that's already pointed the way the line wants — an opposite-lock correction, a deliberate
    // drift, anything that isn't "turning the way the corner goes" is left alone.
    steerAssist(car, raw, mu, assists) {
      if (assists !== 'full' || Math.abs(raw) < 1e-3) return raw;
      const ideal = SC.Driver.lineSteer(this.track, car, mu);
      if (Math.sign(raw) !== Math.sign(ideal)) return raw;
      const cap = Math.abs(ideal) * 1.35 + 0.05;
      return Math.abs(raw) > cap ? Math.sign(raw) * cap : raw;
    }

    // Tow from a car close ahead on roughly the same line (drag multiplier).
    slipstream(car) {
      const tr = this.track;
      let drag = 1;
      for (const o of this.cars) {
        if (o === car || o.dnf || o.finished || o.mode === 'pit') continue;
        const gap = tr.rel(o.s - car.s);
        if (gap > 0 && gap < 30 && Math.abs(o.d - car.d) < 1.3) drag = Math.min(drag, 1 - 0.3 * (1 - gap / 30));
      }
      return drag;
    }

    // Bots drive the full car physics at normal speed. Under time warp, in the pits, after the flag, or
    // while recovering from a spin they fall back to the rail model.
    botControl(car) {
      const tr = this.track;
      if (car.recoverT > 0) car.recoverT -= 1 / 120;
      const want = this.physBots && this.warp === 1 && car.mode === 'race' && !car.finished && !(car.recoverT > 0);
      if (!want) {
        if (car.control === 'free') this.toRail(car);
        return;
      }
      if (car.control === 'rail') {
        this.toFree(car);
        return;
      }
      if (this.phase !== 'racing' || this.raceTime < car.reaction + 3) return;
      // spun or stuck: rejoin
      const off = Math.abs(SC.util.wrapAngle(car.heading - tr.heading(car.s)));
      const v = Math.hypot(car.vx, car.vy);
      car.stuckT = off > 1.4 || (v < 2.5 && !car.outOfFuel) ? (car.stuckT || 0) + 1 / 120 : 0;
      if (car.stuckT > (off > 1.4 ? 1.2 : 2.5)) {
        car.stuckT = 0;
        this.toRail(car);
        car.v = Math.min(car.v, 3);
        car.recoverT = 4;
        if (Math.abs(car.pos - this.player.pos) <= 3) this.log(`${car.name} spins and rejoins`, 'info');
      }
    }

    botInput(car, dt) {
      const mu = T.tyreGrip(car.tyre, this.weather.wet);
      const tg = this.targets(car, dt, mu, true);
      car.slipDrag = tg.drag;
      if (car.err && (car.err.t -= dt) <= 0) car.err = null;
      return SC.Driver.control(this, car, tg, mu);
    }

    // A driving error: on rails a sideways twitch, in the physics a braking point missed or a line run wide
    // that the car then has to live with.
    botMistake(car, severity = 1) {
      const tr = this.track;
      const rng = this.rng;
      const k = tr.sample(tr.KC, car.s + 25);
      const outward = -Math.sign(k || 1);
      if (car.control === 'free') {
        const late = rng() < 0.55;
        car.err = { kind: late ? 'late' : 'wide', d: outward * (1.2 + 2.2 * rng()) * severity, t: 1.6 + rng() * 1.4 };
      } else {
        car.slowT = Math.max(car.slowT, (0.7 + rng() * 0.9) * severity);
        car.dKick += outward * (1.2 + 2 * rng());
      }
    }

    // Car corners against the barriers: push back out and apply a rigid-body impulse (with scraping friction),
    // so a glancing hit spins the car the way the corner struck.
    barrierContact(car, mass) {
      const tr = this.track;
      const lim = tr.limits(car.s);
      const nx = tr.sample(tr.NX, car.s);
      const ny = tr.sample(tr.NY, car.s);
      const ch = Math.cos(car.heading);
      const sh = Math.sin(car.heading);
      const hl = CAR.length / 2;
      const hw = CAR.width / 2;
      let hit = 0;
      for (const side of [1, -1]) {
        const wall = side > 0 ? lim.hi + hw : lim.lo - hw;
        let pen = 0;
        let rx = 0;
        let ry = 0;
        for (const [lx, ly] of [[hl, hw], [hl, -hw], [-hl, hw], [-hl, -hw]]) {
          const ox = lx * ch - ly * sh;
          const oy = lx * sh + ly * ch;
          const p = (car.d + ox * nx + oy * ny - wall) * side;
          if (p > pen) {
            pen = p;
            rx = ox;
            ry = oy;
          }
        }
        if (pen <= 0) continue;
        car.x -= nx * pen * side;
        car.y -= ny * pen * side;
        car.d -= pen * side;
        hit = Math.max(hit, SC.Physics.barrierHit(car, nx * side, ny * side, rx, ry, mass));
      }
      if (hit > 5 && this.clock - (car.lastHit || 0) > 1.5) {
        car.lastHit = this.clock;
        this.log('Ouch — that was the barrier!', 'bad');
      }
    }

    // ---------------- contact ----------------
    collide() {
      const cars = this.cars;
      for (let i = 0; i < cars.length; i++) {
        const a = cars[i];
        if (a.finished || a.dnf) continue;
        for (let j = i + 1; j < cars.length; j++) {
          const b = cars[j];
          if (b.finished || b.dnf) continue;
          if ((a.mode === 'pit') !== (b.mode === 'pit') || (a.mode === 'pit' && b.mode === 'pit')) continue;
          if ((a.x - b.x) ** 2 + (a.y - b.y) ** 2 > 16) continue;
          const hit = sat(a, b);
          if (!hit) continue;
          const { nx, ny, depth } = hit;
          // share the separation, but a car pinned against its barrier can't give way
          const roomA = this.room(a, -nx, -ny);
          const roomB = this.room(b, nx, ny);
          let da = Math.min(depth * 0.5, roomA);
          const db = Math.min(depth - da, roomB);
          da = Math.min(depth - db, roomA);
          this.shove(a, -nx * da, -ny * da);
          this.shove(b, nx * db, ny * db);
          const rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
          if (rel < 0) {
            const jimp = (-(1 + 0.25) * rel) / 2;
            const wa = roomA < 0.05 ? 0 : roomB < 0.05 ? 2 : 1;
            const wb = 2 - wa;
            // contact point: midway between each car's corner nearest the other
            const ca = corner(a, nx, ny);
            const cb = corner(b, -nx, -ny);
            const px = (a.x + ca[0] + b.x + cb[0]) / 2;
            const py = (a.y + ca[1] + b.y + cb[1]) / 2;
            this.kick(a, -nx * jimp * wa, -ny * jimp * wa, px - a.x, py - a.y);
            this.kick(b, nx * jimp * wb, ny * jimp * wb, px - b.x, py - b.y);
            if (this.brain && jimp > 1) this.brain.contact(a, b, nx, ny);
            if ((a.isPlayer || b.isPlayer) && jimp > 2.5 && this.clock - (this.lastContact || 0) > 1) {
              this.lastContact = this.clock;
              this.log(`Contact with ${a.isPlayer ? b.name : a.name}!`, 'bad');
            }
          }
        }
      }
    }

    // How far a car can be pushed along (ux, uy) before its lateral limit (barrier / run-off edge).
    room(car, ux, uy) {
      const tr = this.track;
      const un = ux * tr.sample(tr.NX, car.s) + uy * tr.sample(tr.NY, car.s);
      if (Math.abs(un) < 0.2) return Infinity;
      let lo;
      let hi;
      if (car.control === 'free') ({ lo, hi } = tr.limits(car.s));
      else {
        hi = tr.half + tr.cfg.runoff - 1;
        lo = -hi;
      }
      const r = un > 0 ? (hi - car.d) / un : (car.d - lo) / -un;
      return Math.max(0, r);
    }

    shove(car, dx, dy) {
      if (car.control === 'free') {
        car.x += dx;
        car.y += dy;
        const pr = this.track.project(car.x, car.y, car.s);
        const lim = this.track.limits(car.s);
        const d = clamp(pr.d, lim.lo, lim.hi);
        if (d !== pr.d) {
          car.x += this.track.sample(this.track.NX, car.s) * (d - pr.d);
          car.y += this.track.sample(this.track.NY, car.s) * (d - pr.d);
        }
        car.d = d;
        return;
      }
      const tr = this.track;
      const lim = tr.half + tr.cfg.runoff - 1;
      car.d = clamp(car.d + dx * tr.sample(tr.NX, car.s) + dy * tr.sample(tr.NY, car.s), -lim, lim);
      this.moveS(car, dx * tr.sample(tr.TX, car.s) + dy * tr.sample(tr.TY, car.s));
      const q = tr.pos(car.s, car.d);
      car.x = q.x;
      car.y = q.y;
    }

    kick(car, ix, iy, rx, ry) {
      if (car.control === 'free') {
        SC.Physics.kick(car, ix, iy, rx, ry);
        return;
      }
      const tr = this.track;
      car.v = Math.max(0, car.v + ix * tr.sample(tr.TX, car.s) + iy * tr.sample(tr.TY, car.s));
      car.dKick += ix * tr.sample(tr.NX, car.s) + iy * tr.sample(tr.NY, car.s);
      car.vx = Math.cos(car.heading) * car.v;
      car.vy = Math.sin(car.heading) * car.v;
    }

    // Nudge the field's pace a little towards the player's, scaled by difficulty: bots that have broken
    // clear ease off a fraction, bots that have fallen behind push a little harder. Small and slow enough
    // that it never overturns a real pace difference — it only takes the sting out of a single mistake.
    rubberBand(dt) {
      const band = DIFFICULTY[this.s.difficulty].band;
      const p = this.player;
      if (!band || this.phase !== 'racing' || p.dnf) return;
      const L = this.track.L;
      const vAvg = L / this.cal.T0;
      const pp = p.lap * L + p.s;
      for (const c of this.cars) {
        if (c.isPlayer) continue;
        if (c.dnf || c.finished || c.mode !== 'race') {
          c.paceScale = 1;
          continue;
        }
        const gapSec = (c.lap * L + c.s - pp) / vAvg;
        const over = clamp((Math.abs(gapSec) - 5) / 20, 0, 1);
        const want = 1 - Math.sign(gapSec) * band * over;
        c.paceScale = (c.paceScale || 1) + clamp(want - (c.paceScale || 1), -dt * 0.04, dt * 0.04);
      }
    }

    // ---------------- ordering + results ----------------
    updateOrder() {
      const L = this.track.L;
      const key = (c) =>
        c.dnf ? -1e12 + c.lap * L + c.s : c.finished ? c.finishLap * L + L - 1 - c.finishOrder * 1e-3 : c.lap * L + c.s;
      this.order = this.cars.slice().sort((a, b) => key(b) - key(a));
      this.order.forEach((c, i) => (c.pos = i + 1));
    }

    results() {
      const L = this.track.L;
      const rows = this.cars.map((c) => ({
        car: c,
        laps: c.finished ? c.finishLap : c.lap,
        total: c.finishTime != null ? c.finishTime + c.penalty : null,
      }));
      rows.sort((a, b) => {
        if (a.car.dnf !== b.car.dnf) return a.car.dnf ? 1 : -1;
        if (b.laps !== a.laps) return b.laps - a.laps;
        if (a.total != null && b.total != null) return a.total - b.total;
        if (a.total != null) return -1;
        if (b.total != null) return 1;
        return b.car.s - a.car.s;
      });
      const win = rows[0];
      return rows.map((r, i) => ({
        pos: i + 1,
        car: r.car,
        laps: r.laps,
        total: r.total,
        gap: i === 0 ? null : r.laps < win.laps ? `+${win.laps - r.laps} lap${win.laps - r.laps > 1 ? 's' : ''}` : r.total != null && win.total != null ? '+' + (r.total - win.total).toFixed(3) : '',
        status: r.car.dnf ? 'DNF — ' + r.car.dnfReason : r.car.running ? 'Not classified (still running)' : '',
        _L: L,
      }));
    }

    // ---------------- player pit-wall controls ----------------
    playerTogglePit() {
      const p = this.player;
      if (p.mode === 'pit' || p.finished) return;
      p.pitRequest = !p.pitRequest;
      if (!p.service) p.service = this.defaultService(p);
      this.log(p.pitRequest ? 'Pit request confirmed — box at the end of this lap' : 'Pit request cancelled', 'box');
    }
    playerCycleCompound(dir) {
      const p = this.player;
      if (p.mode === 'pit' && p.pit.phase !== 'in') return;
      if (!p.service) p.service = this.defaultService(p);
      const list = ['S', 'M', 'H', 'W', null];
      const i = list.indexOf(p.service.c);
      const c = list[(i + dir + list.length) % list.length];
      p.service = this.makeService(p, c, p.service.fuelTarget);
      p.serviceEdited = true;
    }
    playerAdjustFuel(delta) {
      const p = this.player;
      if (!this.rules.refuel || (p.mode === 'pit' && p.pit.phase !== 'in')) return;
      if (!p.service) p.service = this.defaultService(p);
      p.service = this.makeService(p, p.service.c, clamp(p.service.fuelTarget + delta, 0, CAR.tank));
      p.serviceEdited = true;
    }
    playerReplan() {
      const p = this.player;
      p.planStale = true;
      p.serviceEdited = false;
      const rem = this.R - (p.lap + 1);
      if (rem <= 0) return;
      const opts = S.plan(this.planOpts({
        laps: rem, wet: this.weather.wet, maxStops: 4,
        current: { c: p.tyre.c, wear: p.tyre.wear, fuel: p.fuel, mask: p.usedMask, stopsDone: p.stops },
      }));
      if (!opts.length) {
        this.log('Strategist: no valid plan found from here', 'bad');
        return;
      }
      const best = opts[0];
      const lapsInStint = p.lap + 1 - p.stintStartLap;
      const done = p.plan.slice(0, p.stintIdx);
      const first = best.stints[0];
      if (first && first.cont) p.plan = done.concat([{ c: p.tyre.c, laps: lapsInStint + first.laps }], best.stints.slice(1).map((x) => ({ c: x.c, laps: x.laps })));
      else p.plan = done.concat([{ c: p.tyre.c, laps: lapsInStint }], best.stints.map((x) => ({ c: x.c, laps: x.laps })));
      p.planStale = false;
      p.planWet = this.weather.wet;
      p.service = this.defaultService(p);
      const next = p.plan[p.stintIdx + 1];
      this.log(`Strategist: ${next ? `box after lap ${p.stintStartLap + p.plan[p.stintIdx].laps} for ${T.COMPOUNDS[next.c].name}` : 'no more stops, bring it home'}`, 'box');
    }
    setAutopilot(on) {
      const p = this.player;
      if (p.finished || p.mode === 'pit') return;
      p.autopilot = on;
      if (on) {
        p.control = 'rail';
        p.v = Math.max(0, p.vx * Math.cos(p.heading) + p.vy * Math.sin(p.heading));
        p.dKick = 0;
        p.latV = 0;
      } else this.toFree(p);
    }

    // Laps the player's next planned stop is after (1-based), or null.
    playerNextStopLap() {
      const p = this.player;
      if (p.stintIdx >= p.plan.length - 1) return null;
      return p.stintStartLap + p.plan[p.stintIdx].laps;
    }
  }

  SC.fmtTime = (t) => {
    if (t == null || !isFinite(t)) return '—';
    const m = Math.floor(t / 60);
    const s = t - m * 60;
    return (m > 0 ? m + ':' + s.toFixed(3).padStart(6, '0') : s.toFixed(3));
  };
  SC.Race = Race;
  SC.DIFFICULTY = DIFFICULTY;
})();
