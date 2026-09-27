// Physics driver for the bots: turns a target line and speed into throttle, brake and steering for the same
// four-wheel car model the player drives. Bots can therefore run wide, lock up, spin and lose time exactly
// like you do; their speed comes from how well they drive, not from a shortcut.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const G = SC.G;
  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

  // Pure pursuit on a point further up the racing line (shifted sideways by offs, plus a mistake's
  // wobble), with a little yaw damping. This is the actual geometry a driver needs to make the corner —
  // not a fixed lock, but exactly the angle the coming curvature calls for at this speed and grip. Used
  // both to drive the bots and, as a ceiling, to keep a keyboard's digital steering from overshooting it.
  function pursuitSteer(tr, car, mu, offs, err) {
    const P = SC.Physics;
    const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
    const v = Math.max(0, car.vx * ch + car.vy * sh);
    const lim = tr.half + tr.cfg.runoff - 1;
    const Ld = clamp(5 + v * 0.42, 6, 26);
    const sl = car.s + Ld;
    const dl = clamp(tr.sample(tr.RLD, sl) + offs + (err ? err.d : 0), -lim, lim);
    const p = tr.pos(sl, dl);
    const dx = p.x - car.x, dy = p.y - car.y;
    const lx = dx * ch + dy * sh;
    const ly = -dx * sh + dy * ch;
    const kap = (2 * ly) / Math.max(1, lx * lx + ly * ly);
    let delta = Math.atan(kap * P.P.L);
    // the tyres need a little slip angle to make the turn; more as the car nears its limit
    const ay = v * v * kap;
    delta += Math.sign(kap) * Math.min(0.08, (Math.abs(ay) / (mu * G)) * P.APK * 0.35);
    delta += 0.06 * (v * kap - car.yawRate);
    return clamp(delta / P.maxSteer(v, mu), -1, 1);
  }

  // The steer a driver on the racing line, exactly at car's own position, would ask for right now — used
  // as a guide rail for keyboard/pad steering (see steerAssist in race.js), not to drive anyone directly.
  function lineSteer(tr, car, mu) {
    return pursuitSteer(tr, car, mu, 0, null);
  }

  // tg: { vT (speed wanted here, traffic included), dT (lateral target), K (profile scale), err (a mistake in progress) }
  function control(race, car, tg, mu) {
    const tr = race.track;
    const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
    const v = Math.max(0, car.vx * ch + car.vy * sh);
    const err = tg.err;

    // ---- speed: the target here, and never so fast that the braking for what's ahead can't be made
    const aB = 0.86 * mu * G * (err && err.kind === 'late' ? 1.35 : 1);
    let vRef = tg.vT;
    const lead = v * 0.12;
    for (let x = 5; x < 140; x += 5) {
      const va = tr.sample(tr.PROF, car.s + lead + x) * tg.K;
      const lim = Math.sqrt(va * va + 2 * aB * x);
      if (lim < vRef) vRef = lim;
      if (va * va + 2 * aB * x > v * v + 400) break;
    }
    const e = vRef - v;
    let throttle = 0;
    let brake = 0;
    if (e > 0) throttle = clamp(0.35 + e * 0.9, 0, 1);
    else if (e < -0.4) brake = clamp(-e * 0.45, 0, 1);
    else throttle = clamp(0.35 + e * 0.9, 0, 1);
    // feel the front tyres: ease off when they're washing out
    const under = car.understeer || 0;
    if (under > 1.08 && throttle > 0) throttle *= clamp(1.6 - (under - 1.08) * 4, 0.2, 1);

    // ---- steering
    const rl = tr.sample(tr.RLD, car.s);
    const steer = pursuitSteer(tr, car, mu, tg.dT - rl, err);
    return { throttle, brake, steer };
  }

  SC.Driver = { control, lineSteer };
})();
