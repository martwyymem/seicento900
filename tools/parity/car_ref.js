// Dumps js/car.js outputs over a grid of inputs, as the reference for godot/tests/test_car.gd.
const SC = require('../harness.js');
const { Car, Tyres } = SC;
const out = [];
const push = (fn, args, v) => out.push({ fn, args, v });
for (const rpm of [500, 800, 1200, 3000, 4500, 6200, 6300, 7000]) push('torque_at', [rpm], Car.torqueAt(rpm));
for (let v = 0; v <= 45; v += 2.5) {
  push('best_gear', [v], Car.bestGear(v));
  push('resistance', [v, 900, 1], Car.resistance(v, 900, 1));
  push('resistance', [v, 850, 0.7], Car.resistance(v, 850, 0.7));
  for (const mu of [0.6, 1.0, 1.1]) push('max_accel', [v, 880, mu, 1], Car.maxAccel(v, 880, mu, 1));
  for (let g = 0; g < 5; g++) {
    push('rpm_for', [v, g], Car.rpmFor(v, g));
    for (const th of [0, 0.3, 1]) {
      push('engine_rpm', [v, g, th], Car.engineRpm(v, g, th));
      push('wheel_force', [v, g, th], Car.wheelForce(v, g, th));
    }
  }
  for (const k of [0, 0.005, 0.02, 0.08]) push('scrub', [v, k, 1.0], Car.scrub(v, k, 1.0));
}
for (const p of [-100, 0, 5000, 29000]) push('fuel_rate', [p], Car.fuelRate(p));
push('mass_with_fuel', [20], Car.massWithFuel(20));
for (const c of Tyres.COMPOUND_KEYS)
  for (const wet of [0, 0.4, 1]) {
    push('compound_grip', [c, wet], Tyres.compoundGrip(c, wet));
    push('wear_per_metre', [c, wet, 1.3], Tyres.wearPerMetre(c, wet, 1.3));
    for (const wear of [1, 0.5, 0.2, 0.01]) for (const temp of [0, 0.5, 2])
      push('tyre_grip', [{ c, wear, temp }, wet], Tyres.tyreGrip({ c, wear, temp }, wet));
  }
require('fs').writeFileSync(require('path').join(__dirname, '../../godot/tests/ref/car.json'), JSON.stringify(out));
console.log(`car reference: ${out.length} values`);
