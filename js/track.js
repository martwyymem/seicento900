// Track geometry: centreline, racing line, speed profile, pit lane and scenery.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});

  // Distances are metres along the OSM chain (startOffset) or relative to the start line (pit values).
  // pitOffset > 0 puts the pit lane on the right-hand side in the direction of travel.
  const TRACK_CONFIG = {
    gp: {
      name: 'Nürburgring GP-Strecke',
      short: 'GP-Strecke',
      width: 13,
      startOffset: 420,
      pitEntry: -405,
      pitExit: 360,
      pitRamp: 90,
      pitOffset: 14,
      boxStart: -250,
      boxSpacing: 12,
      runoff: 16,
      runoffColor: '#b9ae8c',
      treeDensity: 0.35,
      trees: { density: 0.35, patch: 0.45, conifer: 0.45 },
      terrainFine: 5,
      grandstands: true,
      osmNames: false,
      // chain distance -> corner name (OSM only names a few GP sections)
      corners: [
        [300, 'Start/Ziel'], [1040, 'Yokohama-S'], [1240, 'Mercedes-Arena'], [2080, 'Valvoline-Kurve'],
        [2260, 'Ford-Kurve'], [2820, 'Dunlop-Kehre'], [3240, 'Schumacher-S'], [3800, 'Kumho-Kurve'],
        [4000, 'Bit-Kurve'], [4440, 'Advan-Bogen'], [4940, 'NGK-Schikane'], [5180, 'Coca-Cola-Kurve'],
      ],
    },
    nordschleife: {
      name: 'Nürburgring Nordschleife',
      short: 'Nordschleife',
      width: 9.5,
      startOffset: 230, // on the T13 straight, grid clear of the Hohenrain corner
      pitEntry: -222,
      pitExit: 60,
      pitRamp: 45,
      pitOffset: 10.5,
      boxStart: -172,
      boxSpacing: 9,
      runoff: 4,
      runoffColor: '#4b7a3d',
      treeDensity: 1,
      trees: { density: 1.25, patch: 0.28, conifer: 0.82 },
      grandstands: false,
      osmNames: true,
      corners: [],
    },
    // ---- Triple Crown: Monaco, Indianapolis, Le Mans ----
    monaco: {
      name: 'Circuit de Monaco',
      short: 'Monaco',
      width: 9,
      startOffset: 0,
      pitEntry: -268, // after Anthony Noghès; the lane runs along the harbour to just before Sainte Dévote
      pitExit: 120,
      pitRamp: 40,
      pitOffset: 10,
      boxStart: -196,
      boxSpacing: 9,
      runoff: 0.6,
      runoffColor: '#8d8d88',
      runoffSurface: 'asphalt',
      treeDensity: 0.04,
      trees: { density: 0.05, patch: 0.5, conifer: 0 },
      terrainFine: 4,
      barrier: 'armco+fence',
      theme: 'city',
      sea: true,
      grandstands: true,
      stands: [-240, 100],
      osmNames: false,
      corners: [
        [0, 'Boulevard Albert Ier'], [170, 'Sainte Dévote'], [280, 'Beau Rivage'], [700, 'Massenet'], [860, 'Casino'],
        [1080, 'Mirabeau Haute'], [1215, 'Grand Hotel Hairpin'], [1300, 'Mirabeau Bas'], [1395, 'Portier'], [1480, 'Tunnel'],
        [1900, 'Nouvelle Chicane'], [2250, 'Tabac'], [2470, 'Piscine'], [2780, 'La Rascasse'], [2950, 'Anthony Noghès'],
        [3040, 'Boulevard Albert Ier'],
      ],
    },
    indy: {
      name: 'Indianapolis Motor Speedway',
      short: 'Indianapolis',
      width: 15,
      startOffset: 0,
      pitEntry: -420,
      pitExit: 250,
      pitRamp: 70,
      pitOffset: -15,
      boxStart: -250,
      boxSpacing: 13,
      runoff: 3,
      runoffColor: '#6f6f6a',
      runoffSurface: 'asphalt',
      treeDensity: 0.1,
      trees: { density: 0.12, patch: 0.55, conifer: 0.2 },
      terrainFine: 6,
      barrier: 'safer',
      banking: 9.2, // degrees in the turns (9°12'); the 3D view here still draws it flat
      standTiers: 14,
      theme: 'oval',
      grandstands: true,
      stands: [-600, 250],
      osmNames: false,
      corners: [
        [0, 'Front Stretch'], [308, 'Turn 1'], [712, 'South Short Chute'], [922, 'Turn 2'], [1330, 'Backstretch'],
        [2340, 'Turn 3'], [2748, 'North Short Chute'], [2958, 'Turn 4'], [3364, 'Front Stretch'],
      ],
    },
    lemans: {
      name: 'Circuit de la Sarthe (Le Mans)',
      short: 'Le Mans',
      width: 11,
      startOffset: 0,
      pitEntry: -226,
      pitExit: 540,
      pitRamp: 70,
      pitOffset: 14,
      boxStart: -80,
      boxSpacing: 13,
      runoff: 6,
      runoffColor: '#5a8a3f',
      theme: 'forest',
      treeDensity: 0.8,
      trees: { density: 0.9, patch: 0.36, conifer: 0.6 },
      grandstands: true,
      stands: [-200, 250],
      osmNames: true,
      corners: [],
    },
    // ---- Grand Prix classics: Monza, Silverstone, Spa-Francorchamps ----
    monza: {
      name: 'Autodromo Nazionale Monza',
      short: 'Monza',
      width: 12,
      startOffset: 0,
      pitEntry: -540, // the lane leaves at the Parabolica exit and runs the length of the start straight
      pitExit: 170,
      pitRamp: 70,
      pitOffset: 14,
      boxStart: -300,
      boxSpacing: 12,
      runoff: 12,
      runoffColor: '#a99c78',
      treeDensity: 1,
      trees: { density: 1.1, patch: 0.3, conifer: 0.2 },
      grandstands: true,
      stands: [-320, 250],
      osmNames: true,
      corners: [[0, 'Rettifilo']],
    },
    silverstone: {
      name: 'Silverstone Circuit',
      short: 'Silverstone',
      width: 13,
      startOffset: 0,
      pitEntry: -420,
      pitExit: 400,
      pitRamp: 70,
      pitOffset: 15,
      boxStart: -140,
      boxSpacing: 12,
      runoff: 10,
      runoffColor: '#9a9a90',
      treeDensity: 0.15,
      trees: { density: 0.2, patch: 0.5, conifer: 0.1 },
      grandstands: true,
      stands: [-300, 300],
      osmNames: true,
      corners: [],
    },
    spa: {
      name: 'Circuit de Spa-Francorchamps',
      short: 'Spa',
      width: 13,
      startOffset: 0,
      pitEntry: -222,
      pitExit: 540,
      pitRamp: 70,
      pitOffset: 16,
      boxStart: -120,
      boxSpacing: 12,
      runoff: 9,
      runoffColor: '#8f8a78',
      treeDensity: 1,
      trees: { density: 1.3, patch: 0.3, conifer: 0.85 },
      grandstands: true,
      stands: [-200, 250],
      osmNames: true,
      corners: [],
    },
  };
  // scenery defaults for configs that don't set them
  for (const c of Object.values(TRACK_CONFIG)) {
    c.theme = c.theme || 'forest';
    c.stands = c.stands || [-330, 250];
    c.runoffSurface = c.runoffSurface || (c.runoff > 8 ? 'gravel' : 'grass');
    c.barrier = c.barrier || (c.runoff > 8 ? 'tyres' : 'armco');
    c.terrainFine = c.terrainFine || 8;
    c.standTiers = c.standTiers || 5;
  }

  function mulberry32(seed) {
    return function () {
      seed |= 0;
      seed = (seed + 0x6d2b79f5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const smoothstep = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));
  const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));

  class Track {
    constructor(key) {
      const cfg = (this.cfg = TRACK_CONFIG[key]);
      const raw = window.TRACK_DATA[key];
      this.key = key;
      this.name = cfg.name;
      this.width = cfg.width;
      this.half = cfg.width / 2;
      const n = (this.n = raw.pts.length / 2);
      const step = (this.step = raw.step);
      this.L = n * step;

      const off = Math.round(cfg.startOffset / step);
      this.X = new Float64Array(n);
      this.Y = new Float64Array(n);
      this.H = new Float64Array(n); // elevation above sea level (m)
      for (let i = 0; i < n; i++) {
        const j = (i + off) % n;
        this.X[i] = raw.pts[2 * j];
        this.Y[i] = raw.pts[2 * j + 1];
        this.H[i] = raw.elev ? raw.elev[j] : 0;
      }
      this.grid = raw.grid || null;
      this.hMin = Math.min(...this.H);
      this.hMax = Math.max(...this.H);
      // road gradient along the direction of travel (rise over run)
      this.GRADE = new Float64Array(n);
      const gw = 5;
      for (let i = 0; i < n; i++) this.GRADE[i] = (this.H[(i + gw) % n] - this.H[(i - gw + n) % n]) / (2 * gw * step);
      this.sectors = (cfg.osmNames ? raw.names : [])
        .map(([j, name]) => [(((j - off) % n) + n) % n, name])
        .concat(cfg.corners.map(([cs, name]) => [(((Math.round(cs / step) - off) % n) + n) % n, name]))
        .sort((a, b) => a[0] - b[0]);

      this.buildFrames();
      this.buildBanking();
      this.buildCornerEnvelope();
      this.buildRacingLine();
      this.buildProfile();
      this.buildBounds();
    }

    buildFrames() {
      const { n, X, Y } = this;
      this.TX = new Float64Array(n);
      this.TY = new Float64Array(n);
      this.NX = new Float64Array(n);
      this.NY = new Float64Array(n);
      this.ANG = new Float64Array(n);
      this.KC = new Float64Array(n); // centreline curvature (+ = turning right on screen)
      for (let i = 0; i < n; i++) {
        const a = (i - 1 + n) % n;
        const b = (i + 1) % n;
        let tx = X[b] - X[a];
        let ty = Y[b] - Y[a];
        const l = Math.hypot(tx, ty) || 1;
        tx /= l;
        ty /= l;
        this.TX[i] = tx;
        this.TY[i] = ty;
        this.NX[i] = -ty;
        this.NY[i] = tx;
        this.ANG[i] = Math.atan2(ty, tx);
      }
      const m = 4;
      for (let i = 0; i < n; i++) {
        const da = wrapAngle(this.ANG[(i + m) % n] - this.ANG[(i - m + n) % n]);
        this.KC[i] = da / (2 * m * this.step);
      }
    }

    // Banked turns: cross slope (rise per metre towards +d), full where the curvature is near its peak.
    buildBanking() {
      const { n } = this;
      this.BANK = new Float64Array(n);
      if (!this.cfg.banking) return;
      const kFull = this.KC.reduce((a, k) => Math.max(a, Math.abs(k)), 0) * 0.85;
      const t = Math.tan((this.cfg.banking * Math.PI) / 180);
      for (let i = 0; i < n; i++) this.BANK[i] = -Math.sign(this.KC[i]) * t * smoothstep(Math.abs(this.KC[i]) / kFull);
    }

    // Peak curvature around each sample, so side offsets can be kept inside the corner radius.
    buildCornerEnvelope() {
      const { n } = this;
      this.KP = new Float64Array(n);
      const w = 8;
      for (let i = 0; i < n; i++) {
        let best = 0;
        for (let q = -w; q <= w; q++) {
          const k = this.KC[(i + q + n) % n];
          if (Math.abs(k) > Math.abs(best)) best = k;
        }
        this.KP[i] = best;
      }
    }

    // Lateral offset pulled in on the inside of tight corners so offset lines (run-off edges, barriers)
    // never fold back through the track.
    clampD(s, d) {
      const k = this.KP[Math.floor(this.wrap(s) / this.step) % this.n];
      if (k * d <= 0) return d;
      const lim = Math.max(this.half + 1.2, 0.8 / Math.abs(k));
      return Math.abs(d) > lim ? Math.sign(d) * lim : d;
    }

    // Iterative relaxation towards a short, low-curvature line inside the track limits.
    buildRacingLine() {
      const { n, X, Y, NX, NY } = this;
      const d = new Float64Array(n);
      const lim = this.half - 1.25;
      const passes = [
        [30, 120],
        [12, 120],
        [5, 80],
      ];
      for (const [k, iters] of passes) {
        for (let it = 0; it < iters; it++) {
          for (let i = 0; i < n; i++) {
            const a = (i - k + n) % n;
            const b = (i + k) % n;
            const px = (X[a] + NX[a] * d[a] + X[b] + NX[b] * d[b]) / 2;
            const py = (Y[a] + NY[a] * d[a] + Y[b] + NY[b] * d[b]) / 2;
            const dn = (px - X[i]) * NX[i] + (py - Y[i]) * NY[i];
            let v = d[i] + (dn - d[i]) * 0.6;
            d[i] = v > lim ? lim : v < -lim ? -lim : v;
          }
        }
      }
      this.RLD = d;
      this.RX = new Float64Array(n);
      this.RY = new Float64Array(n);
      for (let i = 0; i < n; i++) {
        this.RX[i] = X[i] + NX[i] * d[i];
        this.RY[i] = Y[i] + NY[i] * d[i];
      }
      this.RDS = new Float64Array(n); // path length from sample i to i+1 along the racing line
      const ang = new Float64Array(n);
      for (let i = 0; i < n; i++) {
        const j = (i + 1) % n;
        const dx = this.RX[j] - this.RX[i];
        const dy = this.RY[j] - this.RY[i];
        this.RDS[i] = Math.hypot(dx, dy);
        ang[i] = Math.atan2(dy, dx);
      }
      let k = new Float64Array(n);
      const m = 3;
      for (let i = 0; i < n; i++) {
        let len = 0;
        for (let q = -m; q < m; q++) len += this.RDS[(i + q + n) % n];
        k[i] = wrapAngle(ang[(i + m) % n] - ang[(i - m + n) % n]) / len;
      }
      for (let pass = 0; pass < 2; pass++) {
        const k2 = new Float64Array(n);
        for (let i = 0; i < n; i++) k2[i] = (k[(i - 1 + n) % n] + k[i] + k[(i + 1) % n]) / 3;
        k = k2;
      }
      this.RK = k;
      this.rlLength = this.RDS.reduce((a, b) => a + b, 0);
    }

    // Max speed at mu = 1 along the racing line: cornering limit + braking envelope.
    buildProfile() {
      const { n } = this;
      const G = SC.G;
      const vcap = 60;
      const p = new Float64Array(n);
      for (let i = 0; i < n; i++) {
        const t = Math.abs(this.BANK[i]); // banking adds to the centripetal force: g (mu + tan) / (1 - mu tan)
        p[i] = Math.min(vcap, Math.sqrt((G * (1 + t)) / (1 - t) / Math.max(Math.abs(this.RK[i]), 1e-5)));
      }
      this.CORNER = Float64Array.from(p);
      for (let pass = 0; pass < 2; pass++) {
        for (let q = n - 1; q >= 0; q--) {
          const j = (q + 1) % n;
          const aBrake = G * Math.max(0.5, 0.92 + this.GRADE[q]); // braking uphill is easier
          const lim = Math.sqrt(p[j] * p[j] + 2 * aBrake * this.RDS[q]);
          if (p[q] > lim) p[q] = lim;
        }
      }
      this.PROF = p;
    }

    buildBounds() {
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      for (let i = 0; i < this.n; i++) {
        minX = Math.min(minX, this.X[i]);
        maxX = Math.max(maxX, this.X[i]);
        minY = Math.min(minY, this.Y[i]);
        maxY = Math.max(maxY, this.Y[i]);
      }
      this.bounds = { minX, minY, maxX, maxY };
    }

    // ---------- lookups ----------
    wrap(s) {
      return ((s % this.L) + this.L) % this.L;
    }
    rel(s) {
      const L = this.L;
      return ((((s + L / 2) % L) + L) % L) - L / 2;
    }
    sample(arr, s) {
      const u = this.wrap(s) / this.step;
      const i = Math.floor(u) % this.n;
      const f = u - Math.floor(u);
      return arr[i] + (arr[(i + 1) % this.n] - arr[i]) * f;
    }
    pos(s, d) {
      const u = this.wrap(s) / this.step;
      const i = Math.floor(u) % this.n;
      const j = (i + 1) % this.n;
      const f = u - Math.floor(u);
      const nx = this.NX[i] + (this.NX[j] - this.NX[i]) * f;
      const ny = this.NY[i] + (this.NY[j] - this.NY[i]) * f;
      return {
        x: this.X[i] + (this.X[j] - this.X[i]) * f + nx * d,
        y: this.Y[i] + (this.Y[j] - this.Y[i]) * f + ny * d,
      };
    }
    heading(s) {
      const u = this.wrap(s) / this.step;
      const i = Math.floor(u) % this.n;
      const j = (i + 1) % this.n;
      return this.ANG[i] + wrapAngle(this.ANG[j] - this.ANG[i]) * (u - Math.floor(u));
    }
    curvature(s) {
      return this.sample(this.KC, s);
    }
    // Speed along the centreline parameter for a path offset d (Frenet: ds/dt = v / (1 - k d)).
    sRate(s, d) {
      const f = 1 - this.curvature(s) * d;
      return 1 / Math.max(0.5, Math.min(1.5, f));
    }

    // Nearest centreline point. hintS limits the search window so crossings never jump sections.
    project(x, y, hintS) {
      const { n, X, Y } = this;
      let bi = 0;
      let bd = Infinity;
      if (hintS == null) {
        for (let i = 0; i < n; i++) {
          const dd = (X[i] - x) ** 2 + (Y[i] - y) ** 2;
          if (dd < bd) {
            bd = dd;
            bi = i;
          }
        }
      } else {
        const c = Math.round(this.wrap(hintS) / this.step);
        for (let k = -40; k <= 40; k++) {
          const i = (((c + k) % n) + n) % n;
          const dd = (X[i] - x) ** 2 + (Y[i] - y) ** 2;
          if (dd < bd) {
            bd = dd;
            bi = i;
          }
        }
      }
      // refine on the neighbouring segments
      let best = { s: bi * this.step, d: 0, dist: Infinity };
      for (const i of [(bi - 1 + n) % n, bi]) {
        const j = (i + 1) % n;
        const sx = X[j] - X[i];
        const sy = Y[j] - Y[i];
        const l2 = sx * sx + sy * sy;
        let t = ((x - X[i]) * sx + (y - Y[i]) * sy) / l2;
        t = Math.max(0, Math.min(1, t));
        const px = X[i] + sx * t;
        const py = Y[i] + sy * t;
        const dist = Math.hypot(x - px, y - py);
        if (dist < best.dist) {
          const nx = this.NX[i] + (this.NX[j] - this.NX[i]) * t;
          const ny = this.NY[i] + (this.NY[j] - this.NY[i]) * t;
          best = { s: (i + t) * this.step, d: (x - px) * nx + (y - py) * ny, dist };
        }
      }
      return best;
    }

    sectorName(s) {
      const i = Math.floor(this.wrap(s) / this.step);
      let name = this.sectors.length ? this.sectors[this.sectors.length - 1][1] : '';
      for (const [si, nm] of this.sectors) {
        if (si <= i) name = nm;
        else break;
      }
      return name;
    }

    // ---------- pit lane ----------
    get laneStart() {
      return this.cfg.pitEntry + this.cfg.pitRamp;
    }
    get laneEnd() {
      return this.cfg.pitExit - this.cfg.pitRamp;
    }
    get wallD() {
      return (this.half + Math.abs(this.cfg.pitOffset) - 2.5) / 2;
    }
    pitBlend(s) {
      const p = this.rel(s);
      const c = this.cfg;
      if (p < c.pitEntry || p > c.pitExit) return 0;
      if (p < c.pitEntry + c.pitRamp) return smoothstep((p - c.pitEntry) / c.pitRamp);
      if (p > c.pitExit - c.pitRamp) return smoothstep((c.pitExit - p) / c.pitRamp);
      return 1;
    }
    boxS(i) {
      return this.cfg.boxStart + i * this.cfg.boxSpacing;
    }
    // Lateral barrier limits for a free-driving car at s.
    limits(s) {
      const p = this.rel(s);
      const c = this.cfg;
      let lo = this.clampD(s, -(this.half + c.runoff));
      let hi = this.clampD(s, this.half + c.runoff);
      const inWall = p > c.pitEntry + c.pitRamp * 0.55 && p < c.pitExit - c.pitRamp * 0.55;
      if (inWall) {
        if (c.pitOffset > 0) hi = Math.min(hi, this.wallD - 0.3);
        else lo = Math.max(lo, -this.wallD + 0.3);
      }
      return { lo, hi };
    }

    // ---------- scenery (built lazily, only needed for rendering) ----------
    buildScenery() {
      if (this.scenery) return this.scenery;
      const { n, X, Y, NX, NY, half } = this;
      const cfg = this.cfg;
      const rand = mulberry32(this.key.length * 7919 + n);

      // spatial hash of the centreline for clearance checks
      const cell = 20;
      const hash = new Map();
      for (let i = 0; i < n; i++) {
        const k = Math.floor(X[i] / cell) + ',' + Math.floor(Y[i] / cell);
        if (!hash.has(k)) hash.set(k, []);
        hash.get(k).push(i);
      }
      const clearance = (x, y) => {
        let best = Infinity;
        const cx = Math.floor(x / cell);
        const cy = Math.floor(y / cell);
        for (let a = -2; a <= 2; a++)
          for (let b = -2; b <= 2; b++) {
            const l = hash.get(cx + a + ',' + (cy + b));
            if (l) for (const i of l) best = Math.min(best, Math.hypot(X[i] - x, Y[i] - y));
          }
        return best;
      };

      const pitSide = Math.sign(cfg.pitOffset);
      const trees = [];
      const every = 3;
      for (let i = 0; i < n; i += every) {
        for (const side of [-1, 1]) {
          if (rand() > cfg.treeDensity) continue;
          const r = half + cfg.runoff + 5 + Math.pow(rand(), 1.4) * 60;
          const p = this.rel(i * this.step);
          if (side === pitSide && p > cfg.pitEntry - 40 && p < cfg.pitExit + 40 && r < Math.abs(cfg.pitOffset) + 30) continue;
          if (cfg.grandstands && side === -pitSide && p > cfg.stands[0] - 10 && p < cfg.stands[1] + 10 && r < half + cfg.runoff + 20) continue;
          const x = X[i] + NX[i] * r * side + (rand() - 0.5) * 6;
          const y = Y[i] + NY[i] * r * side + (rand() - 0.5) * 6;
          if (clearance(x, y) < half + cfg.runoff + 3) continue;
          trees.push({ x, y, r: 2.2 + rand() * 3.2, shade: rand() });
        }
      }
      // bucket trees for view culling
      const tcell = 150;
      const treeGrid = new Map();
      for (const t of trees) {
        const k = Math.floor(t.x / tcell) + ',' + Math.floor(t.y / tcell);
        if (!treeGrid.has(k)) treeGrid.set(k, []);
        treeGrid.get(k).push(t);
      }

      const centre = new Path2D();
      centre.moveTo(X[0], Y[0]);
      for (let i = 1; i < n; i++) centre.lineTo(X[i], Y[i]);
      centre.closePath();

      const racing = { accel: new Path2D(), brake: new Path2D() };
      for (let i = 0; i < n; i += 1) {
        const j = (i + 1) % n;
        const ahead = this.PROF[(i + 6) % n];
        const braking = ahead < this.PROF[i] - 0.4;
        const path = braking ? racing.brake : racing.accel;
        path.moveTo(this.RX[i], this.RY[i]);
        path.lineTo(this.RX[j], this.RY[j]);
      }

      // offset polyline between relative distances p0..p1
      const strip = (p0, p1, dFn) => {
        const path = new Path2D();
        let first = true;
        for (let p = p0; p <= p1; p += this.step) {
          const q = this.pos(p, dFn(p));
          if (first) path.moveTo(q.x, q.y);
          else path.lineTo(q.x, q.y);
          first = false;
        }
        return path;
      };
      const quad = (p0, p1, d0, d1) => {
        const path = new Path2D();
        const pts = [];
        for (let p = p0; p <= p1 + 1e-6; p += Math.min(this.step, p1 - p0 || 1)) pts.push(this.pos(p, d0));
        for (let p = p1; p >= p0 - 1e-6; p -= Math.min(this.step, p1 - p0 || 1)) pts.push(this.pos(p, d1));
        path.moveTo(pts[0].x, pts[0].y);
        for (const q of pts) path.lineTo(q.x, q.y);
        path.closePath();
        return path;
      };

      const po = cfg.pitOffset;
      const sg = Math.sign(po);
      const laneC = po + sg * 1;
      const pitLane = strip(cfg.pitEntry, cfg.pitExit, (p) => {
        const b = this.pitBlend(p);
        return sg * (half - 1.5) + (laneC - sg * (half - 1.5)) * b;
      });
      const pitWall = strip(cfg.pitEntry + cfg.pitRamp * 0.55, cfg.pitExit - cfg.pitRamp * 0.55, () => sg * this.wallD);
      const garage = quad(this.boxS(0) - 20, this.boxS(15) + 20, po + sg * 5.2, po + sg * 20);
      const boxes = [];
      for (let b = 0; b < 16; b++) {
        const s = this.boxS(b);
        boxes.push(quad(s - cfg.boxSpacing / 2 + 0.6, s + cfg.boxSpacing / 2 - 0.6, po + sg * 2.2, po + sg * 5));
      }

      const grandstands = [];
      if (cfg.grandstands) {
        const d0 = -sg * (half + cfg.runoff + 3);
        const d1 = -sg * (half + cfg.runoff + 16);
        for (let p = cfg.stands[0]; p < cfg.stands[1] - 10; p += 70) grandstands.push(quad(p, p + 62, d0, d1));
      }

      // kerbs on the inside of real corners
      const kerbRed = new Path2D();
      const kerbWhite = new Path2D();
      for (let i = 0; i < n; i++) {
        const k = this.KC[i];
        if (Math.abs(k) < 1 / 170) continue;
        const sd = Math.sign(k);
        const s0 = i * this.step;
        const target = (i >> 0) % 2 === 0 ? kerbRed : kerbWhite;
        const a0 = this.pos(s0, sd * (half - 0.9));
        const a1 = this.pos(s0 + this.step, sd * (half - 0.9));
        const b1 = this.pos(s0 + this.step, sd * (half + 0.4));
        const b0 = this.pos(s0, sd * (half + 0.4));
        target.moveTo(a0.x, a0.y);
        target.lineTo(a1.x, a1.y);
        target.lineTo(b1.x, b1.y);
        target.lineTo(b0.x, b0.y);
        target.closePath();
      }

      const barrierD = half + cfg.runoff + 0.4;
      const barrier = [strip(-this.L / 2, this.L / 2, () => barrierD), strip(-this.L / 2, this.L / 2, () => -barrierD)];

      this.scenery = { trees, treeGrid, tcell, centre, racing, pitLane, pitWall, garage, boxes, grandstands, kerbRed, kerbWhite, barrier };
      return this.scenery;
    }
  }

  SC.TRACK_CONFIG = TRACK_CONFIG;
  SC.Track = Track;
  // Sun elevation/azimuth (degrees) for local time h on a June race weekend at ~48–50°N,
  // and how much daylight that gives (0 = night, 1 = full day).
  function sunAt(h) {
    const rise = 5.9;
    const set = 21.6;
    let el;
    if (h >= rise && h <= set) el = 63 * Math.sin((Math.PI * (h - rise)) / (set - rise));
    else el = -20 * Math.sin((Math.PI * ((h - set + 24) % 24)) / (24 - (set - rise)));
    return { el, az: 180 + (h - 13.75) * 16, day: smoothstep((el + 6) / 14) };
  }

  SC.util = { mulberry32, smoothstep, wrapAngle, sunAt };
})();
