// Drives js/physics.js through scripted scenarios and records the car state, as the reference for
// godot/tests/test_physics.gd. Inputs (incl. gear changes) are stored per tick so Godot replays them exactly.
const SC = require('../harness.js');
const P = SC.Physics;
const { CAR } = SC.Car;
const DT = 1 / 120;
// surface ids as in godot physics.gd: 0 track, 1 asphalt, 2 grass, 3 gravel
const SURF = [{ grip: 1, drag: 0 }, { grip: 0.9, drag: 0.004 }, { grip: 0.5, drag: 0.07 }, { grip: 0.42, drag: 0.22 }];
const surfId = (x, y) => (y > 4 ? 2 : x > 40 ? 3 : y < -3 ? 1 : 0);

function run(sc) {
  const car = { x: 0, y: 0, heading: sc.heading || 0, vx: sc.v0 * Math.cos(sc.heading || 0), vy: sc.v0 * Math.sin(sc.heading || 0),
    yawRate: 0, rpm: CAR.idleRpm, gear: sc.gear0 || 0, shiftT: 0, rev: !!sc.rev };
  const inputs = [];
  const states = [];
  for (let t = 0; t < sc.ticks; t++) {
    const inp = sc.input(t, car);
    // simple rpm-based box (the race's autoShift is tested separately)
    if (!car.rev && car.rpm > 6000 && car.gear < 4) { car.gear++; car.shiftT = 0.15; }
    else if (!car.rev && car.rpm < 2500 && car.gear > 0 && car.phys) { car.gear--; car.shiftT = 0.12; }
    inputs.push([inp.throttle, inp.brake, inp.steer, car.gear, car.shiftT]);
    const out = P.step(car, inp, {
      mu: sc.mu, mass: sc.mass, surface: (x, y) => SURF[surfId(x, y)], gx: sc.gx || 0, gy: sc.gy || 0,
      dragMul: sc.dragMul || 1, abs: sc.aids, tc: sc.aids, esc: sc.aids,
    }, DT);
    car.shiftT = Math.max(0, car.shiftT - DT);
    const ph = car.phys;
    states.push([car.x, car.y, car.heading, car.vx, car.vy, car.yawRate, car.rpm, car.steer, ph.we, ph.clutch, ...ph.w,
      ph.axF, ph.ayF, car.understeer, car.slip, car.bodyRoll, car.bodyPitch, out.enginePower, out.slidePower]);
  }
  return { name: sc.name, v0: sc.v0, heading: sc.heading || 0, gear0: sc.gear0 || 0, rev: !!sc.rev, mu: sc.mu, mass: sc.mass,
    gx: sc.gx || 0, gy: sc.gy || 0, dragMul: sc.dragMul || 1, aids: sc.aids, inputs, states };
}

const scenarios = [
  { name: 'launch', v0: 0, mu: 1.0, mass: 870, aids: true, ticks: 720, input: () => ({ throttle: 1, brake: 0, steer: 0 }) },
  { name: 'launch-noaids-wet', v0: 0, mu: 0.6, mass: 890, aids: false, ticks: 480, input: () => ({ throttle: 1, brake: 0, steer: 0.1 }) },
  { name: 'slalom-brake', v0: 28, gear0: 3, heading: 0.3, mu: 1.0, mass: 860, aids: true, ticks: 720,
    input: (t) => ({ throttle: t < 300 ? 0.8 : 0, brake: t >= 300 && t < 420 ? 1 : 0, steer: Math.sin(t / 40) * 0.9 }) },
  { name: 'slalom-noaids-grass', v0: 25, gear0: 3, heading: 0.05, mu: 0.95, mass: 900, aids: false, ticks: 720, gx: 0.3, gy: -0.1,
    input: (t) => ({ throttle: t % 200 < 120 ? 1 : 0, brake: t % 200 > 170 ? 0.8 : 0, steer: Math.sin(t / 25) }) },
  { name: 'lockup-gravel', v0: 35, gear0: 4, heading: -0.08, mu: 1.1, mass: 850, aids: false, ticks: 360, dragMul: 0.8,
    input: (t) => ({ throttle: 0, brake: 1, steer: t > 60 ? 0.6 : 0 }) },
];
const out = scenarios.map(run);
require('fs').writeFileSync(require('path').join(__dirname, '../../godot/tests/ref/physics.json'), JSON.stringify(out));
console.log(`physics reference: ${out.length} scenarios, ${out.reduce((a, s) => a + s.states.length, 0)} states`);
