// Runs whole races through js/race.js with a known PRNG seed and dumps car states along the way plus the
// results, as the reference for godot/tests/test_race.gd. The Race seeds its mulberry32 from Math.random(),
// so Math.random is pinned to return seed / 2^31 while a race is built.
const fs = require('fs'), path = require('path');
const SC = require('../harness.js');

const DEFAULTS = {
  track: 'gp', laps: 6, opponents: 15, difficulty: 'medium', grid: 'middle', weather: 'dry',
  wearMult: 2, fuelMult: 1, crew: 'club', mandatoryStop: true, twoCompounds: false, refuel: true,
  parallel: false, collisions: true, playerName: 'You', playerNumber: 9, playerColor: '#b3121d',
  stripes: true, autoStrategist: true, gearbox: 'auto', assists: 'full', aiLearning: 'on',
  format: 'laps', hours: 1, startHour: 14,
};

// Scripted player input (when not on autopilot): a slow weave at part throttle, so the player's car
// runs through the assists, the kerbs, the run-off and into the barriers.
function scripted(t) {
  return { throttle: 0.7 + 0.3 * Math.sin(t * 0.3), brake: t % 17 < 1 ? 0.6 : 0, steer: 0.5 * Math.sin(t * 0.8), shiftUp: false, shiftDown: false };
}

const snap = (c) => ({
  s: c.s, lap: c.lap, d: c.d, v: c.v, x: c.x, y: c.y, heading: c.heading,
  fuel: c.fuel, wear: c.tyre.wear, c: c.tyre.c, gear: c.gear, mode: c.mode, control: c.control,
});

function run(sc) {
  const real = Math.random;
  Math.random = () => sc.seed / 2 ** 31;
  let race;
  try {
    race = new SC.Race(Object.assign({}, DEFAULTS, sc.settings));
  } finally {
    Math.random = real;
  }
  const dt = 1 / 120;
  if (sc.autopilot) race.setAutopilot(true);
  const out = { name: sc.name, seed: sc.seed, settings: sc.settings, autopilot: !!sc.autopilot, trace_every: sc.traceEvery,
    trace_ticks: sc.traceTicks, player_tyre: race.player.tyre.c, grid: race.cars.map((c) => c.name), trace: [], results: [] };
  let ticks = 0;
  const idle = { throttle: 0, brake: 0, steer: 0, shiftUp: false, shiftDown: false };
  while (race.phase !== 'finished' && ticks < sc.maxTicks) {
    race.step(dt, sc.autopilot ? idle : scripted(ticks * dt));
    ticks++;
    if (ticks <= sc.traceTicks && ticks % sc.traceEvery === 0) out.trace.push({ tick: ticks, cars: race.cars.map(snap) });
  }
  out.ticks = ticks;
  out.phase = race.phase;
  for (const r of race.results())
    out.results.push({ pos: r.pos, name: r.car.name, laps: r.laps, total: r.total, best: r.car.bestLap, status: r.status || '',
      stops: r.car.stops, lap_times: r.car.lapTimes });
  return out;
}

const scenarios = [
  { name: 'gp_autopilot', seed: 12345, autopilot: true, settings: { track: 'gp', laps: 2 }, traceEvery: 12, traceTicks: 120 * 60, maxTicks: 120 * 900 },
  { name: 'monaco_scripted', seed: 777, autopilot: false, settings: { track: 'monaco', laps: 1, opponents: 5, difficulty: 'hard', grid: 'back' },
    traceEvery: 12, traceTicks: 120 * 45, maxTicks: 120 * 45 },
  { name: 'spa_rail_wet', seed: 4242, autopilot: true, settings: { track: 'spa', laps: 2, opponents: 9, weather: 'wet', botPhysics: 'off', wearMult: 3 },
    traceEvery: 60, traceTicks: 120 * 120, maxTicks: 120 * 1200 },
];

const res = [];
for (const sc of scenarios) {
  const t0 = Date.now();
  res.push(run(sc));
  console.log(`${sc.name}: ${res[res.length - 1].ticks} ticks in ${Date.now() - t0} ms, ${res[res.length - 1].phase}`);
}
fs.writeFileSync(path.join(__dirname, '../../godot/tests/ref/race.json'), JSON.stringify({ scenarios: res }));
