// Lap-time model + pit strategy planner.
//
// A quasi-steady lap simulation (same engine/tyre model the cars use) is run per track to learn how
// lap time responds to grip and mass, what a lap costs in fuel and how much time a pit lane
// drive-through loses. The planner then runs a dynamic programme over (laps covered, stops,
// compound, compounds used) to find the fastest stint plans that satisfy the race rules.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const { CAR } = SC.Car;
  const T = SC.Tyres;

  const PIT_SPEED = 60 / 3.6;
  const FUEL_MARGIN = 1.04;
  const RESERVE = 0.4; // litres left in the tank at the end of a stint
  const LONG_RACE = 60; // laps; longer races are planned over a rolling horizon

  const CREWS = {
    pro: { name: 'Pro crew', fixed: 2.0, tyres: 6.5, rate: 2.4 },
    club: { name: 'Club crew', fixed: 3.0, tyres: 14, rate: 1.2 },
    amateur: { name: 'Mates with a jack', fixed: 5, tyres: 32, rate: 0.5 },
  };

  function serviceTime(crew, parallel, tyres, litres) {
    const c = CREWS[crew];
    const tt = tyres ? c.tyres : 0;
    const ft = litres > 0.05 ? 1.5 + litres / c.rate : 0;
    if (!tyres && !(litres > 0.05)) return c.fixed * 0.5;
    return c.fixed + (parallel ? Math.max(tt, ft) : tt + ft);
  }

  function simLap(track, mu, mass, record) {
    const n = track.n;
    const sq = Math.sqrt(mu);
    let v = 20;
    let t = 0;
    let fuel = 0;
    const dts = record ? new Float64Array(n) : null;
    const vs = record ? new Float64Array(n) : null;
    for (let pass = 0; pass < 2; pass++) {
      t = 0;
      fuel = 0;
      for (let i = 0; i < n; i++) {
        const ds = track.RDS[i];
        const vAllow = track.PROF[(i + 1) % n] * sq;
        const climb = SC.G * track.GRADE[i] + SC.Car.scrub(v, track.RK[i], mu);
        const a = SC.Car.maxAccel(v, mass, mu) - climb;
        let v2 = Math.sqrt(Math.max(0.25, v * v + 2 * a * ds));
        let power;
        if (v2 >= vAllow) {
          v2 = vAllow;
          const need = (mass * 1.05 * (v2 * v2 - v * v)) / (2 * ds) + SC.Car.resistance(v, mass) + mass * climb;
          power = (Math.max(0, need) * v) / CAR.efficiency;
        } else {
          const g = SC.Car.bestGear(v);
          power = (Math.min(SC.Car.wheelForce(v, g, 1), CAR.frontWeight * mu * SC.G * mass) * v) / CAR.efficiency;
        }
        const dt = (2 * ds) / (v + v2);
        t += dt;
        fuel += SC.Car.fuelRate(power) * dt;
        if (record) {
          dts[i] = dt;
          vs[i] = v;
        }
        v = v2;
      }
    }
    return { time: t, fuel, dts, vs };
  }

  // Time lost driving through the pit lane (entry to exit) versus staying on track; excludes service.
  function pitLaneLoss(track, ref, mass) {
    const cfg = track.cfg;
    const n = track.n;
    const i0 = Math.round(track.wrap(cfg.pitEntry) / track.step);
    const count = Math.round((cfg.pitExit - cfg.pitEntry) / track.step);
    const boxP = track.boxS(7);
    const cap = new Float64Array(count + 1);
    let tRace = 0;
    for (let k = 0; k <= count; k++) {
      const i = (i0 + k) % n;
      const p = cfg.pitEntry + k * track.step;
      cap[k] = track.PROF[i];
      if (p >= track.laneStart && p <= track.laneEnd) cap[k] = Math.min(cap[k], PIT_SPEED);
      if (Math.abs(p - boxP) < track.step / 2) cap[k] = 0;
      if (k < count) tRace += ref.dts[i];
    }
    for (let k = count - 1; k >= 0; k--) {
      cap[k] = Math.min(cap[k], Math.sqrt(cap[k + 1] * cap[k + 1] + 2 * 6 * track.step));
    }
    let v = ref.vs[i0];
    let t = 0;
    for (let k = 0; k < count; k++) {
      const a = SC.Car.maxAccel(v, mass, 1) - SC.G * track.GRADE[(i0 + k) % n];
      const v2 = Math.min(cap[k + 1], Math.sqrt(Math.max(0, v * v + 2 * a * track.step)));
      t += (2 * track.step) / Math.max(0.5, v + v2);
      v = v2;
    }
    return t - tRace;
  }

  function calibrate(track) {
    if (track.cal) return track.cal;
    const mRef = SC.Car.massWithFuel(15);
    const muGrid = [];
    for (let mu = 0.4; mu <= 1.25001; mu += 0.05) muGrid.push([mu, simLap(track, mu, mRef).time]);
    const ref = simLap(track, 1, mRef, true);
    const heavy = simLap(track, 1, mRef + 60).time;
    const massExp = Math.log(heavy / ref.time) / Math.log((mRef + 60) / mRef);
    const cal = {
      mRef,
      muGrid,
      massExp,
      T0: ref.time,
      fuelPerLap: ref.fuel,
      pitDriveLoss: pitLaneLoss(track, ref, mRef),
      topSpeed: Math.max(...ref.vs),
    };
    track.cal = cal;
    return cal;
  }

  function lapTime(cal, muEff, mass) {
    const g = cal.muGrid;
    let t;
    if (muEff <= g[0][0]) t = g[0][1] * Math.pow(g[0][0] / muEff, 0.5);
    else if (muEff >= g[g.length - 1][0]) t = g[g.length - 1][1];
    else {
      const k = Math.min(g.length - 2, Math.floor((muEff - g[0][0]) / 0.05));
      const f = (muEff - g[k][0]) / (g[k + 1][0] - g[k][0]);
      t = g[k][1] + (g[k + 1][1] - g[k][1]) * f;
    }
    return t * Math.pow(mass / cal.mRef, cal.massExp);
  }

  const fuelNeed = (laps, fpl) => laps * fpl * FUEL_MARGIN + RESERVE;

  // Time for `laps` laps on one set of tyres, starting from the given tyre/fuel state.
  function stintTime(ctx, c, laps, fuelStart, wear0, temp0) {
    const { cal, track, wet, wearMult, skill2, agg, fpl } = ctx;
    const perLap = track.L * T.wearPerMetre(c, wet, wearMult) * agg;
    let w = wear0;
    let fuel = fuelStart;
    let temp = temp0;
    let t = 0;
    const base = T.compoundGrip(c, wet);
    for (let lap = 0; lap < laps; lap++) {
      const warmFrac = Math.min(1, ((1 - temp) * 1500) / track.L);
      const tempF = 1 - warmFrac * (1 - T.tempGrip((temp + 1) / 2));
      const grip = base * T.wearGrip(w - perLap / 2) * tempF;
      t += lapTime(cal, grip * skill2, SC.Car.massWithFuel(Math.max(0, fuel - fpl / 2)));
      w -= perLap;
      fuel -= fpl;
      temp = 1;
      if (w < 0.04 || fuel < RESERVE * 0.5 - 1e-6) return Infinity;
    }
    return t;
  }

  /**
   * opts: { track, laps, wet, wearMult, fuelMult, rules:{mandatoryStop, twoCompounds, refuel},
   *         crew, parallel, skill, agg, maxStops,
   *         current?: { c, wear, fuel, mask, stopsDone }, forcePit?: bool, diverse?: bool }
   * Returns plans sorted by estimated time: { stints:[{c, laps, fuel}], time, stops }.
   * With `current`, the first stint is the continuation of the current tyres (fuel 0 = no stop).
   */
  function plan(opts) {
    const track = opts.track;
    const cal = calibrate(track);
    const rules = opts.rules;
    const fpl = cal.fuelPerLap * opts.fuelMult;
    // Endurance races are planned over a rolling horizon of about three tanks: the cars extend
    // the plan as they go. Stop counts and compound masks stop mattering there, so the state collapses.
    const long = opts.laps > LONG_RACE && rules.refuel;
    const R = long ? Math.min(opts.laps, Math.max(LONG_RACE, Math.ceil((3 * CAR.tank) / fpl))) : opts.laps;
    const ctx = {
      cal, track, fpl,
      wet: opts.wet || 0,
      wearMult: opts.wearMult,
      skill2: (opts.skill || 1) ** 2,
      agg: opts.agg || 1,
    };
    const cur = opts.current || null;
    const stopsDone = cur ? cur.stopsDone : 0;
    const maxStops = long ? Infinity : opts.maxStops != null ? opts.maxStops : Math.min(6, 2 + Math.ceil(R / 6));
    const startFuel = cur ? cur.fuel : rules.refuel ? null : fuelNeed(R, fpl);
    if (!cur && !rules.refuel && startFuel > CAR.tank) return [];

    const memo = new Map();
    // cost of a fresh-tyre stint of n laps starting after r laps
    const stint = (c, n, r) => {
      const key = rules.refuel ? c + n : c + n + ',' + r;
      if (memo.has(key)) return memo.get(key);
      let fuel;
      if (rules.refuel) fuel = fuelNeed(n, fpl);
      else fuel = startFuel - r * fpl;
      let res;
      if (fuel > CAR.tank + 1e-6) res = { t: Infinity, fuel };
      else res = { t: stintTime(ctx, c, n, fuel, 1, 0.3), fuel };
      memo.set(key, res);
      return res;
    };
    const stopCost = (fuelTarget) => {
      const litres = rules.refuel ? Math.max(0, fuelTarget - RESERVE) : 0;
      return cal.pitDriveLoss + serviceTime(opts.crew, opts.parallel, true, litres);
    };

    const buckets = Array.from({ length: R + 1 }, () => new Map());
    const relax = (node) => {
      const key = long
        ? Math.min(node.j, 1) * 1000 + node.c * 100 + (rules.twoCompounds ? node.m * 4 : 0) + (opts.diverse ? node.f : 0)
        : node.j * 1000 + node.c * 100 + node.m * 4 + (opts.diverse ? node.f : 0);
      const b = buckets[node.r];
      const e = b.get(key);
      if (!e || node.t < e.t) b.set(key, node);
    };
    const ci = (c) => T.COMPOUND_KEYS.indexOf(c);

    if (!cur) {
      for (const c of T.COMPOUND_KEYS) {
        for (let n = 1; n <= R; n++) {
          const s = stint(c, n, 0);
          if (!isFinite(s.t)) break;
          relax({ r: n, j: 0, c: ci(c), m: T.compoundBit(c), f: ci(c), t: s.t, prev: null, st: { c, laps: n, fuel: s.fuel } });
        }
      }
    } else {
      const nMax = opts.forcePit ? 0 : R;
      for (let n = 0; n <= nMax; n++) {
        const tt = n === 0 ? 0 : stintTime(ctx, cur.c, n, cur.fuel, cur.wear, 1);
        if (!isFinite(tt)) break;
        relax({ r: n, j: 0, c: ci(cur.c), m: cur.mask, f: ci(cur.c), t: tt, prev: null, st: n ? { c: cur.c, laps: n, fuel: 0, cont: true } : null });
      }
    }

    for (let r = 0; r < R; r++) {
      for (const node of buckets[r].values()) {
        if (node.j >= maxStops) continue;
        for (const c of T.COMPOUND_KEYS) {
          for (let n = 1; n <= R - r; n++) {
            const s = stint(c, n, r);
            if (!isFinite(s.t)) break;
            relax({
              r: r + n,
              j: node.j + 1,
              c: ci(c),
              m: node.m | T.compoundBit(c),
              f: node.f,
              t: node.t + stopCost(s.fuel) + s.t,
              prev: node,
              st: { c, laps: n, fuel: rules.refuel ? s.fuel : 0 },
            });
          }
        }
      }
    }

    const dryMask = T.compoundBit('S') | T.compoundBit('M') | T.compoundBit('H');
    const valid = (node) => {
      const stops = stopsDone + node.j;
      if (rules.mandatoryStop && stops < 1) return false;
      if (rules.twoCompounds && !(node.m & T.compoundBit('W'))) {
        let bits = node.m & dryMask;
        let count = 0;
        while (bits) {
          count += bits & 1;
          bits >>= 1;
        }
        if (count < 2) return false;
      }
      return true;
    };

    const out = [];
    for (const node of buckets[R].values()) {
      if (!valid(node)) continue;
      const stints = [];
      for (let q = node; q; q = q.prev) if (q.st) stints.unshift(q.st);
      out.push({ stints, time: node.t, stops: node.j, horizon: R < opts.laps ? R : 0 });
    }
    out.sort((a, b) => a.time - b.time);
    // one entry per distinct compound sequence/stop count, best first
    const seen = new Set();
    return out.filter((p) => {
      const k = p.stints.map((s) => s.c).join('') + p.stops;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  }

  // Validate and time a hand-built plan. stints: [{c, laps}]
  function evaluate(opts, stints) {
    const cal = calibrate(opts.track);
    const R = opts.laps;
    const fpl = cal.fuelPerLap * opts.fuelMult;
    const rules = opts.rules;
    const ctx = { cal, track: opts.track, fpl, wet: opts.wet || 0, wearMult: opts.wearMult, skill2: 1, agg: 1 };
    const errors = [];
    const total = stints.reduce((a, st) => a + st.laps, 0);
    if (total !== R) errors.push(`Stints cover ${total} laps, the race is ${R}`);
    let r = 0;
    let time = 0;
    const out = [];
    const startFuel = rules.refuel ? null : fuelNeed(R, fpl);
    stints.forEach((st, k) => {
      const fuel = rules.refuel ? fuelNeed(st.laps, fpl) : startFuel - r * fpl;
      if (fuel > CAR.tank + 1e-6) errors.push(`Stint ${k + 1} needs ${fuel.toFixed(1)} L — the tank holds ${CAR.tank} L`);
      const t = stintTime(ctx, st.c, st.laps, Math.min(fuel, CAR.tank), 1, 0.3);
      if (!isFinite(t) && fuel <= CAR.tank) errors.push(`Stint ${k + 1}: ${T.COMPOUNDS[st.c].name}s won't last ${st.laps} laps`);
      time += t;
      if (k > 0) time += cal.pitDriveLoss + serviceTime(opts.crew, opts.parallel, true, rules.refuel ? Math.max(0, fuel - RESERVE) : 0);
      out.push({ c: st.c, laps: st.laps, fuel: rules.refuel || k === 0 ? Math.min(fuel, CAR.tank) : 0 });
      r += st.laps;
    });
    if (rules.mandatoryStop && stints.length < 2) errors.push('A pit stop is mandatory');
    if (rules.twoCompounds && !stints.some((st) => st.c === 'W') && new Set(stints.map((st) => st.c)).size < 2)
      errors.push('Two different dry compounds are required');
    return { stints: out, time, stops: stints.length - 1, errors };
  }

  // Expected laps for a timed race: typical lap plus the pit time spread over a tank of fuel.
  function estimateLaps(track, duration, s) {
    const cal = calibrate(track);
    const fpl = cal.fuelPerLap * s.fuelMult;
    const lap = lapTime(cal, T.compoundGrip('M', s.weather === 'wet' ? 0.85 : 0) * 0.96 * 0.96, SC.Car.massWithFuel(CAR.tank / 2));
    const stintLaps = Math.max(1, Math.min(CAR.tank / fpl, tyreLifeLaps(track, 'H', 0, s.wearMult) * 0.9));
    const stop = cal.pitDriveLoss + serviceTime(s.crew, s.parallel, true, s.refuel ? CAR.tank * 0.8 : 0);
    return Math.max(1, Math.round(duration / (lap * 1.01 + stop / stintLaps)));
  }

  // Laps a fresh set lasts at nominal driving load.
  function tyreLifeLaps(track, c, wet, wearMult) {
    return 1 / (track.L * T.wearPerMetre(c, wet, wearMult));
  }

  function label(p) {
    const stops = p.stops === 0 ? 'No stop' : p.stops === 1 ? '1 stop' : p.stops + ' stops';
    return stops + ': ' + p.stints.map((s) => s.c + s.laps).join(' → ');
  }

  SC.Strategy = {
    PIT_SPEED, FUEL_MARGIN, RESERVE, CREWS,
    serviceTime, simLap, calibrate, lapTime, stintTime, plan, evaluate, tyreLifeLaps, label, fuelNeed, estimateLaps, LONG_RACE,
  };
})();
