// Fiat Seicento 900 vehicle + tyre model.
// Figures are the real 899 cc car where known (39 hp @ 5500, 65 Nm @ 3000, ~735 kg, ~140 km/h);
// gearing and aero are close approximations.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const G = 9.81;

  const CAR = {
    massEmpty: 735,
    driverMass: 80,
    fuelDensity: 0.745, // kg per litre
    tank: 35, // litres
    length: 3.34,
    width: 1.51,
    wheelbase: 2.2,
    wheelRadius: 0.277, // 145/70 R13
    gears: [3.909, 2.158, 1.345, 0.974, 0.784],
    finalDrive: 4.923,
    efficiency: 0.88,
    idleRpm: 850,
    redline: 6100,
    limiter: 6300,
    cdA: 0.33 * 1.84,
    crr: 0.013,
    frontWeight: 0.62, // FWD traction share
    bsfc: 330, // g/kWh at load
  };

  // [rpm, Nm]
  const TORQUE = [
    [800, 40], [1500, 52], [2000, 58], [3000, 65], [4000, 62],
    [5000, 56], [5500, 51.5], [6000, 45], [6300, 38],
  ];

  function torqueAt(rpm) {
    if (rpm <= TORQUE[0][0]) return TORQUE[0][1];
    for (let i = 1; i < TORQUE.length; i++) {
      const [r1, t1] = TORQUE[i];
      if (rpm <= r1) {
        const [r0, t0] = TORQUE[i - 1];
        return t0 + ((t1 - t0) * (rpm - r0)) / (r1 - r0);
      }
    }
    return 0;
  }

  const ratio = (gear) => CAR.gears[gear] * CAR.finalDrive;
  const rpmFor = (v, gear) => (Math.abs(v) / CAR.wheelRadius) * ratio(gear) * (60 / (2 * Math.PI));

  // Engine rpm including clutch slip in first gear when pulling away.
  function engineRpm(v, gear, throttle) {
    const r = rpmFor(v, gear);
    if (gear === 0 && throttle > 0.05) return Math.max(r, 2600 * throttle + CAR.idleRpm * (1 - throttle));
    return Math.max(r, CAR.idleRpm);
  }

  function wheelForce(v, gear, throttle) {
    const rpm = engineRpm(v, gear, throttle);
    if (rpm >= CAR.limiter) return 0;
    return (throttle * torqueAt(rpm) * ratio(gear) * CAR.efficiency) / CAR.wheelRadius;
  }

  // The gear an ideal driver would be in: most tractive force without passing the redline.
  function bestGear(v) {
    let best = 0;
    let bestF = -1;
    for (let g = 0; g < CAR.gears.length; g++) {
      if (g > 0 && rpmFor(v, g) < 1500) break;
      if (rpmFor(v, g) > CAR.redline && g < CAR.gears.length - 1) continue;
      const f = wheelForce(v, g, 1);
      if (f > bestF) {
        bestF = f;
        best = g;
      }
    }
    return best;
  }

  function resistance(v, mass, dragMul = 1) {
    return 0.5 * 1.2 * CAR.cdA * dragMul * v * v + CAR.crr * mass * G;
  }

  // Full-throttle longitudinal acceleration in the best gear (used by AI and the lap simulator).
  function maxAccel(v, mass, mu, dragMul = 1) {
    const gear = bestGear(v);
    const drive = Math.min(wheelForce(v, gear, 1), CAR.frontWeight * mu * G * mass);
    return (drive - resistance(v, mass, dragMul)) / (mass * 1.05);
  }

  // Deceleration from tyre scrub while cornering on curvature k: slip angles tilt the lateral force backwards.
  // Fitted to the four-wheel model in physics.js; a 39 hp car can barely hold speed through a long bend at the limit.
  function scrub(v, k, mu) {
    const ay = v * v * Math.abs(k);
    const u = Math.min(1.2, ay / (mu * G));
    return 0.065 * ay * u * Math.sqrt(u);
  }

  // Litres per second for a given engine output (W).
  function fuelRate(powerW) {
    const idle = 0.35 / 3600;
    if (powerW <= 0) return idle;
    return idle + ((powerW / 1000) * CAR.bsfc) / 3600 / (CAR.fuelDensity * 1000);
  }

  const baseMass = () => CAR.massEmpty + CAR.driverMass;
  const massWithFuel = (litres) => baseMass() + litres * CAR.fuelDensity;

  // ---------------- Tyres ----------------
  const COMPOUNDS = {
    S: { key: 'S', name: 'Soft', color: '#ff4040', grip: 1.045, life: 20000 },
    M: { key: 'M', name: 'Medium', color: '#ffd23b', grip: 1.0, life: 32000 },
    H: { key: 'H', name: 'Hard', color: '#f2f2f2', grip: 0.962, life: 48000 },
    W: { key: 'W', name: 'Wet', color: '#3b9dff', grip: 0.88, life: 30000 },
  };
  const COMPOUND_KEYS = ['S', 'M', 'H', 'W'];
  const compoundBit = (c) => 1 << COMPOUND_KEYS.indexOf(c);

  // Grip of a fresh, warm tyre for the given track wetness (0 dry .. 1 soaked).
  function compoundGrip(c, wet) {
    if (c === 'W') return COMPOUNDS.W.grip - 0.07 * wet;
    return COMPOUNDS[c].grip * (1 - 0.43 * wet);
  }

  // Remaining tread 1..0: gentle linear fall-off, then a cliff below 25 %.
  function wearGrip(w) {
    if (w >= 0.25) return 1 - (0.06 * (1 - w)) / 0.75;
    return Math.max(0.6, 0.94 - (0.26 * (0.25 - w)) / 0.25);
  }

  const tempGrip = (t) => 0.9 + 0.1 * Math.min(1, Math.max(0, t));

  // Tread fraction lost per metre at nominal driving load.
  function wearPerMetre(c, wet, wearMult) {
    let r = 1 / COMPOUNDS[c].life;
    if (c === 'W') r *= 1 + 3.5 * (1 - wet) * (1 - wet); // wets cook on a dry track
    else r *= 1 - 0.35 * wet; // slicks stay cool in the rain
    return r * wearMult;
  }

  function tyreGrip(tyre, wet) {
    return compoundGrip(tyre.c, wet) * wearGrip(tyre.wear) * tempGrip(tyre.temp);
  }

  SC.G = G;
  SC.Car = {
    CAR, torqueAt, rpmFor, engineRpm, wheelForce, bestGear, resistance, maxAccel, scrub, fuelRate,
    baseMass, massWithFuel, ratio,
  };
  SC.Tyres = {
    COMPOUNDS, COMPOUND_KEYS, compoundBit, compoundGrip, wearGrip, tempGrip, wearPerMetre, tyreGrip,
  };
})();
