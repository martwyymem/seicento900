// Vehicle dynamics for the player's car: a rigid body on four Pacejka tyres.
// - Magic Formula tyres with combined slip, load sensitivity and per-wheel surface grip
// - Wheel spin dynamics solved implicitly, so locking and wheelspin are stable at any speed
// - Engine inertia, friction/engine braking, rev limiter, auto clutch and an open front differential
// - Load transfer through a sprung body (pitch and roll lag behind the tyre forces)
// - Front-biased brakes with optional ABS, traction and stability control, Ackermann steering, aero drag and lift
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const { CAR } = SC.Car;
  const G = SC.G;
  const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);

  const P = {
    cgH: 0.54,
    a: CAR.wheelbase * (1 - CAR.frontWeight), // CG to front axle
    b: CAR.wheelbase * CAR.frontWeight, // CG to rear axle
    trackF: 1.36,
    trackR: 1.33,
    wheelI: 0.6, // per wheel incl. brake disc and half-shaft
    engineI: 0.045, // crank + flywheel
    clutchCap: 125, // Nm
    brakeF: 1250, // Nm per wheel at full pedal
    brakeR: 130, // rear drums behind a load-sensing valve
    rollF: 0.6, // front share of roll stiffness
    rollGrad: 0.11, // body roll, rad per g
    pitchGrad: 0.045, // body pitch, rad per g
    suspHz: 1.5,
    suspZeta: 0.55,
    liftA: 0.12, // Cl·A, a little lift at speed
    reverse: 3.55,
    lock: 0.5, // road-wheel angle at full lock
    ackermann: 0.5, // fraction of true Ackermann geometry
    loadSens: 0.1, // grip lost per unit of extra load over static
    gripK: 1.15, // calibrates the tyre so the car's steady-state limit matches the field's
    vRef: 2.5, // low-speed slip floor (m/s)
    idle: CAR.idleRpm,
    sub: 8, // substeps per race tick
  };
  P.L = P.a + P.b;

  // Magic Formula curves, normalised to a peak of 1. Longitudinal in slip ratio, lateral in slip angle.
  const TX = { B: 16, C: 1.5, E: 0.3 };
  const TY = { B: 13, C: 1.6, E: 0.1 };
  const mf = (t, x) => {
    const bx = t.B * x;
    return Math.sin(t.C * Math.atan(bx - t.E * (bx - Math.atan(bx))));
  };
  const peakOf = (t) => {
    let best = 0, bx = 0;
    for (let x = 0.001; x < 1; x += 0.0005) {
      const f = mf(t, x);
      if (f > best) (best = f), (bx = x);
    }
    return bx;
  };
  const KPK = peakOf(TX); // slip ratio at peak force
  const APK = peakOf(TY); // slip angle at peak force (rad)
  const TAPK = Math.tan(APK);

  // Tyre forces in the wheel frame. vl/vt: contact patch velocity along/across the wheel, w: wheel spin.
  // Returns [Fl, Ft, rho] where rho is the combined slip relative to peak (1 = at the limit).
  function tyre(w, vl, vt, fz, mu, out) {
    const vr = Math.max(Math.abs(vl), P.vRef);
    const sx = (w * CAR.wheelRadius - vl) / vr / KPK;
    const sy = vt / vr / TAPK;
    const rho = Math.hypot(sx, sy);
    out[2] = rho;
    if (rho < 1e-9 || fz <= 0) {
      out[0] = out[1] = 0;
      return out;
    }
    const fm = mu * fz;
    out[0] = (fm * mf(TX, rho * KPK) * sx) / rho;
    out[1] = (-fm * mf(TY, Math.atan(rho * TAPK)) * sy) / rho;
    return out;
  }

  const ratioOf = (car) => (car.rev ? -P.reverse : CAR.gears[car.gear]) * CAR.finalDrive;
  const rpmOf = (w) => (w * 30) / Math.PI;
  const engineFriction = (rpm) => 7 + 0.0022 * rpm;

  // Fresh drivetrain state for a car that has just been handed to physics (race start, leaving the pits…).
  function init(car) {
    const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
    const vF = car.vx * ch + car.vy * sh;
    const wW = vF / CAR.wheelRadius;
    car.phys = {
      w: [wW, wW, wW, wW],
      we: Math.max((car.rpm * Math.PI) / 30, Math.abs(wW * ratioOf(car))),
      clutch: Math.abs(vF) > 3 ? 1 : 0,
      axF: 0, ayF: 0, axD: 0, ayD: 0,
      abs: [1, 1, 1, 1],
      tc: 1,
      fx0: 0,
      fz: [0, 0, 0, 0],
      rho: [0, 0, 0, 0],
      slide: 0,
      heat: 0,
    };
    car.rev = false;
    return car.phys;
  }

  // Speed-sensitive steering limit: enough lock to reach the tyres' peak slip, not so much that a
  // keyboard tap throws the car past it. Scaled by the steering input.
  function maxSteer(v, mu) {
    const v2 = Math.max(1, v * v);
    return Math.min(P.lock, (P.L * mu * G) / v2 + 1.35 * APK);
  }

  const WX = [P.a, P.a, -P.b, -P.b];
  const WY = [-P.trackF / 2, P.trackF / 2, -P.trackR / 2, P.trackR / 2];
  const tmp = [0, 0, 0];
  const tmp2 = [0, 0, 0];
  // per-wheel scratch, reused every substep
  const vl = new Float64Array(4), vt = new Float64Array(4), mu = new Float64Array(4), drag = new Float64Array(4);
  const cw = new Float64Array(4), dw = new Float64Array(4), esc = new Float64Array(4);
  const dW = new Float64Array(4), cd = new Float64Array(4), sd = new Float64Array(4);
  const surf = [null, null, null, null];

  // Advance the car by dt. env: { mu, mass, surface(x, y) -> {grip, drag}, gx, gy (gravity along the road, world),
  //   abs, tc, esc }. input: { throttle, brake, steer } with throttle/brake already routed for reverse.
  function step(car, input, env, dt) {
    const ph = car.phys || init(car);
    const m = env.mass;
    const iz = (m * (CAR.length * CAR.length + CAR.width * CAR.width)) / 12;
    const h = dt / P.sub;
    const R = CAR.wheelRadius;
    const wn = 2 * Math.PI * P.suspHz;
    const ratio = ratioOf(car);
    let fuelW = 0;
    let slideW = 0;
    let maxRhoF = 0;
    let maxRhoR = 0;
    let slideV = 0;
    const v0 = Math.hypot(car.vx, car.vy);
    const delta = input.steer * maxSteer(v0, env.mu);
    car.steer = delta;
    // Ackermann: the inside wheel turns tighter
    dW[0] = dW[1] = delta;
    dW[2] = dW[3] = 0;
    if (Math.abs(delta) > 1e-4) {
      const rt = P.L / Math.tan(delta);
      dW[0] = delta + (Math.atan(P.L / (rt - WY[0])) - delta) * P.ackermann;
      dW[1] = delta + (Math.atan(P.L / (rt - WY[1])) - delta) * P.ackermann;
    }
    for (let i = 0; i < 4; i++) {
      cd[i] = Math.cos(dW[i]);
      sd[i] = Math.sin(dW[i]);
    }

    for (let k = 0; k < P.sub; k++) {
      const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
      const vx = car.vx * ch + car.vy * sh;
      const vy = -car.vx * sh + car.vy * ch;
      const r = car.yawRate;
      const v2 = vx * vx + vy * vy;

      // ---- loads: static + aero lift + pitch/roll transfer from the lagged body accelerations
      const lift = 0.5 * 1.2 * P.liftA * v2;
      const W = m * G;
      const dLong = (m * ph.axF * P.cgH) / P.L;
      const front = (W * P.b) / P.L - dLong - lift * 0.55;
      const rear = (W * P.a) / P.L + dLong - lift * 0.45;
      const dLatF = ((m * ph.ayF * P.cgH) / P.trackF) * P.rollF;
      const dLatR = ((m * ph.ayF * P.cgH) / P.trackR) * (1 - P.rollF);
      const fz = ph.fz;
      fz[0] = Math.max(0, front / 2 + dLatF);
      fz[1] = Math.max(0, front / 2 - dLatF);
      fz[2] = Math.max(0, rear / 2 + dLatR);
      fz[3] = Math.max(0, rear / 2 - dLatR);
      const fz0 = W / 4;

      // ---- per-wheel kinematics, surface and grip
      for (let i = 0; i < 4; i++) {
        const wx = vx - r * WY[i];
        const wy = vy + r * WX[i];
        vl[i] = wx * cd[i] + wy * sd[i];
        vt[i] = -wx * sd[i] + wy * cd[i];
        if (k === 0) surf[i] = env.surface(car.x + WX[i] * ch - WY[i] * sh, car.y + WX[i] * sh + WY[i] * ch);
        const sens = clamp(1 - P.loadSens * (fz[i] / fz0 - 1), 0.75, 1.15);
        mu[i] = env.mu * P.gripK * surf[i].grip * sens;
        drag[i] = CAR.crr + surf[i].drag;
      }

      // ---- driver aids
      let thr = input.throttle;
      // traction control trims the throttle in proportion to how far the driven wheels are past peak slip
      const spin = Math.max(ph.rho[0], ph.rho[1]);
      const tcWant = env.tc && vx > 1 && ph.fx0 > 0 && spin > 1.1 ? Math.max(0.35, 1 - (spin - 1.1) * 1.5) : 1;
      ph.tc += clamp(tcWant - ph.tc, -h * 10, h * 5);
      thr *= ph.tc;

      // ---- engine, clutch and gearbox
      const shifting = car.shiftT > 0;
      let rpm = rpmOf(ph.we);
      const wc = (ph.w[0] + ph.w[1]) / 2;
      const wheelRpm = Math.abs(rpmOf(wc * ratio));
      let bite;
      if (shifting) bite = 0;
      else if (wheelRpm < 1250) {
        // pulling away or rolling to a stop: slip the clutch, never stall
        bite = thr > 0.02 ? clamp((rpm - 1150) / 1500, 0, 1) : 0;
      } else bite = rpm < 780 ? 0 : 1;
      ph.clutch += clamp(bite - ph.clutch, -h * 25, h * (shifting ? 25 : 7));
      if (shifting) {
        // throttle lifts on upshifts; the box blips on downshifts to match revs
        const target = Math.abs(rpmOf(wc * ratio));
        thr = target > rpm + 150 ? 1 : 0;
      }
      if (rpm < P.idle + 60) thr = Math.max(thr, clamp((P.idle + 180 - rpm) / 400, 0, 0.35));
      if (rpm >= CAR.limiter) thr = 0;
      const fr = engineFriction(rpm);
      const te = thr * (SC.Car.torqueAt(rpm) + fr) - fr;

      // ---- stability control: brake the outside front wheel when the car yaws faster than the steering asks
      esc.fill(0);
      if (env.esc && vx > 5) {
        // reference: the neutral-steer yaw rate, capped at what the grip allows
        const lim = (env.mu * G * 1.1) / vx;
        const target = clamp((vx * delta) / P.L, -lim, lim);
        const over = r - target;
        const band = 0.05 + 0.1 * Math.abs(target);
        if (Math.abs(over) > band && Math.sign(over) === Math.sign(r)) {
          esc[r > 0 ? 0 : 1] = Math.min(1, (Math.abs(over) - band) * 4) * P.brakeF * 0.7;
          thr *= 0.3;
        }
      }

      // ---- wheel spin: linearised backward Euler so stiff tyres can't blow up
      const brk = input.brake;
      for (let i = 0; i < 4; i++) {
        const w = ph.w[i];
        tyre(w, vl[i], vt[i], fz[i], mu[i], tmp);
        const eps = 0.02;
        tyre(w + eps, vl[i], vt[i], fz[i], mu[i], tmp2);
        const kx = Math.max(0, (tmp2[0] - tmp[0]) / eps);
        ph.rho[i] = tmp[2];
        // ABS: back off a wheel's pressure when it is heading for a lock
        const kappa = (w * R - vl[i]) / Math.max(Math.abs(vl[i]), P.vRef);
        if (env.abs && (brk > 0 || esc[i] > 0) && Math.abs(vl[i]) > 2 && kappa * Math.sign(vl[i]) < -KPK * 1.2) ph.abs[i] = Math.max(0.1, ph.abs[i] - h * 30);
        else ph.abs[i] = Math.min(1, ph.abs[i] + h * 10);
        const tb = (brk * (i < 2 ? P.brakeF : P.brakeR) + esc[i]) * ph.abs[i];
        const roll = drag[i] * fz[i] * R;
        const w0 = 1.5;
        const sgn = clamp(w / w0, -1, 1);
        cw[i] = R * tmp[0] + (tb + roll) * sgn;
        dw[i] = P.wheelI / h + R * kx + (Math.abs(w) < w0 ? (tb + roll) / w0 : 0);
      }
      let tau = 0;
      const a = (ratio * CAR.efficiency) / 2;
      if (ph.clutch > 0.001) {
        // clutch torque that would lock engine and differential together this substep, limited by capacity
        const lhs = h / P.engineI + (ratio / 2) * a * (1 / dw[0] + 1 / dw[1]);
        const rhs = ph.we + (h * te) / P.engineI - (ratio / 2) * (ph.w[0] + ph.w[1]) + (ratio / 2) * (cw[0] / dw[0] + cw[1] / dw[1]);
        const cap = ph.clutch * P.clutchCap;
        tau = clamp(rhs / lhs, -cap, cap);
      }
      ph.we += (h * (te - tau)) / P.engineI;
      ph.we = clamp(ph.we, (600 * Math.PI) / 30, ((CAR.limiter + 250) * Math.PI) / 30);
      for (let i = 0; i < 4; i++) {
        ph.w[i] += ((i < 2 ? tau * a : 0) - cw[i]) / dw[i];
      }
      ph.fx0 = tau * ratio;
      fuelW += Math.max(0, te) * ph.we * h;

      // ---- tyre forces with the updated wheel speeds, summed on the body
      let fxB = 0, fyB = 0, mz = 0;
      for (let i = 0; i < 4; i++) {
        tyre(ph.w[i], vl[i], vt[i], fz[i], mu[i], tmp);
        const Fl = tmp[0], Ft = tmp[1];
        ph.rho[i] = tmp[2];
        const bx = Fl * cd[i] - Ft * sd[i];
        const by = Fl * sd[i] + Ft * cd[i];
        fxB += bx;
        fyB += by;
        mz += WX[i] * by - WY[i] * bx;
        const sv = Math.hypot(ph.w[i] * R - vl[i], vt[i]);
        slideW += Math.hypot(Fl, Ft) * sv * h;
        slideV = Math.max(slideV, sv);
        if (i < 2) maxRhoF = Math.max(maxRhoF, tmp[2]);
        else maxRhoR = Math.max(maxRhoR, tmp[2]);
      }
      const vmag = Math.sqrt(v2);
      const fa = 0.5 * 1.2 * CAR.cdA * (env.dragMul || 1) * vmag;
      fxB -= fa * vx;
      fyB -= fa * vy;

      // ---- integrate the body (world frame) and the lagged suspension
      const axB = fxB / m, ayB = fyB / m;
      car.vx += (axB * ch - ayB * sh + env.gx) * h;
      car.vy += (axB * sh + ayB * ch + env.gy) * h;
      car.yawRate += (mz / iz) * h;
      // parked with the brakes on: stop creeping
      if (brk > 0.2 && v2 < 0.01 && Math.abs(car.yawRate) < 0.05) {
        car.vx *= 0.9;
        car.vy *= 0.9;
        car.yawRate *= 0.9;
      }
      car.heading += car.yawRate * h;
      car.x += car.vx * h;
      car.y += car.vy * h;
      ph.axD += (wn * wn * (axB - ph.axF) - 2 * P.suspZeta * wn * ph.axD) * h;
      ph.ayD += (wn * wn * (ayB - ph.ayF) - 2 * P.suspZeta * wn * ph.ayD) * h;
      ph.axF += ph.axD * h;
      ph.ayF += ph.ayD * h;
    }

    const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
    const vF = car.vx * ch + car.vy * sh;
    car.speed = vF;
    car.v = Math.abs(vF);
    car.rpm = rpmOf(ph.we);
    car.throttle = input.throttle;
    car.brakeOn = input.brake > 0.05;
    // tyre noise cues: fronts past their peak (understeer) and how far any tyre is past ~80 % of its grip
    car.understeer = maxRhoF;
    car.slip = Math.max(0, Math.max(maxRhoF, maxRhoR) - 0.8) * 3 + Math.max(0, slideV - 4) * 0.2;
    car.bodyRoll = clamp((-ph.ayF / G) * P.rollGrad, -0.12, 0.12);
    car.bodyPitch = clamp((ph.axF / G) * P.pitchGrad, -0.06, 0.06);
    ph.slide = slideW / dt; // W dissipated in the contact patches
    return { enginePower: fuelW / dt, slidePower: ph.slide };
  }

  // Impulse on the body at a point (rx, ry from the CG, world axes), given as the velocity change of the CG.
  function kick(car, ix, iy, rx, ry) {
    const k2 = (CAR.length * CAR.length + CAR.width * CAR.width) / 12; // yaw radius of gyration squared
    car.vx += ix;
    car.vy += iy;
    if (rx != null) car.yawRate += (rx * iy - ry * ix) / k2;
  }

  // Rigid-body contact with a barrier: n points out of the track, (rx, ry) is the contact point from the CG.
  function barrierHit(car, nx, ny, rx, ry, mass) {
    const iz = (mass * (CAR.length * CAR.length + CAR.width * CAR.width)) / 12;
    const vcx = car.vx - car.yawRate * ry;
    const vcy = car.vy + car.yawRate * rx;
    const vn = vcx * nx + vcy * ny;
    if (vn <= 0) return 0;
    const rn = rx * ny - ry * nx;
    const jn = (-(1 + 0.25) * vn) / (1 / mass + (rn * rn) / iz);
    const tx = -ny, ty = nx;
    const vt = vcx * tx + vcy * ty;
    const rt = rx * ty - ry * tx;
    const jtMax = 0.45 * Math.abs(jn);
    const jt = clamp(-vt / (1 / mass + (rt * rt) / iz), -jtMax, jtMax);
    const jx = jn * nx + jt * tx;
    const jy = jn * ny + jt * ty;
    car.vx += jx / mass;
    car.vy += jy / mass;
    car.yawRate += (rx * jy - ry * jx) / iz;
    return vn;
  }

  SC.Physics = { P, init, step, kick, barrierHit, maxSteer, tyre, KPK, APK };
})();
