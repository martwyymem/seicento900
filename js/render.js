// Classic 2D canvas renderer (top-down) and the HUD minimap.
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const { CAR } = SC.Car;

  function shade(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
    if (f > 0) {
      r += (255 - r) * f;
      g += (255 - g) * f;
      b += (255 - b) * f;
    } else {
      r *= 1 + f;
      g *= 1 + f;
      b *= 1 + f;
    }
    return `rgb(${r | 0},${g | 0},${b | 0})`;
  }

  // Top-down Fiat Seicento, local frame: +x forward, units metres.
  function drawSeicento(ctx, car, alpha) {
    const hl = CAR.length / 2;
    const hw = CAR.width / 2;
    ctx.save();
    ctx.translate(car.x, car.y);
    ctx.rotate(car.heading);
    ctx.globalAlpha = alpha;

    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath();
    ctx.roundRect(-hl + 0.2, -hw + 0.25, CAR.length, CAR.width, 0.55);
    ctx.fill();

    ctx.fillStyle = car.color;
    ctx.beginPath();
    ctx.roundRect(-hl, -hw, CAR.length, CAR.width, [0.62, 0.62, 0.45, 0.45]);
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.45)';
    ctx.lineWidth = 0.06;
    ctx.stroke();

    // bonnet crease + bumpers
    ctx.fillStyle = 'rgba(40,40,40,0.9)';
    ctx.fillRect(hl - 0.1, -hw + 0.12, 0.1, CAR.width - 0.24);
    ctx.fillRect(-hl, -hw + 0.12, 0.1, CAR.width - 0.24);

    if (car.stripes) {
      ctx.fillStyle = car.stripeColor || '#ffffff';
      ctx.fillRect(-hl + 0.1, -0.22, CAR.length - 0.2, 0.14);
      ctx.fillRect(-hl + 0.1, 0.08, CAR.length - 0.2, 0.14);
    }

    // glasshouse
    ctx.fillStyle = '#1b2530';
    ctx.beginPath();
    ctx.moveTo(0.9, -hw + 0.18);
    ctx.lineTo(0.9, hw - 0.18);
    ctx.lineTo(0.4, hw - 0.1);
    ctx.lineTo(-1.25, hw - 0.1);
    ctx.lineTo(-1.5, hw - 0.2);
    ctx.lineTo(-1.5, -hw + 0.2);
    ctx.lineTo(-1.25, -hw + 0.1);
    ctx.lineTo(0.4, -hw + 0.1);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = shade(car.color, 0.12);
    ctx.beginPath();
    ctx.roundRect(-1.15, -hw + 0.22, 1.5, CAR.width - 0.44, 0.15);
    ctx.fill();
    if (car.stripes) {
      ctx.fillStyle = car.stripeColor || '#ffffff';
      ctx.fillRect(-1.15, -0.22, 1.5, 0.14);
      ctx.fillRect(-1.15, 0.08, 1.5, 0.14);
    }

    // roof number
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(-0.42, 0, 0.36, 0, Math.PI * 2);
    ctx.fill();
    ctx.save();
    ctx.translate(-0.42, 0);
    ctx.rotate(Math.PI / 2);
    ctx.fillStyle = '#111';
    ctx.font = 'bold 0.44px system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(car.number), 0, 0.03);
    ctx.restore();

    // lights
    ctx.fillStyle = '#fff4c4';
    ctx.fillRect(hl - 0.16, -hw + 0.12, 0.12, 0.3);
    ctx.fillRect(hl - 0.16, hw - 0.42, 0.12, 0.3);
    ctx.fillStyle = car.brakeOn ? '#ff2a2a' : '#8a1010';
    ctx.fillRect(-hl + 0.02, -hw + 0.1, 0.1, 0.32);
    ctx.fillRect(-hl + 0.02, hw - 0.42, 0.1, 0.32);
    if (car.brakeOn) {
      ctx.fillStyle = 'rgba(255,40,40,0.25)';
      ctx.beginPath();
      ctx.arc(-hl - 0.2, -hw + 0.26, 0.5, 0, Math.PI * 2);
      ctx.arc(-hl - 0.2, hw - 0.26, 0.5, 0, Math.PI * 2);
      ctx.fill();
    }
    // mirrors
    ctx.fillStyle = shade(car.color, -0.3);
    ctx.fillRect(0.35, -hw - 0.12, 0.16, 0.14);
    ctx.fillRect(0.35, hw - 0.02, 0.16, 0.14);
    ctx.restore();
  }

  // Track map in the HUD corner, shared by the 2D and 3D views.
  class Minimap {
    constructor(canvas) {
      this.mini = canvas;
      this.mctx = canvas.getContext('2d');
      this.resize();
      window.addEventListener('resize', () => this.resize());
    }

    resize() {
      this.dpr = Math.min(2, window.devicePixelRatio || 1);
      const ms = this.mini.clientWidth || 220;
      this.mini.width = ms * this.dpr;
      this.mini.height = ms * this.dpr;
      this.miniTrack = null;
    }

    build() {
      const tr = this.track;
      const c = document.createElement('canvas');
      c.width = this.mini.width;
      c.height = this.mini.height;
      const g = c.getContext('2d');
      const b = tr.bounds;
      const pad = 12 * this.dpr;
      const sc = Math.min((c.width - 2 * pad) / (b.maxX - b.minX), (c.height - 2 * pad) / (b.maxY - b.minY));
      const ox = (c.width - (b.maxX - b.minX) * sc) / 2 - b.minX * sc;
      const oy = (c.height - (b.maxY - b.minY) * sc) / 2 - b.minY * sc;
      this.miniXf = { sc, ox, oy };
      const centre = tr.buildScenery().centre;
      g.lineJoin = 'round';
      g.setTransform(sc, 0, 0, sc, ox, oy);
      g.strokeStyle = 'rgba(0,0,0,0.6)';
      g.lineWidth = (7 * this.dpr) / sc;
      g.stroke(centre);
      g.strokeStyle = '#e9edf2';
      g.lineWidth = (3.2 * this.dpr) / sc;
      g.stroke(centre);
      const p = tr.pos(0, 0);
      const n = tr.pos(0, tr.half * 3);
      g.strokeStyle = '#ff3b3b';
      g.lineWidth = (3 * this.dpr) / sc;
      g.beginPath();
      g.moveTo(2 * p.x - n.x, 2 * p.y - n.y);
      g.lineTo(n.x, n.y);
      g.stroke();
      this.miniTrack = c;
    }

    draw(race, focus) {
      if (this.track !== race.track) {
        this.track = race.track;
        this.miniTrack = null;
      }
      if (!this.miniTrack) this.build();
      const g = this.mctx;
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.clearRect(0, 0, this.mini.width, this.mini.height);
      g.drawImage(this.miniTrack, 0, 0);
      const { sc, ox, oy } = this.miniXf;
      const cars = race.cars.slice().sort((a, b) => (a === focus) - (b === focus));
      for (const car of cars) {
        if (car.dnf) continue;
        const x = car.x * sc + ox;
        const y = car.y * sc + oy;
        const r = (car === focus ? 5 : 3.2) * this.dpr;
        g.beginPath();
        g.arc(x, y, r, 0, Math.PI * 2);
        g.fillStyle = car.color;
        g.fill();
        g.lineWidth = (car === focus ? 2 : 1) * this.dpr;
        g.strokeStyle = car === focus ? '#fff' : 'rgba(0,0,0,0.7)';
        g.stroke();
      }
    }
  }

  class Renderer {
    constructor(canvas) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.cam = { x: 0, y: 0, angle: 0, zoom: 6 };
      this.drops = [];
      for (let i = 0; i < 400; i++) this.drops.push({ x: Math.random(), y: Math.random(), z: 0.4 + Math.random() * 0.6 });
      this.resize();
      window.addEventListener('resize', () => this.resize());
    }

    resize() {
      this.dpr = Math.min(2, window.devicePixelRatio || 1);
      this.W = window.innerWidth;
      this.H = window.innerHeight;
      this.canvas.width = this.W * this.dpr;
      this.canvas.height = this.H * this.dpr;
    }

    setTrack(track) {
      if (this.track === track) return;
      this.track = track;
      this.sc = track.buildScenery();
      this.cam.snap = true;
    }

    updateCamera(focus, dt, rotate) {
      const cam = this.cam;
      const v = Math.hypot(focus.vx, focus.vy);
      const base = Math.min(this.W, this.H) / 105;
      const zoom = base * (1.15 - 0.45 * Math.min(1, v / 38));
      const k = cam.snap ? 1 : 1 - Math.exp(-dt * 6);
      const target = rotate ? focus.heading : -Math.PI / 2;
      let da = Math.atan2(Math.sin(target - cam.angle), Math.cos(target - cam.angle));
      cam.angle += da * (cam.snap ? 1 : 1 - Math.exp(-dt * 5));
      // look ahead of the car
      const ahead = rotate ? 0 : Math.min(18, v * 0.4);
      cam.x += (focus.x + Math.cos(focus.heading) * ahead - cam.x) * k;
      cam.y += (focus.y + Math.sin(focus.heading) * ahead - cam.y) * k;
      cam.zoom += ((this.debugZoom || zoom) - cam.zoom) * (cam.snap || this.debugZoom ? 1 : 1 - Math.exp(-dt * 2));
      cam.rotate = rotate;
      cam.snap = false;
    }

    draw(race, focus, opts) {
      const ctx = this.ctx;
      const tr = race.track;
      this.setTrack(tr);
      const sc = this.sc;
      const cfg = tr.cfg;
      const cam = this.cam;
      const wet = race.weather.wet;
      const rain = race.weather.rain;
      const { W, H, dpr } = this;

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.fillStyle = wet > 0 ? shade('#4f8a3f', -0.25 * wet) : '#4f8a3f';
      ctx.fillRect(0, 0, W, H);

      ctx.save();
      ctx.translate(W / 2, cam.rotate ? H * 0.64 : H / 2);
      ctx.scale(cam.zoom, cam.zoom);
      ctx.rotate(-cam.angle - Math.PI / 2);
      ctx.translate(-cam.x, -cam.y);
      const viewR = Math.hypot(W, H) / cam.zoom;

      ctx.lineJoin = 'round';
      ctx.lineCap = 'butt';
      // run-off, barriers, track surface
      ctx.strokeStyle = cfg.runoffColor;
      ctx.lineWidth = tr.width + cfg.runoff * 2;
      ctx.stroke(sc.centre);
      ctx.strokeStyle = cfg.runoff < 8 ? '#c9ccd1' : '#2b2b2b';
      ctx.lineWidth = cfg.runoff < 8 ? 0.35 : 0.9;
      for (const b of sc.barrier) ctx.stroke(b);

      // pit lane + buildings
      ctx.strokeStyle = '#5b5c61';
      ctx.lineWidth = 7;
      ctx.stroke(sc.pitLane);
      ctx.fillStyle = '#6f737b';
      ctx.fill(sc.garage);
      for (let i = 0; i < sc.boxes.length; i++) {
        const car = race.cars.find((c) => c.box === i);
        ctx.fillStyle = car ? car.color : '#777';
        ctx.globalAlpha = 0.28;
        ctx.fill(sc.boxes[i]);
        ctx.globalAlpha = 1;
        ctx.strokeStyle = 'rgba(255,255,255,0.7)';
        ctx.lineWidth = 0.2;
        ctx.stroke(sc.boxes[i]);
      }
      ctx.fillStyle = '#4c5a74';
      for (const g of sc.grandstands) ctx.fill(g);

      ctx.strokeStyle = '#f0f0f0';
      ctx.lineWidth = tr.width + 0.7;
      ctx.stroke(sc.centre);
      ctx.strokeStyle = '#46474c';
      ctx.lineWidth = tr.width - 0.5;
      ctx.stroke(sc.centre);
      if (wet > 0.02) {
        ctx.strokeStyle = `rgba(25,45,75,${(wet * 0.5).toFixed(3)})`;
        ctx.stroke(sc.centre);
      }
      ctx.fillStyle = '#d42a2a';
      ctx.fill(sc.kerbRed);
      ctx.fillStyle = '#f4f4f4';
      ctx.fill(sc.kerbWhite);
      ctx.strokeStyle = '#d8d8d8';
      ctx.lineWidth = 0.6;
      ctx.stroke(sc.pitWall);

      if (opts.racingLine) {
        ctx.lineWidth = 0.55;
        ctx.strokeStyle = 'rgba(90,230,120,0.4)';
        ctx.stroke(sc.racing.accel);
        ctx.strokeStyle = 'rgba(255,70,60,0.55)';
        ctx.stroke(sc.racing.brake);
      }

      this.drawStartLine(ctx, tr);

      // cars (player drawn last)
      const cars = race.cars.slice().sort((a, b) => (a === focus) - (b === focus));
      for (const car of cars) {
        if ((car.x - cam.x) ** 2 + (car.y - cam.y) ** 2 > viewR * viewR) continue;
        drawSeicento(ctx, car, car.finished && car !== focus ? 0.55 : car.dnf ? 0.4 : 1);
      }

      // trees above cars (canopy)
      const tc = sc.tcell;
      const x0 = Math.floor((cam.x - viewR) / tc), x1 = Math.floor((cam.x + viewR) / tc);
      const y0 = Math.floor((cam.y - viewR) / tc), y1 = Math.floor((cam.y + viewR) / tc);
      ctx.fillStyle = 'rgba(0,0,0,0.25)';
      const visible = [];
      for (let gx = x0; gx <= x1; gx++)
        for (let gy = y0; gy <= y1; gy++) {
          const l = sc.treeGrid.get(gx + ',' + gy);
          if (l) for (const t of l) visible.push(t);
        }
      ctx.beginPath();
      for (const t of visible) {
        ctx.moveTo(t.x + 1.2 + t.r, t.y + 1.2);
        ctx.arc(t.x + 1.2, t.y + 1.2, t.r, 0, Math.PI * 2);
      }
      ctx.fill();
      for (const t of visible) {
        ctx.fillStyle = t.shade < 0.5 ? '#2d5a2a' : '#356b2f';
        ctx.beginPath();
        ctx.arc(t.x, t.y, t.r, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = t.shade < 0.5 ? '#3c7336' : '#468039';
        ctx.beginPath();
        ctx.arc(t.x - t.r * 0.25, t.y - t.r * 0.25, t.r * 0.55, 0, Math.PI * 2);
        ctx.fill();
      }

      // name tags
      const m = ctx.getTransform();
      ctx.restore();
      const night = 1 - SC.util.sunAt(race.timeOfDay).day;
      if (night > 0.02) this.drawNight(ctx, race, m, night, viewR);
      ctx.font = '600 11px system-ui, sans-serif';
      ctx.textAlign = 'center';
      for (const car of race.cars) {
        if (car === focus || car.dnf) continue;
        const dx = car.x - focus.x, dy = car.y - focus.y;
        if (dx * dx + dy * dy > 70 * 70) continue;
        const p = m.transformPoint(new DOMPoint(car.x, car.y));
        const sx = p.x / dpr, sy = p.y / dpr - 2.4 * cam.zoom;
        const label = `P${car.pos} ${car.name.split(' ').pop()}`;
        const w = ctx.measureText(label).width + 10;
        ctx.fillStyle = 'rgba(10,12,16,0.65)';
        ctx.fillRect(sx - w / 2, sy - 14, w, 16);
        ctx.fillStyle = car.color;
        ctx.fillRect(sx - w / 2, sy - 14, 3, 16);
        ctx.fillStyle = '#fff';
        ctx.fillText(label, sx + 1, sy - 2);
      }

      if (rain > 0.02) this.drawRain(ctx, rain);
    }

    drawStartLine(ctx, tr) {
      const h = tr.heading(0);
      const p = tr.pos(0, 0);
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(h);
      const sq = 0.8;
      const cols = Math.floor(tr.width / sq);
      for (let r = 0; r < 2; r++)
        for (let c = 0; c < cols; c++) {
          ctx.fillStyle = (r + c) % 2 ? '#111' : '#fafafa';
          ctx.fillRect(r * sq - sq, -tr.width / 2 + c * sq + (tr.width - cols * sq) / 2, sq, sq);
        }
      ctx.restore();
      // grid boxes
      ctx.strokeStyle = 'rgba(255,255,255,0.8)';
      ctx.lineWidth = 0.25;
      for (let k = 0; k < 16; k++) {
        const s = -(9 + k * 6.5) + 2.2;
        const d = (k % 2 === 0 ? -1 : 1) * tr.half * 0.36;
        const a = tr.pos(s, d - 1.1);
        const b = tr.pos(s, d + 1.1);
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }
    }

    // Darkness over the scene with headlight cones cut out of it.
    drawNight(ctx, race, m, night, viewR) {
      const c = this.canvas;
      const nc = this.nightCanvas || (this.nightCanvas = document.createElement('canvas'));
      if (nc.width !== c.width || nc.height !== c.height) {
        nc.width = c.width;
        nc.height = c.height;
      }
      const n = nc.getContext('2d');
      n.setTransform(1, 0, 0, 1, 0, 0);
      n.globalCompositeOperation = 'source-over';
      n.clearRect(0, 0, nc.width, nc.height);
      n.fillStyle = `rgba(3,6,18,${(0.78 * night).toFixed(3)})`;
      n.fillRect(0, 0, nc.width, nc.height);
      n.globalCompositeOperation = 'destination-out';
      n.setTransform(m);
      const cam = this.cam;
      for (const car of race.cars) {
        if (car.dnf || (car.x - cam.x) ** 2 + (car.y - cam.y) ** 2 > viewR * viewR) continue;
        n.save();
        n.translate(car.x, car.y);
        n.rotate(car.heading);
        const g = n.createRadialGradient(1.6, 0, 0, 1.6, 0, 34);
        g.addColorStop(0, 'rgba(0,0,0,0.95)');
        g.addColorStop(1, 'rgba(0,0,0,0)');
        n.fillStyle = g;
        n.beginPath();
        n.moveTo(1.6, -0.7);
        n.lineTo(34, -11);
        n.lineTo(34, 11);
        n.lineTo(1.6, 0.7);
        n.closePath();
        n.fill();
        n.fillStyle = 'rgba(0,0,0,0.6)';
        n.beginPath();
        n.arc(0, 0, 3.2, 0, Math.PI * 2);
        n.fill();
        n.restore();
      }
      ctx.save();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.drawImage(nc, 0, 0);
      ctx.restore();
      // tail lights stay visible in the dark
      ctx.save();
      ctx.setTransform(m);
      ctx.fillStyle = `rgba(255,40,40,${(0.9 * night).toFixed(3)})`;
      for (const car of race.cars) {
        if (car.dnf || (car.x - cam.x) ** 2 + (car.y - cam.y) ** 2 > viewR * viewR) continue;
        const ch = Math.cos(car.heading), sh = Math.sin(car.heading);
        for (const side of [-0.55, 0.55]) {
          ctx.beginPath();
          ctx.arc(car.x - ch * 1.7 - sh * side, car.y - sh * 1.7 + ch * side, car.brakeOn ? 0.35 : 0.22, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      ctx.restore();
    }

    drawRain(ctx, rain) {
      const { W, H } = this;
      const n = Math.floor(this.drops.length * Math.min(1, rain));
      ctx.fillStyle = `rgba(40,60,90,${(rain * 0.16).toFixed(3)})`;
      ctx.fillRect(0, 0, W, H);
      ctx.strokeStyle = 'rgba(200,215,235,0.45)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 0; i < n; i++) {
        const d = this.drops[i];
        d.y += 0.02 * d.z;
        d.x += 0.004 * d.z;
        if (d.y > 1) {
          d.y -= 1;
          d.x = Math.random();
        }
        if (d.x > 1) d.x -= 1;
        const x = d.x * W, y = d.y * H;
        ctx.moveTo(x, y);
        ctx.lineTo(x + 3 * d.z, y + 14 * d.z);
      }
      ctx.stroke();
    }
  }

  SC.Renderer = Renderer;
  SC.Minimap = Minimap;
  SC.drawSeicento = drawSeicento;
})();
