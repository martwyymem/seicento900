// Dumps js/strategy.js calibration, lap/stint times, plans and evaluations, as the reference for
// godot/tests/test_strategy.gd. Option keys are written in the Godot (snake_case) form.
const SC = require('../harness.js');
const S = SC.Strategy;
const out = { tracks: {}, service: [] };
for (const crew of Object.keys(S.CREWS))
  for (const par of [false, true])
    for (const [ty, l] of [[true, 0], [true, 20], [false, 10], [false, 0], [true, 0.04]])
      out.service.push({ args: [crew, par, ty, l], v: S.serviceTime(crew, par, ty, l) });
const snake = (o) => {
  if (Array.isArray(o) || o === null || typeof o !== 'object') return o;
  const r = {};
  for (const [k, v] of Object.entries(o)) r[k.replace(/[A-Z]/g, (c) => '_' + c.toLowerCase())] = snake(v);
  return r;
};
for (const key of ['gp', 'monaco', 'nordschleife', 'spa']) {
  const tr = new SC.Track(key);
  const cal = S.calibrate(tr);
  const t = { cal: { m_ref: cal.mRef, mu_grid: cal.muGrid, mass_exp: cal.massExp, T0: cal.T0, fuel_per_lap: cal.fuelPerLap,
    pit_drive_loss: cal.pitDriveLoss, top_speed: cal.topSpeed }, lap_time: [], plans: [], evals: [], est: [] };
  for (const mu of [0.3, 0.4, 0.62, 0.97, 1.1, 1.3]) for (const m of [830, 870, 900]) t.lap_time.push({ args: [mu, m], v: S.lapTime(cal, mu, m) });
  const base = { laps: 12, wet: 0, wearMult: 1, fuelMult: 1, rules: { mandatoryStop: false, twoCompounds: false, refuel: true }, crew: 'club', parallel: false };
  const cases = [
    base,
    { ...base, laps: 25, wearMult: 2.5, rules: { mandatoryStop: true, twoCompounds: true, refuel: true }, diverse: true },
    { ...base, laps: 8, wet: 0.6, rules: { mandatoryStop: false, twoCompounds: false, refuel: false }, crew: 'pro', parallel: true },
    { ...base, laps: 20, wearMult: 3, rules: { mandatoryStop: false, twoCompounds: true, refuel: false }, skill: 0.95, agg: 1.1 },
    { ...base, laps: 15, wet: 0.3, maxStops: 4, current: { c: 'S', wear: 0.6, fuel: 12, mask: 1, stopsDone: 1 } },
    { ...base, laps: 10, forcePit: true, current: { c: 'M', wear: 0.3, fuel: 5, mask: 2, stopsDone: 0 }, rules: { mandatoryStop: true, twoCompounds: true, refuel: true } },
  ];
  if (key !== 'nordschleife') cases.push({ ...base, laps: 90, wearMult: 1.5, crew: 'amateur', diverse: true });
  for (const o of cases) {
    const plans = S.plan({ ...o, track: tr });
    t.plans.push({ opts: snake(o), plans: plans.map((p) => ({ ...p, label: S.label(p) })) });
  }
  t.evals.push({ opts: snake(base), stints: [{ c: 'S', laps: 5 }, { c: 'M', laps: 7 }], v: S.evaluate({ ...base, track: tr }, [{ c: 'S', laps: 5 }, { c: 'M', laps: 7 }]) });
  const nr = { ...base, laps: 30, rules: { mandatoryStop: true, twoCompounds: true, refuel: false } };
  t.evals.push({ opts: snake(nr), stints: [{ c: 'H', laps: 30 }], v: S.evaluate({ ...nr, track: tr }, [{ c: 'H', laps: 30 }]) });
  for (const [dur, s] of [[3600, { fuelMult: 1, weather: 'dry', wearMult: 1, crew: 'club', parallel: false, refuel: true }],
    [86400, { fuelMult: 1.5, weather: 'wet', wearMult: 2, crew: 'pro', parallel: true, refuel: true }],
    [1800, { fuelMult: 1, weather: 'variable', wearMult: 1, crew: 'amateur', parallel: false, refuel: false }]])
    t.est.push({ args: [dur, snake(s)], v: S.estimateLaps(tr, dur, s) });
  out.tracks[key] = t;
}
require('fs').writeFileSync(require('path').join(__dirname, '../../godot/tests/ref/strategy.json'), JSON.stringify(out));
console.log('strategy reference written');
