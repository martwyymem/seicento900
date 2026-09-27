// 3D renderer (Three.js): real-elevation terrain, road, pits, forests, Seicento models and cameras.
// Simulation coordinates (x east, y south, metres) map to Three as (x, height, y).
(function () {
  'use strict';
  const SC = (window.SC = window.SC || {});
  const THREE = window.THREE;
  const { CAR } = SC.Car;
  const { mulberry32, smoothstep, sunAt } = SC.util;

  function webglAvailable() {
    try {
      const c = document.createElement('canvas');
      return !!(window.WebGLRenderingContext && (c.getContext('webgl2') || c.getContext('webgl')));
    } catch (e) {
      return false;
    }
  }

  // ---------------- procedural textures ----------------
  function canvasTex(w, h, paint, srgb = true) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    paint(c.getContext('2d'), w, h);
    const t = new THREE.CanvasTexture(c);
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.anisotropy = 8;
    return t;
  }
  // Texture from per-pixel float channels (0..1); rgb and optional alpha arrays of size*size.
  function pixelTex(size, r, g, b, a, srgb = true) {
    return canvasTex(size, size, (ctx) => {
      const img = ctx.createImageData(size, size);
      const d = img.data;
      for (let i = 0, o = 0; i < size * size; i++, o += 4) {
        d[o] = r[i] * 255;
        d[o + 1] = g[i] * 255;
        d[o + 2] = b[i] * 255;
        d[o + 3] = a ? a[i] * 255 : 255;
      }
      ctx.putImageData(img, 0, 0);
    }, srgb);
  }
  // Tileable fractal value noise on a size×size grid, roughly 0..1. period = lattice cells of the first octave.
  function fbmField(size, period, octaves, seed, gain = 0.5) {
    const out = new Float32Array(size * size);
    let amp = 1;
    let norm = 0;
    for (let o = 0; o < octaves; o++) {
      const p = period << o;
      const lat = new Float32Array(p * p);
      const r = mulberry32(seed * 131 + o * 7919);
      for (let i = 0; i < lat.length; i++) lat[i] = r();
      const k = p / size;
      for (let y = 0; y < size; y++) {
        const fy = y * k;
        const j = Math.floor(fy);
        const v = smoothstep(fy - j);
        const j0 = (j % p) * p;
        const j1 = ((j + 1) % p) * p;
        for (let x = 0; x < size; x++) {
          const fx = x * k;
          const i = Math.floor(fx);
          const u = smoothstep(fx - i);
          const a = lat[j0 + (i % p)], b = lat[j0 + ((i + 1) % p)], c = lat[j1 + (i % p)], d = lat[j1 + ((i + 1) % p)];
          out[y * size + x] += amp * (a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v);
        }
      }
      norm += amp;
      amp *= gain;
    }
    for (let i = 0; i < out.length; i++) out[i] /= norm;
    return out;
  }
  // Tangent-space normal map (OpenGL convention) from a tileable height field.
  function normalTex(hgt, size, strength) {
    const r = new Float32Array(size * size), g = new Float32Array(size * size), b = new Float32Array(size * size);
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const i = y * size + x;
        const l = hgt[y * size + ((x + size - 1) % size)], rr = hgt[y * size + ((x + 1) % size)];
        const up = hgt[((y + size - 1) % size) * size + x], dn = hgt[((y + 1) % size) * size + x];
        const nx = (l - rr) * strength, ny = (dn - up) * strength;
        const inv = 1 / Math.hypot(nx, ny, 1);
        r[i] = nx * inv * 0.5 + 0.5;
        g[i] = ny * inv * 0.5 + 0.5;
        b[i] = inv * 0.5 + 0.5;
      }
    return pixelTex(size, r, g, b, null, false);
  }
  // Stamp a round stone (wrapping) into colour/height layers.
  function stone(L, size, cx, cy, rad, tone, tint, lift) {
    const R = Math.ceil(rad);
    for (let dy = -R; dy <= R; dy++)
      for (let dx = -R; dx <= R; dx++) {
        const d = Math.hypot(dx, dy) / rad;
        if (d > 1) continue;
        const x = (((cx + dx) | 0) % size + size) % size;
        const y = (((cy + dy) | 0) % size + size) % size;
        const i = y * size + x;
        const dome = Math.sqrt(1 - d * d);
        const shade = tone * (0.8 + 0.25 * dome - 0.12 * (dx + dy) / rad);
        L.r[i] = shade * tint[0];
        L.g[i] = shade * tint[1];
        L.b[i] = shade * tint[2];
        L.h[i] = Math.max(L.h[i], lift * dome);
        if (L.m) L.m[i] = 1;
      }
  }
  function layers(size, base, noise, amt) {
    const n = size * size;
    const L = { r: new Float32Array(n), g: new Float32Array(n), b: new Float32Array(n), h: new Float32Array(n), m: new Float32Array(n) };
    for (let i = 0; i < n; i++) {
      const k = 1 + (noise[i] - 0.5) * amt;
      L.r[i] = base[0] * k;
      L.g[i] = base[1] * k;
      L.b[i] = base[2] * k;
    }
    return L;
  }
  const TEX = {};
  function textures() {
    if (TEX.asphalt) return TEX;
    const rand = mulberry32(42);
    const S = 512;

    // asphalt: dark binder with exposed aggregate, fine pores; tiles every 5 m
    {
      const L = layers(S, [0.27, 0.27, 0.285], fbmField(S, 6, 4, 11), 0.3);
      const fine = fbmField(S, 64, 2, 12);
      for (let i = 0; i < S * S; i++) L.h[i] = fine[i] * 0.25;
      for (let k = 0; k < 16000; k++) {
        const t = 0.24 + Math.pow(rand(), 2.2) * 0.3;
        const warm = rand() < 0.25 ? [1.08, 1.0, 0.9] : [1, 1, 1.02];
        stone(L, S, rand() * S, rand() * S, 0.6 + Math.pow(rand(), 2.5) * 1.6, t, warm, 0.6 + rand() * 0.4);
      }
      for (let k = 0; k < 5000; k++) {
        const i = ((rand() * S) | 0) * S + ((rand() * S) | 0);
        L.r[i] *= 0.7;
        L.g[i] *= 0.7;
        L.b[i] *= 0.7;
        L.h[i] = -0.4;
      }
      TEX.asphalt = pixelTex(S, L.r, L.g, L.b);
      TEX.asphaltN = normalTex(L.h, S, 2.2);
      const ro = L.m.map((m, i) => 0.95 - 0.2 * m - 0.1 * fine[i]);
      TEX.asphaltR = pixelTex(S, ro, ro, ro, null, false);
    }
    // gravel trap: packed rounded stones, beige and grey
    {
      const L = layers(S, [0.55, 0.5, 0.4], fbmField(S, 8, 3, 21), 0.3);
      const cols = [[1.0, 0.92, 0.76], [0.92, 0.9, 0.86], [1.0, 0.86, 0.66], [0.8, 0.78, 0.74]];
      for (let k = 0; k < 16000; k++) stone(L, S, rand() * S, rand() * S, 1.2 + rand() * 3.2, 0.45 + rand() * 0.35, cols[(rand() * 4) | 0], 1);
      TEX.gravel = pixelTex(S, L.r, L.g, L.b);
      TEX.gravelN = normalTex(L.h, S, 3);
    }
    // grass: near-neutral blades (vertex / material colour gives the hue); tiles every 9 m
    {
      const base = fbmField(S, 8, 4, 31);
      const L = layers(S, [0.5, 0.5, 0.48], base, 0.5);
      for (let i = 0; i < S * S; i++) L.h[i] = base[i] * 0.3;
      for (let k = 0; k < 42000; k++) {
        let x = rand() * S, y = rand() * S;
        const len = 3 + rand() * 7;
        const ang = -Math.PI / 2 + (rand() - 0.5) * 0.9;
        const t = 0.32 + rand() * 0.48;
        const tint = rand() < 0.2 ? [1.12, 1.04, 0.78] : rand() < 0.3 ? [0.9, 1.0, 1.05] : [1, 1, 0.96];
        for (let s = 0; s < len; s++) {
          const i = (((y | 0) % S + S) % S) * S + (((x | 0) % S + S) % S);
          const f = t * (0.75 + 0.35 * (s / len));
          L.r[i] = f * tint[0];
          L.g[i] = f * tint[1];
          L.b[i] = f * tint[2];
          L.h[i] = 0.3 + 0.7 * (s / len);
          x += Math.cos(ang);
          y += Math.sin(ang);
        }
      }
      TEX.grass = pixelTex(S, L.r, L.g, L.b, null, false);
      TEX.grassN = normalTex(L.h, S, 1.2);
    }
    // large-scale variation, sampled at a low frequency to break up tiling
    {
      const m = fbmField(256, 4, 5, 41, 0.55);
      TEX.macro = pixelTex(256, m, m, m, null, false);
    }
    // foliage: leaves / needles with alpha, near-neutral (instance colour gives the green)
    // (the near-transparent fill keeps mipmaps from bleeding black into the leaf colour)
    TEX.leaves = canvasTex(256, 256, (g, w, h) => {
      g.clearRect(0, 0, w, h);
      g.fillStyle = 'rgba(112,118,96,0.012)';
      g.fillRect(0, 0, w, h);
      const r = mulberry32(51);
      for (let i = 0; i < 2600; i++) {
        const x = r() * w, y = r() * h;
        const l = 30 + r() * 38;
        g.fillStyle = `hsl(${70 + r() * 30},${10 + r() * 18}%,${l}%)`;
        g.save();
        g.translate(x, y);
        g.rotate(r() * Math.PI * 2);
        g.beginPath();
        g.ellipse(0, 0, 4 + r() * 5, 2 + r() * 2.5, 0, 0, Math.PI * 2);
        g.fill();
        g.fillStyle = `hsl(80,10%,${l + 12}%)`;
        g.fillRect(-4, -0.4, 8, 0.8);
        g.restore();
      }
    });
    TEX.needles = canvasTex(256, 256, (g, w, h) => {
      g.clearRect(0, 0, w, h);
      g.fillStyle = 'rgba(96,106,90,0.012)';
      g.fillRect(0, 0, w, h);
      const r = mulberry32(61);
      g.lineCap = 'round';
      for (let i = 0; i < 5200; i++) {
        const x = r() * w, y = r() * h;
        const len = 6 + r() * 14;
        const a = Math.PI / 2 + (r() - 0.5) * 1.3;
        g.strokeStyle = `hsl(${95 + r() * 30},${8 + r() * 14}%,${24 + r() * 40}%)`;
        g.lineWidth = 1 + r() * 1.6;
        g.beginPath();
        g.moveTo(x, y);
        g.lineTo(x + Math.cos(a) * len, y + Math.sin(a) * len);
        g.stroke();
      }
    });
    TEX.bark = canvasTex(64, 128, (g, w, h) => {
      const r = mulberry32(71);
      g.fillStyle = '#6b5846';
      g.fillRect(0, 0, w, h);
      for (let i = 0; i < 260; i++) {
        g.fillStyle = `rgba(${r() < 0.5 ? '30,22,16' : '150,135,118'},${0.2 + r() * 0.4})`;
        g.fillRect(r() * w, r() * h, 1 + r() * 2.5, 6 + r() * 26);
      }
    });
    // soft contact shadow under each car
    TEX.contact = canvasTex(64, 128, (g, w, h) => {
      const img = g.createImageData(w, h);
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
          const u = Math.abs((x + 0.5) / w - 0.5) * 2, v = Math.abs((y + 0.5) / h - 0.5) * 2;
          const d = Math.pow(Math.pow(u, 4) + Math.pow(v, 4), 0.25);
          const o = (y * w + x) * 4;
          img.data[o + 3] = 255 * Math.pow(1 - smoothstep((d - 0.55) / 0.45), 1.6);
        }
      g.putImageData(img, 0, 0);
    });
    TEX.contact.wrapS = TEX.contact.wrapT = THREE.ClampToEdgeWrapping;
    // gentle swell for the sea
    {
      const hs = fbmField(256, 6, 4, 81, 0.5);
      TEX.waves = normalTex(hs, 256, 5);
    }
    TEX.checker = canvasTex(8, 64, (g) => {
      for (let i = 0; i < 2; i++)
        for (let j = 0; j < 16; j++) {
          g.fillStyle = (i + j) % 2 ? '#111' : '#f5f5f5';
          g.fillRect(i * 4, j * 4, 4, 4);
        }
    });
    TEX.checker.magFilter = THREE.NearestFilter;
    TEX.garage = canvasTex(128, 64, (g, w, h) => {
      g.fillStyle = '#d9dbe0';
      g.fillRect(0, 0, w, h);
      g.fillStyle = '#3a3f48';
      g.fillRect(10, 18, w - 20, h - 18);
      g.fillStyle = 'rgba(255,255,255,0.12)';
      for (let y = 22; y < h; y += 6) g.fillRect(10, y, w - 20, 2);
      g.fillStyle = '#c8102e';
      g.fillRect(0, 4, w, 6);
    });
    TEX.fence = canvasTex(64, 64, (g, w, h) => {
      g.clearRect(0, 0, w, h);
      g.strokeStyle = 'rgba(200,205,210,0.95)';
      g.lineWidth = 2;
      for (let k = -w; k < w * 2; k += 12) {
        g.beginPath();
        g.moveTo(k, 0);
        g.lineTo(k + h, h);
        g.moveTo(k + h, 0);
        g.lineTo(k, h);
        g.stroke();
      }
      g.fillStyle = 'rgba(120,125,130,1)';
      g.fillRect(0, 0, w, 3);
    });
    // Mediterranean facade, 4 bays × 4 floors = 12 m × 12 m: stucco, shuttered windows, balconies
    const facade = (lit) =>
      canvasTex(256, 256, (g, w, h) => {
        const r = mulberry32(lit ? 7 : 8);
        const rl = mulberry32(9);
        g.fillStyle = lit ? '#000' : '#f4f1ea';
        g.fillRect(0, 0, w, h);
        if (!lit) {
          for (let i = 0; i < 2500; i++) {
            g.fillStyle = `rgba(${r() < 0.5 ? '0,0,0' : '255,255,255'},${r() * 0.06})`;
            g.fillRect(r() * w, r() * h, 2 + r() * 6, 2 + r() * 6);
          }
        }
        for (let fl = 0; fl < 4; fl++) {
          const y0 = fl * 64;
          if (!lit) {
            g.fillStyle = 'rgba(0,0,0,0.12)';
            g.fillRect(0, y0 + 60, w, 4); // floor cornice shadow
            g.fillStyle = 'rgba(255,255,255,0.35)';
            g.fillRect(0, y0 + 58, w, 2);
          }
          for (let bay = 0; bay < 4; bay++) {
            const x0 = bay * 64 + 20;
            const wy = y0 + 12;
            const on = rl() < 0.5;
            if (lit) {
              if (on) {
                const warm = rl() < 0.75;
                g.fillStyle = warm ? '#ffcf7a' : '#d6e4ff';
                g.fillRect(x0, wy, 24, 36);
                g.fillStyle = 'rgba(0,0,0,0.35)';
                g.fillRect(x0 + 11, wy, 2, 36);
              }
              continue;
            }
            // glass with a sky reflection at the top
            const gr = g.createLinearGradient(0, wy, 0, wy + 36);
            gr.addColorStop(0, '#9fb3c6');
            gr.addColorStop(0.35, '#4a5866');
            gr.addColorStop(1, '#1f262e');
            g.fillStyle = gr;
            g.fillRect(x0, wy, 24, 36);
            g.fillStyle = '#e9e6de';
            g.fillRect(x0 - 2, wy - 2, 28, 2);
            g.fillRect(x0 - 2, wy + 36, 28, 3);
            g.fillRect(x0 + 11, wy, 2, 36);
            // shutters, some closed
            const closed = r() < 0.25;
            g.fillStyle = '#5b7355';
            if (closed) g.fillRect(x0, wy, 24, 36);
            else {
              g.fillRect(x0 - 9, wy, 8, 36);
              g.fillRect(x0 + 25, wy, 8, 36);
            }
            g.fillStyle = 'rgba(0,0,0,0.25)';
            for (let s = 0; s < 36; s += 3) {
              if (closed) g.fillRect(x0, wy + s, 24, 1);
              else {
                g.fillRect(x0 - 9, wy + s, 8, 1);
                g.fillRect(x0 + 25, wy + s, 8, 1);
              }
            }
            // balcony slab and railing on alternate floors
            if (fl % 2 === 1) {
              g.fillStyle = 'rgba(0,0,0,0.3)';
              g.fillRect(x0 - 10, wy + 40, 44, 5);
              g.fillStyle = '#d8d4cc';
              g.fillRect(x0 - 10, wy + 38, 44, 3);
              g.fillStyle = '#2d2d2d';
              g.fillRect(x0 - 10, wy + 22, 44, 2);
              for (let k = 0; k <= 44; k += 4) g.fillRect(x0 - 10 + k, wy + 22, 1, 17);
            }
          }
        }
      });
    TEX.facade = facade(false);
    TEX.facadeLit = facade(true);
    // grandstand: rows of seats with spectators (shirts, heads), some empty seats
    TEX.crowd = canvasTex(512, 128, (g, w, h) => {
      const r = mulberry32(91);
      const shirts = ['#c8323c', '#e8e6df', '#2c4f8c', '#f0c341', '#1f7a5a', '#303030', '#8a2d6b', '#e07b2c', '#6a8fb8', '#444c58'];
      const skin = ['#e9c3a0', '#d7a47c', '#b07a52', '#7a5238', '#f1d2b6'];
      g.fillStyle = '#3b4048';
      g.fillRect(0, 0, w, h);
      const rows = 8;
      const rh = h / rows;
      for (let k = 0; k < rows; k++) {
        const y = k * rh;
        g.fillStyle = '#5a6270';
        g.fillRect(0, y + rh * 0.55, w, rh * 0.3); // seat backs
        g.fillStyle = 'rgba(0,0,0,0.35)';
        g.fillRect(0, y + rh * 0.85, w, rh * 0.15);
        for (let x = 1 + r() * 3; x < w - 4; x += 5 + r() * 2) {
          if (r() < 0.22) continue;
          g.fillStyle = shirts[(r() * shirts.length) | 0];
          g.fillRect(x, y + rh * 0.42, 4, rh * 0.45);
          g.fillStyle = skin[(r() * skin.length) | 0];
          g.fillRect(x + 0.8, y + rh * 0.18, 2.6, rh * 0.26);
          if (r() < 0.15) {
            g.fillStyle = shirts[(r() * shirts.length) | 0]; // cap
            g.fillRect(x + 0.5, y + rh * 0.14, 3.2, rh * 0.1);
          }
        }
      }
    });
    return TEX;
  }

  // Add a shader tweak to a material; several tweaks chain, and survive the CSM hook (see prepareMaterials).
  function patchShader(mat, key, fn) {
    const list = mat.userData.patches || (mat.userData.patches = []);
    list.push({ key, fn });
    mat.onBeforeCompile = (shader) => list.forEach((p) => p.fn(shader));
    mat.customProgramCacheKey = () => list.map((p) => p.key).join('|');
    return mat;
  }
  // Sample the colour map twice at unrelated scales/rotations and modulate by a macro noise: no visible tiling.
  function antiTile(mat, macroScale = 0.031, macroAmt = 0.5) {
    const macro = textures().macro;
    return patchShader(mat, 'antitile', (sh) => {
      sh.uniforms.macroMap = { value: macro };
      sh.fragmentShader = 'uniform sampler2D macroMap;\n' + sh.fragmentShader.replace(
        '#include <map_fragment>',
        `#ifdef USE_MAP
          vec4 tA = texture2D( map, vMapUv );
          vec4 tB = texture2D( map, mat2( 0.8, -0.6, 0.6, 0.8 ) * vMapUv * 0.37 + 0.21 );
          float mc = texture2D( macroMap, vMapUv * ${macroScale.toFixed(4)} ).r;
          vec4 sampledDiffuseColor = mix( tA, tB, 0.45 ) * ( 1.0 + ( mc - 0.5 ) * ${(macroAmt * 2).toFixed(3)} );
          diffuseColor *= sampledDiffuseColor;
        #endif`
      );
    });
  }

  function numberTexture(n) {
    return canvasTex(128, 128, (g) => {
      g.fillStyle = '#ffffff';
      g.beginPath();
      g.arc(64, 64, 60, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#111';
      g.font = 'bold 72px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.fillText(String(n), 64, 70);
    });
  }

  // ---------------- Seicento model ----------------
  // Built from the real car's proportions: 3.32 m long, 1.51 m wide, 1.42 m tall, 2.20 m wheelbase,
  // 0.61 m front and 0.51 m rear overhang. x forward (front bumper ≈ +1.70), y up (ground 0), z to the right.
  // The shell is lofted from cross-sections; glass, lamps, shut lines and trim are drawn by the paint
  // shader from the same coordinates, so they stay crisp at any distance.

  // Smooth curve through [x, y] knots (ascending x), cubic Hermite with finite-difference tangents.
  function curve(knots) {
    const n = knots.length;
    const m = knots.map((k, i) => {
      const a = knots[Math.max(0, i - 1)], b = knots[Math.min(n - 1, i + 1)];
      return (b[1] - a[1]) / (b[0] - a[0]);
    });
    return (x) => {
      if (x <= knots[0][0]) return knots[0][1];
      if (x >= knots[n - 1][0]) return knots[n - 1][1];
      let i = 0;
      while (knots[i + 1][0] < x) i++;
      const [x0, y0] = knots[i], [x1, y1] = knots[i + 1];
      const h = x1 - x0, t = (x - x0) / h, t2 = t * t, t3 = t2 * t;
      return (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m[i + 1];
    };
  }

  const SEI = (() => {
    const W = 0.754;
    // lower body: top edge (bonnet, then the beltline, then the tailgate top) and underside
    const yTop = curve([
      [-1.69, 0.87], [-1.62, 0.93], [-1.5, 0.945], [-1.0, 0.94], [0, 0.925], [0.6, 0.905], [0.85, 0.875],
      [1.0, 0.83], [1.2, 0.765], [1.4, 0.7], [1.52, 0.655], [1.6, 0.61], [1.69, 0.52],
    ]);
    const yBot = curve([[-1.69, 0.3], [-1.55, 0.25], [-1.35, 0.205], [1.25, 0.2], [1.5, 0.24], [1.69, 0.29]]);
    // plan view: full width between the wheels, a rounded nose and a flatter tail
    const plan = (x) => {
      let w = W;
      if (x > 1.2) {
        const u = Math.min(1, (x - 1.2) / 0.48);
        w *= Math.pow(1 - Math.pow(u, 2.4), 1 / 2.4);
      }
      if (x < -1.46) {
        const u = Math.min(1, (-1.46 - x) / 0.22);
        w *= Math.pow(1 - Math.pow(u, 2.6), 1 / 2.6);
      }
      return w;
    };
    const BULGE = 0.022;
    const dims = (x) => {
      const w = plan(x), yb = yBot(x), yt = yTop(x), hgt = yt - yb;
      const wc = Math.max(0.004, w - BULGE * (w / W));
      const rTop = x > 0.9 ? 0.07 + 0.13 * smoothstep((x - 0.9) / 0.7) : 0.065;
      return { w, wc, bulge: w - wc, yb, yt, rt: Math.min(rTop, wc * 0.95, hgt * 0.45), rb: Math.min(0.1, wc * 0.95, hgt * 0.45) };
    };
    // half-width of the lower body at height y
    const sideZ = (x, y) => {
      const d = dims(x);
      if (y <= d.yb + d.rb) {
        const dy = d.yb + d.rb - y;
        return d.wc - d.rb + Math.sqrt(Math.max(0, d.rb * d.rb - dy * dy));
      }
      if (y >= d.yt - d.rt) {
        const dy = y - (d.yt - d.rt);
        return d.wc - d.rt + Math.sqrt(Math.max(0, d.rt * d.rt - dy * dy));
      }
      const s = (y - d.yb - d.rb) / (d.yt - d.rt - d.yb - d.rb);
      return d.wc + d.bulge * (1 - (2 * s - 1) ** 2);
    };
    // right half of a lower-body section, bottom centre -> top centre, as [y, z]; fixed point count
    const halfSection = (x) => {
      const d = dims(x);
      const pts = [];
      const crown = 0.02 * smoothstep((x - 0.8) / 0.2);
      for (let i = 0; i < 3; i++) pts.push([d.yb, ((d.wc - d.rb) * i) / 3]);
      for (let i = 0; i < 5; i++) {
        const a = -Math.PI / 2 + ((Math.PI / 2) * i) / 5;
        pts.push([d.yb + d.rb + Math.sin(a) * d.rb, d.wc - d.rb + Math.cos(a) * d.rb]);
      }
      const y0 = d.yb + d.rb, y1 = d.yt - d.rt;
      for (let i = 0; i < 7; i++) {
        const s = i / 7;
        pts.push([y0 + (y1 - y0) * s, d.wc + d.bulge * (1 - (2 * s - 1) ** 2)]);
      }
      for (let i = 0; i < 7; i++) {
        const a = ((Math.PI / 2) * i) / 7;
        pts.push([y1 + Math.sin(a) * d.rt, d.wc - d.rt + Math.cos(a) * d.rt]);
      }
      const zf = Math.max(1e-3, d.wc - d.rt);
      for (let i = 0; i <= 6; i++) {
        const z = zf * (1 - i / 6);
        pts.push([d.yt + crown * (1 - (z / zf) ** 2), z]);
      }
      return pts;
    };
    // glasshouse: windscreen, roof and near-vertical hatch, sitting just inside the shoulders
    const roof = curve([
      [-1.615, 0.9], [-1.58, 1.02], [-1.5, 1.16], [-1.4, 1.3], [-1.3, 1.38], [-1.2, 1.405], [-0.6, 1.425],
      [0, 1.41], [0.18, 1.385], [0.3, 1.335], [0.4, 1.265], [0.6, 1.1], [0.8, 0.935], [0.88, 0.87], [0.95, 0.82],
    ]);
    const roofW = curve([[-1.615, 0.52], [-1.56, 0.62], [-1.45, 0.675], [-1.2, 0.69], [0.3, 0.69], [0.7, 0.675], [0.95, 0.64]]);
    const G0 = -1.615, G1 = 0.95;
    const gSection = (x) => {
      const base = yTop(x) - 0.035;
      const h = Math.max(0.002, roof(x) - base);
      const a = roofW(x);
      const pts = [];
      const N = 30;
      for (let i = 0; i <= N; i++) {
        const t = (Math.PI * i) / N;
        const c = Math.cos(t), s = Math.sin(t);
        pts.push([base + h * Math.pow(Math.abs(s), 2 / 2.4), a * Math.sign(c) * Math.pow(Math.abs(c), 2 / 3)]);
      }
      return pts;
    };
    return { W, yTop, yBot, plan, sideZ, halfSection, gSection, roof, G0, G1, X0: -1.673, X1: 1.663 };
  })();

  // Loft a list of rings (each an array of [y, z] at station x) into an indexed mesh.
  function loft(stations, closed, capFront, capRear) {
    const pos = [];
    const idx = [];
    const R = stations[0].ring.length;
    for (const st of stations) for (const [y, z] of st.ring) pos.push(st.x, y, z);
    const seg = closed ? R : R - 1;
    for (let k = 0; k < stations.length - 1; k++)
      for (let i = 0; i < seg; i++) {
        const j = (i + 1) % R;
        const a = k * R + i, b = (k + 1) * R + i, c = k * R + j, d = (k + 1) * R + j;
        idx.push(a, b, c, c, b, d);
      }
    const cap = (k, dx, front) => {
      const st = stations[k];
      let cy = 0;
      for (const [y] of st.ring) cy += y / R;
      // own copy of the rim so the cap gets its own (flat) normals
      const r0 = pos.length / 3;
      for (const [y, z] of st.ring) pos.push(st.x, y, z);
      const ci = pos.length / 3;
      pos.push(st.x + dx, cy, 0);
      for (let i = 0; i < R; i++) {
        const j = (i + 1) % R;
        if (front) idx.push(r0 + j, r0 + i, ci);
        else idx.push(r0 + i, r0 + j, ci);
      }
    };
    if (capRear) cap(0, -0.004, false);
    if (capFront) cap(stations.length - 1, 0.004, true);
    return { pos, idx };
  }

  function mergeIndexed(parts) {
    const pos = [];
    const idx = [];
    for (const p of parts) {
      const off = pos.length / 3;
      for (const v of p.pos) pos.push(v);
      for (const i of p.idx) idx.push(i + off);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    g.computeVertexNormals();
    return g;
  }

  // Wraparound plastic bumper: the body's plan outline at bumper height, pushed out, extruded vertically.
  function bumperGeometry(front, y0, y1) {
    const ym = (y0 + y1) / 2;
    const xa = front ? 1.4 : -1.49;
    const xb = front ? SEI.X1 : SEI.X0;
    const tip = xb + (front ? 0.012 : -0.012);
    const outline = [];
    const n = 28;
    for (let i = 0; i <= n; i++) {
      const u = i / n;
      const x = xa + (xb - xa) * (1 - (1 - u) * (1 - u));
      outline.push([x, SEI.sideZ(x, ym)]);
    }
    outline.push([tip, 0]);
    // full loop: right side (z > 0) out to the tip, then back along the left side
    const loop = outline.concat(outline.slice(0, -1).reverse().map(([x, z]) => [x, -z]));
    const offset = (pts, d) =>
      pts.map((p, i) => {
        const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
        let tx = b[0] - a[0], tz = b[1] - a[1];
        const l = Math.hypot(tx, tz) || 1;
        tx /= l;
        tz /= l;
        // outward: away from the car's centre
        let nx = tz, nz = -tx;
        if (nx * (p[0] - (front ? 1.2 : -1.2)) + nz * p[1] < 0) {
          nx = -nx;
          nz = -nz;
        }
        return [p[0] + nx * d, p[1] + nz * d];
      });
    const outer = offset(loop, 0.012);
    const inner = offset(loop, -0.035).reverse();
    const shape = new THREE.Shape();
    shape.moveTo(outer[0][0], outer[0][1]);
    for (const p of outer.slice(1)) shape.lineTo(p[0], p[1]);
    for (const p of inner) shape.lineTo(p[0], p[1]);
    shape.closePath();
    const g = new THREE.ExtrudeGeometry(shape, {
      depth: y1 - y0 - 0.024, curveSegments: 4, bevelEnabled: true, bevelThickness: 0.012, bevelSize: 0.012, bevelSegments: 3,
    });
    // shape (x, z) extruded along +Z -> rotate so the extrusion runs down from y1
    g.rotateX(Math.PI / 2);
    g.translate(0, y1 - 0.012, 0);
    return g;
  }

  // Tyre with rounded shoulders and a slightly bulged sidewall (lathe around the axle, which is z).
  function tyreGeometry() {
    const R = 0.277, w = 0.075, rim = 0.17;
    const pts = [];
    pts.push(new THREE.Vector2(rim, -w + 0.004));
    for (let k = 0; k <= 8; k++) {
      const a = -Math.PI / 2 + (k / 8) * Math.PI;
      pts.push(new THREE.Vector2(R - 0.03 + Math.cos(a) * 0.03, Math.sin(a) * w));
    }
    pts.push(new THREE.Vector2(rim, w - 0.004));
    return new THREE.LatheGeometry(pts, 24).rotateX(Math.PI / 2);
  }

  let carGeo = null;
  function carGeometry() {
    if (carGeo) return carGeo;
    // lower body, denser at the rounded ends
    const lower = [];
    for (let i = 0; i <= 90; i++) {
      const t = i / 90;
      const x = SEI.X0 + (SEI.X1 - SEI.X0) * (0.6 * (0.5 - 0.5 * Math.cos(Math.PI * t)) + 0.4 * t);
      const h = SEI.halfSection(x);
      const ring = h.concat(h.slice(1, -1).reverse().map(([y, z]) => [y, -z]));
      lower.push({ x, ring });
    }
    lower.sort((a, b) => a.x - b.x);
    const glass = [];
    for (let i = 0; i <= 80; i++) {
      const x = SEI.G0 + ((SEI.G1 - SEI.G0) * i) / 80;
      glass.push({ x, ring: SEI.gSection(x) });
    }
    const hubcap = canvasTex(128, 128, (g) => {
      g.clearRect(0, 0, 128, 128);
      g.fillStyle = '#9aa0a6';
      g.beginPath();
      g.arc(64, 64, 63, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#d4d8dc';
      g.beginPath();
      g.arc(64, 64, 56, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#2a2c30';
      for (let k = 0; k < 10; k++) {
        g.save();
        g.translate(64, 64);
        g.rotate((k / 10) * Math.PI * 2);
        g.beginPath();
        g.moveTo(-5, 26);
        g.lineTo(5, 26);
        g.lineTo(8, 50);
        g.lineTo(-8, 50);
        g.closePath();
        g.fill();
        g.restore();
      }
      g.fillStyle = '#b9bec4';
      g.beginPath();
      g.arc(64, 64, 17, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#1f4f9a';
      g.beginPath();
      g.arc(64, 64, 8, 0, Math.PI * 2);
      g.fill();
    });
    carGeo = {
      shell: mergeIndexed([loft(lower, true, true, true), loft(glass, false, false, false)]),
      bumperF: bumperGeometry(true, 0.19, 0.47),
      bumperR: bumperGeometry(false, 0.21, 0.52),
      strip: new THREE.BoxGeometry(1.52, 0.055, 0.014),
      mirror: new THREE.SphereGeometry(1, 14, 10).scale(0.05, 0.062, 0.085),
      mirrorArm: new THREE.BoxGeometry(0.05, 0.03, 0.07),
      handle: new THREE.BoxGeometry(0.13, 0.028, 0.02),
      plate: new THREE.BoxGeometry(0.02, 0.11, 0.42),
      intake: new THREE.BoxGeometry(0.02, 0.06, 0.62),
      antenna: new THREE.CylinderGeometry(0.004, 0.006, 0.42, 5).translate(0, 0.21, 0).rotateZ(0.45),
      tyre: tyreGeometry(),
      rim: new THREE.CylinderGeometry(0.175, 0.175, 0.12, 20).rotateX(Math.PI / 2),
      cap: new THREE.CircleGeometry(0.168, 24),
      hubcap,
      arch: new THREE.CylinderGeometry(0.35, 0.35, 1.3, 14, 1, true, -Math.PI / 2, Math.PI).rotateX(-Math.PI / 2),
      archWall: new THREE.CircleGeometry(0.345, 20),
      exhaust: new THREE.CylinderGeometry(0.03, 0.03, 0.14, 8).rotateZ(Math.PI / 2),
      decal: new THREE.PlaneGeometry(0.36, 0.36),
      contact: new THREE.PlaneGeometry(4.1, 2.05).rotateX(-Math.PI / 2),
    };
    return carGeo;
  }

  const shared = {};
  function sharedMats() {
    if (shared.trim) return shared;
    shared.trim = new THREE.MeshStandardMaterial({ color: 0x1b1c1e, roughness: 0.7, map: textures().macro });
    shared.liner = new THREE.MeshStandardMaterial({ color: 0x0b0b0b, roughness: 0.9, side: THREE.DoubleSide });
    shared.tyre = new THREE.MeshStandardMaterial({ color: 0x1a1a1a, roughness: 0.88, side: THREE.DoubleSide });
    shared.rim = new THREE.MeshStandardMaterial({ color: 0x3a3d42, roughness: 0.5, metalness: 0.6 });
    shared.cap = new THREE.MeshStandardMaterial({ map: carGeometry().hubcap, roughness: 0.35, metalness: 0.55, transparent: true, alphaTest: 0.5 });
    shared.plate = new THREE.MeshStandardMaterial({ color: 0xf6f3e8, roughness: 0.5 });
    shared.headU = { value: 0 };
    shared.contact = new THREE.MeshBasicMaterial({
      color: 0x000000, alphaMap: textures().contact, transparent: true, opacity: 0.72, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -8, polygonOffsetUnits: -8,
    });
    return shared;
  }

  // Everything painted onto the shell: glass and seals, B-pillar, lamps, grille, badge, wipers, shut lines,
  // fuel flap, optional stripes, and the wheel-arch openings.
  const LIVERY_GLSL = `
    varying vec3 vObj;
    varying vec3 vObjN;
    uniform float uHead, uTail, uStripes;
    float sdQuad( vec2 p, vec2 v0, vec2 v1, vec2 v2, vec2 v3 ) {
      vec2 v[ 4 ];
      v[ 0 ] = v0; v[ 1 ] = v1; v[ 2 ] = v2; v[ 3 ] = v3;
      float d = dot( p - v[ 0 ], p - v[ 0 ] );
      float s = 1.0;
      for ( int i = 0; i < 4; i ++ ) {
        int j = i == 0 ? 3 : i - 1;
        vec2 e = v[ j ] - v[ i ];
        vec2 w = p - v[ i ];
        vec2 b = w - e * clamp( dot( w, e ) / dot( e, e ), 0.0, 1.0 );
        d = min( d, dot( b, b ) );
        bvec3 c = bvec3( p.y >= v[ i ].y, p.y < v[ j ].y, e.x * w.y > e.y * w.x );
        if ( all( c ) || all( not( c ) ) ) s = -s;
      }
      return s * sqrt( d );
    }
    float sdRBox( vec2 p, vec2 c, vec2 h, float r ) {
      vec2 q = abs( p - c ) - h + r;
      return length( max( q, 0.0 ) ) + min( max( q.x, q.y ), 0.0 ) - r;
    }
    float sdSeg( vec2 p, vec2 a, vec2 b ) {
      vec2 pa = p - a, ba = b - a;
      return length( pa - ba * clamp( dot( pa, ba ) / dot( ba, ba ), 0.0, 1.0 ) );
    }
    float sdCaps( vec2 p, vec2 a, vec2 b, float ra, float rb ) {
      vec2 pa = p - a, ba = b - a;
      float h = clamp( dot( pa, ba ) / dot( ba, ba ), 0.0, 1.0 );
      return length( pa - ba * h ) - mix( ra, rb, h );
    }
    float fillS( float d ) { float aa = fwidth( d ) * 0.8 + 1e-5; return 1.0 - smoothstep( -aa, aa, d ); }
    float lineS( float d, float w ) { float aa = fwidth( d ) * 0.8 + 1e-5; return 1.0 - smoothstep( w - aa, w + aa, d ); }
  `;
  const LIVERY_MAIN = `
    vec3 P = vObj;
    vec3 N = normalize( vObjN );
    float az = abs( P.z );
    if ( az > 0.3 && ( length( P.xy - vec2( 1.05, 0.28 ) ) < 0.34 || length( P.xy - vec2( -1.15, 0.28 ) ) < 0.34 ) ) discard;
    float sideM = smoothstep( 0.45, 0.62, abs( N.z ) );
    float topM = smoothstep( 0.5, 0.7, N.y );
    // glass: door and rear quarter windows, windscreen, hatch
    float dDoor = sdQuad( P.xy, vec2( -0.33, 0.965 ), vec2( 0.67, 0.965 ), vec2( 0.35, 1.245 ), vec2( -0.33, 1.265 ) ) - 0.025;
    float dQtr = sdQuad( P.xy, vec2( -1.33, 0.975 ), vec2( -0.5, 0.965 ), vec2( -0.5, 1.265 ), vec2( -1.14, 1.255 ) ) - 0.025;
    float dSideG = min( dDoor, dQtr );
    float wsM = smoothstep( 0.12, 0.28, N.x ) * smoothstep( 0.2, 0.35, N.y );
    float dWs = sdQuad( P.xz, vec2( 0.36, -0.44 ), vec2( 0.8, -0.53 ), vec2( 0.8, 0.53 ), vec2( 0.36, 0.44 ) ) - 0.045;
    float backM = smoothstep( 0.25, 0.4, -N.x ) * step( 0.95, P.y );
    float dRw = sdRBox( vec2( P.z, P.y ), vec2( 0.0, 1.17 ), vec2( 0.49, 0.165 ), 0.07 );
    float glass = max( fillS( dSideG ) * sideM, max( fillS( dWs ) * wsM, fillS( dRw ) * backM ) );
    float seal = max( fillS( dSideG - 0.014 ) * sideM, max( fillS( dWs - 0.016 ) * wsM, fillS( dRw - 0.014 ) * backM ) ) * ( 1.0 - glass );
    float bPillar = fillS( sdRBox( P.xy, vec2( -0.415, 1.115 ), vec2( 0.05, 0.175 ), 0.01 ) ) * sideM;
    // wipers parked along the base of the windscreen, and the rear wiper
    float wipers = lineS( min( sdSeg( P.xz, vec2( 0.785, -0.5 ), vec2( 0.73, -0.02 ) ), sdSeg( P.xz, vec2( 0.785, 0.04 ), vec2( 0.73, 0.5 ) ) ), 0.009 ) * wsM;
    wipers = max( wipers, lineS( sdSeg( vec2( P.z, P.y ), vec2( 0.0, 1.02 ), vec2( -0.34, 1.2 ) ), 0.008 ) * backM );
    // nose: teardrop headlights with the amber indicator at the outer end, slot grille, badge
    float noseM = smoothstep( 1.26, 1.3, P.x ) * ( 1.0 - smoothstep( 0.9, 0.98, N.y ) );
    vec2 fp = vec2( az, P.y );
    float dHead = sdCaps( fp, vec2( 0.3, 0.6 ), vec2( 0.575, 0.642 ), 0.042, 0.07 );
    float head = fillS( dHead ) * noseM;
    float headRim = lineS( abs( dHead ), 0.006 ) * noseM;
    float indic = smoothstep( 0.595, 0.605, az ) * head;
    float bulb = fillS( length( fp - vec2( 0.49, 0.628 ) ) - 0.04 ) * head * ( 1.0 - indic );
    float frontM = smoothstep( 1.45, 1.5, P.x );
    float dGr = sdRBox( vec2( P.z, P.y ), vec2( 0.0, 0.575 ), vec2( 0.2, 0.024 ), 0.022 );
    float grille = fillS( dGr ) * frontM;
    float badge = fillS( length( vec2( P.z, P.y ) - vec2( 0.0, 0.648 ) ) - 0.03 ) * frontM * step( 0.1, N.x );
    // tall tail lights wrapping round the rear corners: red / amber / reversing white / red
    float rearM = 1.0 - smoothstep( -1.44, -1.4, P.x );
    float dTail = sdRBox( fp, vec2( 0.64, 0.74 ), vec2( 0.12, 0.17 ), 0.05 );
    float tail = fillS( dTail ) * rearM * step( 0.0, -N.x + 0.35 );
    float tAmber = tail * step( 0.74, P.y ) * step( P.y, 0.83 );
    float tWhite = tail * step( 0.66, P.y ) * step( P.y, 0.74 );
    float tRed = tail - tAmber - tWhite;
    float tailRim = lineS( abs( dTail ), 0.005 ) * rearM;
    // shut lines: door, bonnet edges, tailgate, fuel flap (right-hand side)
    float lines = 0.0;
    lines = max( lines, lineS( min( min( sdSeg( P.xy, vec2( 0.7, 0.3 ), vec2( 0.69, 0.94 ) ), sdSeg( P.xy, vec2( -0.4, 0.26 ), vec2( -0.4, 0.94 ) ) ),
      sdSeg( P.xy, vec2( -0.4, 0.26 ), vec2( 0.7, 0.3 ) ) ), 0.0022 ) * sideM );
    lines = max( lines, lineS( sdSeg( vec2( P.x, az ), vec2( 0.9, 0.6 ), vec2( 1.42, 0.55 ) ), 0.0022 ) * topM );
    lines = max( lines, lineS( sdSeg( fp, vec2( 0.6, 0.53 ), vec2( 0.61, 0.95 ) ), 0.0022 ) * smoothstep( 0.4, 0.6, -N.x ) );
    lines = max( lines, lineS( abs( length( P.xy - vec2( -1.02, 0.745 ) ) - 0.055 ), 0.0022 ) * sideM * step( 0.0, P.z ) );
    float stripe = fillS( abs( az - 0.12 ) - 0.05 ) * topM * uStripes * step( -1.3, P.x );
    float trimA = max( max( seal, bPillar ), max( max( wipers, grille ), max( headRim, tailRim ) ) );
    vec3 col = diffuseColor.rgb;
    col = mix( col, vec3( 0.86 ), stripe );
    col *= 1.0 - 0.75 * lines;
    col = mix( col, vec3( 0.016 ), trimA );
    col = mix( col, vec3( 0.008, 0.011, 0.014 ), glass );
    vec3 lens = mix( vec3( 0.7, 0.72, 0.74 ), vec3( 1.0, 0.36, 0.02 ), indic / max( head, 1e-3 ) );
    col = mix( col, lens, head * ( 1.0 - headRim ) );
    col = mix( col, vec3( 0.95 ), bulb );
    vec3 tcol = vec3( 0.42, 0.015, 0.015 ) * tRed + vec3( 0.9, 0.35, 0.02 ) * tAmber + vec3( 0.75, 0.75, 0.73 ) * tWhite;
    col = mix( col, tcol / max( tail, 1e-3 ), tail * ( 1.0 - tailRim ) );
    col = mix( col, mix( vec3( 0.03, 0.12, 0.38 ), vec3( 0.8 ), lineS( abs( length( vec2( P.z, P.y ) - vec2( 0.0, 0.648 ) ) - 0.027 ), 0.004 ) ), badge );
    diffuseColor.rgb = col;
    float lensA = max( glass, max( head, tail ) );
  `;

  function buildCar(car) {
    const g = carGeometry();
    const m = sharedMats();
    const paint = new THREE.MeshPhysicalMaterial({ color: car.color, roughness: 0.35, metalness: 0.05, clearcoat: 1, clearcoatRoughness: 0.06, envMapIntensity: 1.3 });
    const tailU = { value: 0.25 };
    patchShader(paint, 'seicento', (sh) => {
      sh.uniforms.uHead = shared.headU;
      sh.uniforms.uTail = tailU;
      sh.uniforms.uStripes = { value: car.stripes ? 1 : 0 };
      sh.vertexShader = 'varying vec3 vObj;\nvarying vec3 vObjN;\n' + sh.vertexShader.replace(
        '#include <begin_vertex>',
        '#include <begin_vertex>\n vObj = position; vObjN = objectNormal;'
      );
      sh.fragmentShader = LIVERY_GLSL + sh.fragmentShader
        .replace('#include <color_fragment>', '#include <color_fragment>\n' + LIVERY_MAIN)
        .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
          roughnessFactor = mix( roughnessFactor, 0.62, trimA );
          roughnessFactor = mix( roughnessFactor, 0.04, lensA );`)
        .replace('#include <metalnessmap_fragment>', `#include <metalnessmap_fragment>
          metalnessFactor = mix( metalnessFactor, 0.85, head * ( 1.0 - indic ) );`)
        .replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
          material.clearcoat *= 1.0 - trimA;`)
        .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
          totalEmissiveRadiance += vec3( 1.0, 0.93, 0.8 ) * uHead * ( head - indic ) * ( 0.35 + bulb )
            + vec3( 1.0, 0.04, 0.02 ) * uTail * tRed;`);
    });
    const root = new THREE.Group();
    root.rotation.order = 'YZX';
    const body = new THREE.Group();
    root.add(body);
    const add = (geo, mat, x, y, z, parent = body, shadow = true) => {
      const mesh = new THREE.Mesh(geo, mat);
      mesh.position.set(x, y, z);
      mesh.castShadow = shadow;
      parent.add(mesh);
      return mesh;
    };
    add(g.shell, paint, 0, 0, 0);
    add(g.bumperF, m.trim, 0, 0, 0);
    add(g.bumperR, m.trim, 0, 0, 0);
    add(g.intake, m.liner, 1.705, 0.255, 0, body, false);
    add(g.plate, m.plate, 1.714, 0.37, 0, body, false);
    add(g.plate, m.plate, -1.714, 0.39, 0, body, false);
    add(g.exhaust, m.liner, -1.72, 0.22, -0.42, body, false);
    for (const side of [-1, 1]) {
      add(g.strip, m.trim, -0.05, 0.47, side * (SEI.sideZ(-0.05, 0.47) + 0.004), body, false);
      add(g.handle, m.trim, -0.27, 0.815, side * (SEI.sideZ(-0.27, 0.815) + 0.006), body, false);
      const mz = side * (SEI.sideZ(0.64, 0.9) + 0.02);
      add(g.mirrorArm, m.trim, 0.64, 0.975, mz, body, false);
      add(g.mirror, m.trim, 0.62, 1.0, mz + side * 0.07);
      const wall = add(g.archWall, m.liner, 0, 0.28, side * 0.47, body, false);
      wall.position.x = 1.05;
      add(g.archWall, m.liner, -1.15, 0.28, side * 0.47, body, false);
    }
    for (const x of [1.05, -1.15]) add(g.arch, m.liner, x, 0.28, 0, body, false);
    add(g.antenna, m.liner, 0.15, SEI.roof(0.15) - 0.01, -0.35, body, false);
    const num = new THREE.MeshBasicMaterial({ map: numberTexture(car.number), transparent: true });
    const zDoor = SEI.sideZ(0.18, 0.66) + 0.012;
    add(g.decal, num, 0.18, 0.66, zDoor, body, false);
    add(g.decal, num, 0.18, 0.66, -zDoor, body, false).rotation.y = Math.PI;
    const d3 = add(g.decal, num, -0.5, SEI.roof(-0.5) + 0.006, 0, body, false);
    d3.rotation.x = -Math.PI / 2;
    d3.rotation.z = Math.PI / 2;
    const contact = new THREE.Mesh(g.contact, m.contact);
    contact.position.set(-0.05, 0.02, 0);
    contact.renderOrder = 1;
    root.add(contact);
    const wheels = [];
    const steer = [];
    for (const [x, front] of [[1.05, true], [-1.15, false]]) {
      for (const side of [-1, 1]) {
        const pivot = new THREE.Group();
        pivot.position.set(x, 0.277, side * 0.64);
        root.add(pivot);
        const wheel = new THREE.Group();
        pivot.add(wheel);
        add(g.tyre, m.tyre, 0, 0, 0, wheel);
        add(g.rim, m.rim, 0, 0, 0, wheel, false);
        const cap = add(g.cap, m.cap, 0, 0, side * 0.066, wheel, false);
        if (side < 0) cap.rotation.y = Math.PI;
        wheels.push(wheel);
        if (front) steer.push(pivot);
      }
    }
    return { root, body, wheels, steer, tailU, paint, spin: 0, pitch: 0, roll: 0 };
  }

  // ---------------- world (terrain, road, scenery) ----------------
  // ground colours per scenery theme: [base, dark patches, dry patches], far plane
  const THEMES = {
    forest: { ground: ['#526d36', '#34502a', '#8b8650'], plane: 0x3c5a2c, earth: '#6b5d47' },
    city: { ground: ['#8f8b82', '#77736c', '#a39d8e'], plane: 0x6d6a64, earth: '#857b6a' },
    oval: { ground: ['#56803a', '#476d30', '#8a9352'], plane: 0x4a6c32, earth: '#6f624b' },
  };

  class TrackWorld {
    constructor(track) {
      this.track = track;
      this.base = track.hMin - 5;
      this.group = new THREE.Group();
      this.buildHash();
      this.materials();
      this.buildTerrain();
      this.buildRoad();
      this.buildPits();
      this.buildTrees();
      if (track.cfg.theme === 'city') this.buildCity();
      if (track.cfg.sea) this.buildSea();
      this.buildTunnels();
    }

    trackY(s) {
      return this.track.sample(this.track.H, s) - this.base;
    }

    buildHash() {
      const tr = this.track;
      this.cell = 40;
      this.hash = new Map();
      for (let i = 0; i < tr.n; i++) {
        const k = Math.floor(tr.X[i] / this.cell) + ',' + Math.floor(tr.Y[i] / this.cell);
        if (!this.hash.has(k)) this.hash.set(k, []);
        this.hash.get(k).push(i);
      }
    }

    nearest(x, y, reach = 4) {
      const tr = this.track;
      const cx = Math.floor(x / this.cell);
      const cy = Math.floor(y / this.cell);
      let best = Infinity;
      let bi = -1;
      for (let a = -reach; a <= reach; a++)
        for (let b = -reach; b <= reach; b++) {
          const l = this.hash.get(cx + a + ',' + (cy + b));
          if (!l) continue;
          for (const i of l) {
            const d = (tr.X[i] - x) ** 2 + (tr.Y[i] - y) ** 2;
            if (d < best) {
              best = d;
              bi = i;
            }
          }
        }
      return bi < 0 ? null : { i: bi, dist: Math.sqrt(best) };
    }

    dem(x, y) {
      const g = this.track.grid;
      if (!g) return this.track.hMin;
      const fx = Math.min(g.nx - 1.001, Math.max(0, (x - g.x0) / g.step));
      const fy = Math.min(g.ny - 1.001, Math.max(0, (y - g.y0) / g.step));
      const i = Math.floor(fx);
      const j = Math.floor(fy);
      const u = fx - i;
      const v = fy - j;
      const h = (a, b) => g.h[b * g.nx + a];
      return h(i, j) * (1 - u) * (1 - v) + h(i + 1, j) * u * (1 - v) + h(i, j + 1) * (1 - u) * v + h(i + 1, j + 1) * u * v;
    }

    // Visible ground height: DEM, pulled down to meet the road near the track.
    groundY(x, y, near) {
      const tr = this.track;
      const dem = this.dem(x, y) - this.base;
      const n = near === undefined ? this.nearest(x, y) : near;
      if (!n || n.dist > this.band) return dem - 1;
      const th = tr.H[n.i] - this.base;
      const r0 = tr.half + tr.cfg.runoff + 3;
      const t = smoothstep((n.dist - r0) / 70);
      let h = th - 0.35 + (dem - th + 0.35) * t;
      h = Math.min(h, th - 0.35 + Math.max(0, n.dist - r0) * 0.45);
      return h;
    }

    // Height of the rendered fine terrain mesh at (x, y), or null outside it (matches the triangle split).
    terrainAt(x, y) {
      const g = this.fineGrid;
      const fx = (x - g.x0) / g.fine;
      const fy = (y - g.y0) / g.fine;
      const i = Math.floor(fx), j = Math.floor(fy);
      const u = fx - i, v = fy - j;
      const h = (a, b) => {
        const k = g.vmap[(j + b) * (g.nx + 1) + i + a];
        return k < 0 ? NaN : g.pos[k * 3 + 1];
      };
      const h00 = h(0, 0), h10 = h(1, 0), h01 = h(0, 1), h11 = h(1, 1);
      const r = u + v <= 1 ? h00 + (h10 - h00) * u + (h01 - h00) * v : h11 + (h01 - h11) * (1 - u) + (h10 - h11) * (1 - v);
      return isNaN(r) ? null : r;
    }

    materials() {
      const t = textures();
      const tr = this.track;
      const nrm = (x, y = x) => new THREE.Vector2(x, y);
      this.mat = {
        asphalt: new THREE.MeshStandardMaterial({
          map: t.asphalt, normalMap: t.asphaltN, normalScale: nrm(0.9), roughnessMap: t.asphaltR, roughness: 0.92, vertexColors: true,
          polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
        }),
        line: new THREE.MeshStandardMaterial({ color: 0xeeeeea, roughness: 0.62, normalMap: t.asphaltN, normalScale: nrm(0.5), polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }),
        kerb: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.55, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }),
        runoff: new THREE.MeshStandardMaterial(Object.assign(
          { roughness: 1, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 },
          {
            gravel: { map: t.gravel, normalMap: t.gravelN, normalScale: nrm(1.2) },
            grass: { map: t.grass, normalMap: t.grassN, color: 0x5f8143 },
            asphalt: { map: t.asphalt, normalMap: t.asphaltN, color: 0x9a9a98, roughness: 0.95 },
          }[tr.cfg.runoffSurface]
        )),
        fence: new THREE.MeshStandardMaterial({ map: t.fence, transparent: true, alphaTest: 0.3, side: THREE.DoubleSide, roughness: 0.6, metalness: 0.5 }),
        armco: new THREE.MeshStandardMaterial({ color: 0xc3c8cf, roughness: 0.3, metalness: 0.85, side: THREE.DoubleSide }),
        concrete: new THREE.MeshStandardMaterial({ color: 0xc9c5bb, roughness: 0.9, side: THREE.DoubleSide }),
        tyrewall: new THREE.MeshStandardMaterial({ color: 0x222222, roughness: 0.9, side: THREE.DoubleSide }),
        terrain: antiTile(new THREE.MeshStandardMaterial({ map: t.grass, normalMap: t.grassN, normalScale: nrm(0.8), vertexColors: true, roughness: 1 })),
        pitlane: new THREE.MeshStandardMaterial({ map: t.asphalt, normalMap: t.asphaltN, roughnessMap: t.asphaltR, color: 0xb0b0b0, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 }),
        racing: new THREE.MeshBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.55, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -6 }),
      };
      if (tr.cfg.runoffSurface !== 'asphalt') antiTile(this.mat.runoff, 0.05, 0.35);
    }

    // Road surface split into lateral columns so the colour can vary across it: dark rubber on the racing
    // line, dust at the edges, the odd resurfaced patch.
    surface(p0, p1, half, mat, uLen) {
      const tr = this.track;
      const cols = [-1, -0.93, -0.8, -0.6, -0.4, -0.2, 0, 0.2, 0.4, 0.6, 0.8, 0.93, 1];
      const nc = cols.length;
      const pos = [];
      const uv = [];
      const col = [];
      const idx = [];
      const count = Math.max(1, Math.round((p1 - p0) / tr.step));
      for (let k = 0; k <= count; k++) {
        const p = k === count ? p0 : p0 + ((p1 - p0) * k) / count;
        const y = this.trackY(p) + 0.03;
        const j = Math.round(tr.wrap(p) / tr.step) % tr.n;
        const rl = tr.RLD[j];
        const patch = noise2(p / 55, 3.7) > 0.72 ? 0.84 : 1;
        const streak = 0.9 + 0.2 * noise2(p / 9, 1.3);
        for (const f of cols) {
          const d = f * half;
          const a = tr.pos(p, d);
          pos.push(a.x, y, a.y);
          uv.push((p0 + ((p1 - p0) * k) / count) / uLen, (d + half) / uLen);
          const rub = Math.exp(-(((d - rl) / 1.25) ** 2)) * streak;
          const edge = smoothstep((Math.abs(d) - half + 1.4) / 1.2);
          const v = patch * (1 - 0.3 * rub) * (1 + 0.14 * edge);
          col.push(v, v, v * (1 + 0.02 * edge));
        }
        if (k < count) {
          const q = k * nc;
          for (let c = 0; c < nc - 1; c++) idx.push(q + c, q + c + 1, q + nc + c, q + c + 1, q + nc + c + 1, q + nc + c);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const mesh = new THREE.Mesh(geo, mat);
      mesh.receiveShadow = true;
      this.group.add(mesh);
      return mesh;
    }

    // Strip along the track between relative distances p0..p1; dFn(p) -> [d0, d1]; yFn(p) -> height offset.
    ribbon(p0, p1, dFn, yOff, mat, uLen = 10, vLen = null, closed = false) {
      const tr = this.track;
      const pos = [];
      const uv = [];
      const idx = [];
      const count = Math.max(1, Math.round((p1 - p0) / tr.step));
      for (let k = 0; k <= count; k++) {
        const p = closed && k === count ? p0 : p0 + ((p1 - p0) * k) / count;
        const [d0, d1] = dFn(p);
        const y = this.trackY(p) + yOff;
        const a = tr.pos(p, d0);
        const b = tr.pos(p, d1);
        pos.push(a.x, y, a.y, b.x, y, b.y);
        const u = (p0 + ((p1 - p0) * k) / count) / uLen;
        uv.push(u, 0, u, vLen ? Math.abs(d1 - d0) / vLen : 1);
        if (k < count) {
          const q = k * 2;
          idx.push(q, q + 1, q + 2, q + 1, q + 3, q + 2);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const mesh = new THREE.Mesh(geo, mat);
      mesh.receiveShadow = true;
      this.group.add(mesh);
      return mesh;
    }

    // Vertical strip (barriers, walls) at lateral offset d(p).
    wall(p0, p1, dFn, y0, y1, mat, uLen = 10) {
      const tr = this.track;
      const pos = [];
      const uv = [];
      const idx = [];
      const count = Math.max(1, Math.round((p1 - p0) / tr.step));
      for (let k = 0; k <= count; k++) {
        const p = p0 + ((p1 - p0) * k) / count;
        const a = tr.pos(p, dFn(p));
        const y = this.trackY(p);
        pos.push(a.x, y + y0, a.y, a.x, y + y1, a.y);
        uv.push(p / uLen, 0, p / uLen, 1);
        if (k < count) {
          const q = k * 2;
          idx.push(q, q + 2, q + 1, q + 1, q + 2, q + 3);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const mesh = new THREE.Mesh(geo, mat);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      this.group.add(mesh);
      return mesh;
    }

    buildTerrain() {
      const tr = this.track;
      const fine = tr.cfg.terrainFine;
      const theme = THEMES[tr.cfg.theme];
      this.band = 175;
      const b = tr.bounds;
      const m = this.band + fine * 2;
      const x0 = b.minX - m;
      const y0 = b.minY - m;
      const nx = Math.ceil((b.maxX - b.minX + 2 * m) / fine);
      const ny = Math.ceil((b.maxY - b.minY + 2 * m) / fine);
      // nearest centreline sample for every grid vertex inside the band ("splat" outwards from the track)
      const W = nx + 1;
      const bestD = new Float32Array(W * (ny + 1)).fill(1e9);
      const bestI = new Int32Array(W * (ny + 1)).fill(-1);
      // highest the ground may be at each vertex so it stays under every nearby piece of road
      const cap = new Float32Array(W * (ny + 1)).fill(1e9);
      const r0 = tr.half + tr.cfg.runoff + 3;
      const rc = Math.ceil(this.band / fine) + 1;
      for (let i = 0; i < tr.n; i++) {
        const tx = tr.X[i], ty = tr.Y[i];
        const cx = Math.round((tx - x0) / fine);
        const cy = Math.round((ty - y0) / fine);
        for (let a = -rc; a <= rc; a++) {
          const yy = cy + a;
          if (yy < 0 || yy > ny) continue;
          const dyv = y0 + yy * fine - ty;
          const w = Math.floor(Math.sqrt(rc * rc - a * a));
          for (let bb = -w; bb <= w; bb++) {
            const xx = cx + bb;
            if (xx < 0 || xx > nx) continue;
            const dxv = x0 + xx * fine - tx;
            const d2 = dxv * dxv + dyv * dyv;
            const k = yy * W + xx;
            const dist = Math.sqrt(d2);
            const lim = tr.H[i] - this.base - 0.35 + Math.max(0, dist - r0) * 0.45;
            if (lim < cap[k]) cap[k] = lim;
            if (d2 < bestD[k]) {
              bestD[k] = d2;
              bestI[k] = i;
            }
          }
        }
      }
      const band2 = this.band * this.band;
      const mark = new Uint8Array(nx * ny);
      for (let j = 0; j < ny; j++)
        for (let i = 0; i < nx; i++)
          if (bestD[j * W + i] < band2 || bestD[j * W + i + 1] < band2 || bestD[(j + 1) * W + i] < band2 || bestD[(j + 1) * W + i + 1] < band2)
            mark[j * nx + i] = 1;
      const vmap = new Int32Array((nx + 1) * (ny + 1)).fill(-1);
      const pos = [];
      const col = [];
      const uv = [];
      const idx = [];
      const c = new THREE.Color();
      const grass = new THREE.Color(theme.ground[0]);
      const dark = new THREE.Color(theme.ground[1]);
      const dry = new THREE.Color(theme.ground[2]);
      const vert = (i, j) => {
        const k = j * (nx + 1) + i;
        if (vmap[k] >= 0) return vmap[k];
        const x = x0 + i * fine;
        const y = y0 + j * fine;
        const h = Math.min(cap[k], this.groundY(x, y, bestI[k] >= 0 && bestD[k] < band2 ? { i: bestI[k], dist: Math.sqrt(bestD[k]) } : null));
        vmap[k] = pos.length / 3;
        pos.push(x, h, y);
        const n1 = noise2(x / 90, y / 90);
        const n2 = noise2(x / 23 + 7, y / 23 + 3);
        const n3 = noise2(x / 7 + 2, y / 7 + 9);
        c.copy(grass).lerp(dark, n1 * 0.95).lerp(dry, Math.max(0, n2 - 0.5) * 1.4).multiplyScalar(0.86 + 0.28 * n3);
        col.push(c.r, c.g, c.b);
        uv.push(x / 9, y / 9);
        return vmap[k];
      };
      for (let j = 0; j < ny; j++)
        for (let i = 0; i < nx; i++) {
          if (!mark[j * nx + i]) continue;
          const a = vert(i, j), bq = vert(i + 1, j), cq = vert(i, j + 1), d = vert(i + 1, j + 1);
          idx.push(a, cq, bq, bq, cq, d);
        }
      this.fineGrid = { x0, y0, fine, nx, ny, vmap, pos };
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      shadeSlopes(geo, theme);
      const mesh = new THREE.Mesh(geo, this.mat.terrain);
      mesh.receiveShadow = true;
      this.group.add(mesh);

      // coarse DEM terrain for the distance, tucked under the detailed band
      const g = tr.grid;
      if (g) {
        const cp = [];
        const cc = [];
        const cu = [];
        const ci = [];
        for (let j = 0; j < g.ny; j++)
          for (let i = 0; i < g.nx; i++) {
            const x = g.x0 + i * g.step;
            const y = g.y0 + j * g.step;
            const n = this.nearest(x, y, 5);
            let h = g.h[j * g.nx + i] - this.base - 1.2;
            if (n && n.dist < this.band - g.step * 1.5) h -= 40;
            cp.push(x, h, y);
            const n1 = noise2(x / 90, y / 90);
            c.copy(grass).lerp(dark, n1 * 0.95).lerp(dry, Math.max(0, noise2(x / 23 + 7, y / 23 + 3) - 0.5) * 1.4);
            cc.push(c.r, c.g, c.b);
            cu.push(x / 9, y / 9);
            if (i < g.nx - 1 && j < g.ny - 1) {
              const a = j * g.nx + i;
              ci.push(a, a + g.nx, a + 1, a + 1, a + g.nx, a + g.nx + 1);
            }
          }
        const cg = new THREE.BufferGeometry();
        cg.setAttribute('position', new THREE.Float32BufferAttribute(cp, 3));
        cg.setAttribute('color', new THREE.Float32BufferAttribute(cc, 3));
        cg.setAttribute('uv', new THREE.Float32BufferAttribute(cu, 2));
        cg.setIndex(ci);
        cg.computeVertexNormals();
        shadeSlopes(cg, theme);
        const cm = new THREE.Mesh(cg, this.mat.terrain);
        cm.receiveShadow = true;
        this.group.add(cm);
        // endless ground beyond the DEM tile
        const minH = Math.min(...g.h) - this.base - 25;
        const plane = new THREE.Mesh(new THREE.PlaneGeometry(40000, 40000).rotateX(-Math.PI / 2), new THREE.MeshStandardMaterial({ color: theme.plane, roughness: 1 }));
        plane.position.set((b.minX + b.maxX) / 2, minH, (b.minY + b.maxY) / 2);
        this.group.add(plane);
      }
    }

    buildRoad() {
      const tr = this.track;
      const L = tr.L;
      const half = tr.half;
      const cfg = tr.cfg;
      const ro = cfg.runoff;
      this.ribbon(0, L, (p) => [tr.clampD(p, -(half + ro)), tr.clampD(p, half + ro)], 0.0, this.mat.runoff, 6, 6, true);
      this.surface(0, L, half, this.mat.asphalt, 5);
      this.ribbon(0, L, () => [half - 0.45, half - 0.15], 0.05, this.mat.line, 10, null, true);
      this.ribbon(0, L, () => [-half + 0.15, -half + 0.45], 0.05, this.mat.line, 10, null, true);

      // kerbs on the inside of corners: individual quads so colours alternate
      const kp = [];
      const kc = [];
      const red = new THREE.Color('#d42a2a');
      const white = new THREE.Color('#f4f4f4');
      for (let i = 0; i < tr.n; i++) {
        const k = tr.KC[i];
        if (Math.abs(k) < 1 / 170) continue;
        const sd = Math.sign(k);
        const s0 = i * tr.step;
        const s1 = s0 + tr.step;
        const y0 = this.trackY(s0) + 0.07;
        const y1 = this.trackY(s1) + 0.07;
        const a0 = tr.pos(s0, sd * (half - 0.9)), a1 = tr.pos(s1, sd * (half - 0.9));
        const b0 = tr.pos(s0, sd * (half + 0.4)), b1 = tr.pos(s1, sd * (half + 0.4));
        const quad = [[a0, y0], [b0, y0 + 0.04], [a1, y1], [b0, y0 + 0.04], [b1, y1 + 0.04], [a1, y1]];
        const winding = sd > 0 ? quad : [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]];
        const cc = i % 2 ? red : white;
        for (const [p, y] of winding) {
          kp.push(p.x, y, p.y);
          kc.push(cc.r, cc.g, cc.b);
        }
      }
      const kg = new THREE.BufferGeometry();
      kg.setAttribute('position', new THREE.Float32BufferAttribute(kp, 3));
      kg.setAttribute('color', new THREE.Float32BufferAttribute(kc, 3));
      kg.computeVertexNormals();
      const km = new THREE.Mesh(kg, this.mat.kerb);
      km.receiveShadow = true;
      this.group.add(km);

      // racing line (assist)
      const rp = [];
      const rc = [];
      const ri = [];
      const green = new THREE.Color('#3ce37a');
      const brake = new THREE.Color('#ff3b30');
      for (let i = 0; i <= tr.n; i++) {
        const j = i % tr.n;
        const s = j * tr.step;
        const d = tr.RLD[j];
        const a = tr.pos(s, d - 0.22);
        const b = tr.pos(s, d + 0.22);
        const y = this.trackY(s) + 0.06;
        rp.push(a.x, y, a.y, b.x, y, b.y);
        const c = tr.PROF[(j + 6) % tr.n] < tr.PROF[j] - 0.4 ? brake : green;
        rc.push(c.r, c.g, c.b, c.r, c.g, c.b);
        if (i < tr.n) ri.push(i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 1, i * 2 + 3, i * 2 + 2);
      }
      const rg = new THREE.BufferGeometry();
      rg.setAttribute('position', new THREE.Float32BufferAttribute(rp, 3));
      rg.setAttribute('color', new THREE.Float32BufferAttribute(rc, 3));
      rg.setIndex(ri);
      this.racingLine = new THREE.Mesh(rg, this.mat.racing);
      this.group.add(this.racingLine);

      // barriers (Armco on the Nordschleife, tyre walls on the GP), open where the pit lane runs
      const bd = half + ro + 0.4;
      const sg = Math.sign(cfg.pitOffset);
      const gapFrom = cfg.pitEntry - 15;
      const gapTo = cfg.pitExit + 15;
      const kind = cfg.barrier;
      const barrierMat = kind === 'tyres' ? this.mat.tyrewall : kind === 'safer' ? this.mat.concrete : this.mat.armco;
      const h0 = kind === 'armco' || kind === 'armco+fence' ? 0.3 : 0;
      const h1 = kind === 'safer' ? 1.2 : kind === 'tyres' ? 0.9 : 0.85;
      // total turning < 0: the oval runs anticlockwise and its outside is on the right
      const outside = tr.KC.reduce((a, k) => a + k, 0) < 0 ? 1 : -1;
      for (const side of [-1, 1]) {
        const bdFn = (p) => tr.clampD(p, side * bd);
        const walls = side === sg ? [gapTo, L + gapFrom] : [0, L];
        if (kind === 'safer' && side !== outside) continue; // the infield is open grass
        this.wall(walls[0], walls[1], bdFn, h0, h1, barrierMat);
        if (kind === 'safer' || kind === 'armco+fence') {
          const fd = (p) => tr.clampD(p, side * (bd + 0.15));
          this.wall(walls[0], walls[1], fd, h1, kind === 'safer' ? 5 : 3.2, this.mat.fence, 3);
        }
      }
      if (kind === 'armco' || kind === 'armco+fence') {
        // Armco posts
        const post = new THREE.BoxGeometry(0.12, 0.8, 0.12);
        const count = Math.floor(L / 4) * 2;
        const inst = new THREE.InstancedMesh(post, this.mat.concrete, count);
        const mtx = new THREE.Matrix4();
        let k = 0;
        for (let s = 0; s < L - 4 && k < count - 1; s += 4) {
          for (const side of [-1, 1]) {
            const p = tr.rel(s);
            if (side === sg && p > gapFrom && p < gapTo) continue;
            const q = tr.pos(s, tr.clampD(s, side * (bd + 0.12)));
            mtx.makeTranslation(q.x, this.trackY(s) + 0.4, q.y);
            inst.setMatrixAt(k++, mtx);
          }
        }
        inst.count = k;
        inst.castShadow = true;
        this.group.add(inst);
      }

      // start line + gantry
      const line = this.ribbon(-0.8, 0.8, () => [-half, half], 0.06, new THREE.MeshStandardMaterial({ map: TEX.checker, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -5, polygonOffsetUnits: -5 }), 1.6);
      void line;
      const gantry = new THREE.Group();
      const g0 = tr.pos(0, 0);
      gantry.position.set(g0.x, this.trackY(0), g0.y);
      gantry.rotation.y = -tr.heading(0);
      const steel = new THREE.MeshStandardMaterial({ color: 0x2f3440, roughness: 0.5, metalness: 0.6 });
      for (const side of [-1, 1]) {
        const post = new THREE.Mesh(new THREE.BoxGeometry(0.5, 7, 0.5), steel);
        post.position.set(-1, 3.5, side * (half + 1.5));
        post.castShadow = true;
        gantry.add(post);
      }
      const beam = new THREE.Mesh(new THREE.BoxGeometry(0.9, 1.4, tr.width + 3.5), steel);
      beam.position.set(-1, 7, 0);
      beam.castShadow = true;
      gantry.add(beam);
      this.lights = [];
      for (let i = 0; i < 5; i++) {
        const mat = new THREE.MeshStandardMaterial({ color: 0x300808, emissive: 0xff1a1a, emissiveIntensity: 0 });
        const l = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.28, 0.12, 16).rotateZ(Math.PI / 2), mat);
        l.position.set(-1.5, 7, (i - 2) * 0.8);
        gantry.add(l);
        this.lights.push(mat);
      }
      this.group.add(gantry);
    }

    buildPits() {
      const tr = this.track;
      const cfg = tr.cfg;
      const half = tr.half;
      const po = cfg.pitOffset;
      const sg = Math.sign(po);
      const laneC = po + sg * 1;
      // lane surface
      this.ribbon(cfg.pitEntry, cfg.pitExit, (p) => {
        const b = tr.pitBlend(p);
        const c = sg * (half - 1.5) * (1 - b) + laneC * b;
        return [c - 3.5, c + 3.5];
      }, 0.015, this.mat.pitlane, 12, 12);
      // pit wall
      const w0 = cfg.pitEntry + cfg.pitRamp * 0.55;
      const w1 = cfg.pitExit - cfg.pitRamp * 0.55;
      this.wall(w0, w1, () => sg * tr.wallD, 0, 1.1, this.mat.concrete);
      this.ribbon(w0, w1, () => [sg * (tr.wallD - 0.2), sg * (tr.wallD + 0.2)].sort((a, b) => a - b), 1.1, this.mat.concrete);
      // painted boxes
      this.boxMats = [];
      for (let i = 0; i < 16; i++) {
        const s = tr.boxS(i);
        const mat = new THREE.MeshBasicMaterial({ color: 0x888888, transparent: true, opacity: 0.35, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 });
        this.ribbon(s - cfg.boxSpacing / 2 + 0.6, s + cfg.boxSpacing / 2 - 0.6, () => [po + sg * 2.2, po + sg * 5].sort((a, b) => a - b), 0.03, mat);
        this.boxMats.push(mat);
      }
      // garage building with doors facing the lane
      const g0 = tr.boxS(0) - cfg.boxSpacing / 2 - 8;
      const g1 = tr.boxS(15) + cfg.boxSpacing / 2 + 8;
      const doors = new THREE.MeshStandardMaterial({
        map: textures().garage, roughness: 0.8, side: THREE.DoubleSide, emissive: 0xffffff, emissiveMap: textures().garage, emissiveIntensity: 0,
      });
      this.garageMat = doors;
      this.wall(g0, g1, () => po + sg * 5.4, 0, 6.5, doors, cfg.boxSpacing);
      this.wall(g0, g1, () => po + sg * 20, 0, 6.5, this.mat.concrete);
      this.ribbon(g0, g1, () => [po + sg * 5.4, po + sg * 20].sort((a, b) => a - b), 6.5, new THREE.MeshStandardMaterial({ color: 0x9aa0a8, roughness: 0.8, side: THREE.DoubleSide }));
      // grandstands on the far side of the GP straight
      if (cfg.grandstands) {
        const crowd = new THREE.MeshStandardMaterial({ map: textures().crowd, roughness: 1, side: THREE.DoubleSide });
        const d0 = -sg * (half + cfg.runoff + 3);
        const tiers = cfg.standTiers;
        for (let p = cfg.stands[0]; p < cfg.stands[1] - 10; p += 70) {
          for (let k = 0; k < tiers; k++) {
            const a = d0 - sg * k * 2.6;
            const b = d0 - sg * (k + 1) * 2.6;
            this.ribbon(p, p + 62, () => [a, b].sort((x, y) => x - y), 1 + k * 1.3, crowd, 20);
            this.wall(p, p + 62, () => a, k * 1.3, 1 + k * 1.3, this.mat.concrete);
          }
          this.wall(p, p + 62, () => d0 - sg * tiers * 2.6, 0, 2 + tiers * 1.3, this.mat.concrete);
        }
      }
    }

    buildTrees() {
      const tr = this.track;
      const cfg = tr.cfg;
      const rand = mulberry32(7 + tr.n);
      const conifer = [];
      const leafy = [];
      const sg = Math.sign(cfg.pitOffset);
      const { density, patch, conifer: coniferShare } = cfg.trees;
      const minClear = tr.half + cfg.runoff + 4;
      for (let i = 0; i < tr.n; i += 2) {
        for (const side of [-1, 1]) {
          let tries = density;
          while (tries > 0) {
            if (rand() > tries) break;
            tries -= 1;
            const r = minClear + Math.pow(rand(), 1.25) * 200;
            const p = tr.rel(i * tr.step);
            if (side === sg && p > cfg.pitEntry - 40 && p < cfg.pitExit + 40 && r < Math.abs(cfg.pitOffset) + 35) continue;
            if (cfg.grandstands && side === -sg && p > cfg.stands[0] - 20 && p < cfg.stands[1] + 20 && r < tr.half + cfg.runoff + 12 + cfg.standTiers * 2.6) continue;
            const x = tr.X[i] + tr.NX[i] * r * side + (rand() - 0.5) * 8;
            const y = tr.Y[i] + tr.NY[i] * r * side + (rand() - 0.5) * 8;
            if (noise2(x / 260, y / 260) < patch) continue;
            if (cfg.sea && this.dem(x, y) < 1.5) continue;
            const near = this.nearest(x, y, 3);
            if (near && near.dist < minClear) continue;
            const t = { x, y, h: this.groundY(x, y, near), s: 0.75 + rand() * 0.6, c: rand() };
            if (rand() < coniferShare) conifer.push(t);
            else {
              t.kind = 1;
              leafy.push(t);
            }
          }
        }
      }
      const T = textures();
      const G = treeGeometries();
      const trunkMat = new THREE.MeshStandardMaterial({ map: T.bark, color: 0x9a8c7c, roughness: 1 });
      const foliage = (map) =>
        new THREE.MeshStandardMaterial({ map, vertexColors: true, roughness: 0.9, alphaTest: 0.45, side: THREE.DoubleSide, alphaToCoverage: true });
      const needleMat = foliage(T.needles);
      const leafMat = foliage(T.leaves);
      // far trees: the same textures, drawn opaque so they don't thin out in the mipmaps
      const opaque = (m) => Object.assign(m.clone(), { alphaTest: 0, alphaToCoverage: false, side: THREE.FrontSide });
      const needleFar = opaque(needleMat);
      const leafFar = opaque(leafMat);
      const mtx = new THREE.Matrix4();
      const q = new THREE.Quaternion();
      const col = new THREE.Color();
      const pine = [new THREE.Color('#3b6a3e'), new THREE.Color('#4f7d48')];
      const oak = [new THREE.Color('#6f9a4a'), new THREE.Color('#92b05a')];
      // chunk instances spatially so the camera and the shadow pass can cull them, and so each chunk
      // can switch between detailed and simple trees with distance
      const chunks = new Map();
      const tile = 200;
      const push = (t, kind) => {
        const k = Math.floor(t.x / tile) + ',' + Math.floor(t.y / tile);
        if (!chunks.has(k)) chunks.set(k, { conifer: [], leafy: [], x: (Math.floor(t.x / tile) + 0.5) * tile, y: (Math.floor(t.y / tile) + 0.5) * tile });
        chunks.get(k)[kind].push(t);
      };
      conifer.forEach((t) => push(t, 'conifer'));
      leafy.forEach((t) => push(t, 'leafy'));
      const inst = (geo, mat, list, place, colors, out) => {
        if (!list.length) return;
        const im = new THREE.InstancedMesh(geo, mat, list.length);
        list.forEach((t, k) => {
          place(t, mtx);
          im.setMatrixAt(k, mtx);
          im.setColorAt(k, colors ? col.copy(colors[0]).lerp(colors[1], t.c) : col.setRGB(1, 1, 1));
        });
        im.castShadow = true;
        im.receiveShadow = true;
        im.computeBoundingSphere();
        this.group.add(im);
        out.push(im);
      };
      const sc = new THREE.Vector3();
      const pv = new THREE.Vector3();
      const spin = (t) => q.setFromAxisAngle(sc.set(0, 1, 0), t.c * 40);
      this.treeChunks = [];
      for (const ch of chunks.values()) {
        const all = ch.conifer.concat(ch.leafy);
        const near = [];
        const far = [];
        const always = [];
        inst(G.trunk, trunkMat, all, (t, m) => m.compose(pv.set(t.x, t.h - 0.2, t.y), spin(t), sc.set(t.s, (t.kind ? 3.6 : 3.2) * t.s, t.s)), null, always);
        const pineAt = (t, m) => m.compose(pv.set(t.x, t.h + 1.2 * t.s, t.y), spin(t), sc.set(2.7 * t.s, 12 * t.s, 2.7 * t.s));
        const oakAt = (t, m) => m.compose(pv.set(t.x, t.h + 5.2 * t.s, t.y), spin(t), sc.set(3.5 * t.s, 3.2 * t.s, 3.5 * t.s));
        inst(G.pine, needleMat, ch.conifer, pineAt, pine, near);
        inst(G.pineFar, needleFar, ch.conifer, pineAt, pine, far);
        inst(G.oak, leafMat, ch.leafy, oakAt, oak, near);
        inst(G.oakFar, leafFar, ch.leafy, oakAt, oak, far);
        far.forEach((m) => (m.visible = false));
        this.treeChunks.push({ x: ch.x, y: ch.y, near, far, isNear: true });
      }
      this.treeCount = conifer.length + leafy.length;
    }

    // Detailed trees near the camera, simple ones further out.
    updateLod(cam) {
      if (!this.treeChunks) return;
      for (const ch of this.treeChunks) {
        const d2 = (ch.x - cam.x) ** 2 + (ch.y - cam.z) ** 2;
        const isNear = d2 < (ch.isNear ? 360 : 320) ** 2;
        if (isNear === ch.isNear) continue;
        ch.isNear = isNear;
        ch.near.forEach((m) => (m.visible = isNear));
        ch.far.forEach((m) => (m.visible = !isNear));
      }
    }

    // Monaco: blocks of flats and hotels right behind the barriers, stepping up the hillside.
    buildCity() {
      const tr = this.track;
      const cfg = tr.cfg;
      const rand = mulberry32(99 + tr.n);
      const sg = Math.sign(cfg.pitOffset);
      const minClear = tr.half + cfg.runoff + 2.5;
      const standsOut = tr.half + cfg.runoff + 16 + cfg.standTiers * 2.6;
      const list = [];
      for (let i = 0; i < tr.n; i += 8) {
        for (const side of [-1, 1]) {
          for (let row = 0; row < 4; row++) {
            if (rand() < 0.3) continue;
            const w = 10 + rand() * 16;
            const dp = 9 + rand() * 14;
            const r = minClear + dp / 2 + 1.5 + row * 24 + rand() * 6;
            const p = tr.rel(i * tr.step);
            if (side === sg && p > cfg.pitEntry - 25 && p < cfg.pitExit + 25 && r - dp / 2 < Math.abs(cfg.pitOffset) + 24) continue;
            if (cfg.grandstands && side === -sg && p > cfg.stands[0] - 25 && p < cfg.stands[1] + 25 && r - dp / 2 < standsOut) continue;
            const x = tr.X[i] + tr.NX[i] * r * side + (rand() - 0.5) * 4;
            const y = tr.Y[i] + tr.NY[i] * r * side + (rand() - 0.5) * 4;
            if (this.dem(x, y) < 1.5) continue; // harbour
            const near = this.nearest(x, y, 3);
            if (near && near.dist < minClear + Math.hypot(w, dp) / 2) continue;
            list.push({ x, y, w, dp, h: 10 + Math.pow(rand(), 1.7) * 40, ang: tr.ANG[i], g: this.groundY(x, y, near), c: rand() });
          }
        }
      }
      const palette = ['#efe3cc', '#e9d3b0', '#dcbfa0', '#f3efe6', '#e6c2a4', '#d9a98d', '#cdbb98', '#f1dcc4'].map((c) => new THREE.Color(c));
      const geo = new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0);
      const mat = new THREE.MeshStandardMaterial({
        map: textures().facade, roughness: 0.85, emissive: 0xffffff, emissiveMap: textures().facadeLit, emissiveIntensity: 0,
      });
      // facade UVs in metres (a 12 m texture tile of 4 floors), so windows keep their size on any block
      patchShader(mat, 'facade', (sh) => {
        sh.vertexShader = 'varying float vRoof;\n' + sh.vertexShader.replace(
          '#include <uv_vertex>',
          `#include <uv_vertex>
          vec3 bs = vec3( length( instanceMatrix[ 0 ].xyz ), length( instanceMatrix[ 1 ].xyz ), length( instanceMatrix[ 2 ].xyz ) );
          vec2 fUv = abs( normal.x ) > 0.5 ? vec2( ( position.z + 0.5 ) * bs.z, position.y * bs.y - 2.0 ) : vec2( ( position.x + 0.5 ) * bs.x, position.y * bs.y - 2.0 );
          fUv /= 12.0;
          vRoof = step( 0.5, normal.y );
          if ( vRoof > 0.5 ) fUv = vec2( 0.03, 0.2 );
          #ifdef USE_MAP
            vMapUv = fUv;
          #endif
          #ifdef USE_EMISSIVEMAP
            vEmissiveMapUv = fUv;
          #endif`
        );
        sh.fragmentShader = 'varying float vRoof;\n' + sh.fragmentShader.replace(
          '#include <map_fragment>',
          '#include <map_fragment>\n diffuseColor.rgb *= mix( 1.0, 0.62, vRoof );'
        );
      });
      this.cityMat = mat;
      const chunks = new Map();
      for (const b of list) {
        const k = Math.floor(b.x / 300) + ',' + Math.floor(b.y / 300);
        if (!chunks.has(k)) chunks.set(k, []);
        chunks.get(k).push(b);
      }
      const m = new THREE.Matrix4();
      const q = new THREE.Quaternion();
      const e = new THREE.Euler();
      const pv = new THREE.Vector3();
      const sv = new THREE.Vector3();
      for (const bs of chunks.values()) {
        const im = new THREE.InstancedMesh(geo, mat, bs.length);
        bs.forEach((b, k) => {
          q.setFromEuler(e.set(0, -b.ang, 0));
          im.setMatrixAt(k, m.compose(pv.set(b.x, b.g - 2, b.y), q, sv.set(b.w, b.h + 2, b.dp)));
          im.setColorAt(k, palette[Math.floor(b.c * palette.length)]);
        });
        im.castShadow = true;
        im.receiveShadow = true;
        im.computeBoundingSphere();
        this.group.add(im);
      }
      this.buildingCount = list.length;
    }

    buildSea() {
      const b = this.track.bounds;
      const waves = textures().waves;
      waves.repeat.set(1800, 1800);
      this.mat.sea = new THREE.MeshStandardMaterial({ color: 0x0d3a4d, roughness: 0.06, metalness: 0.1, normalMap: waves, normalScale: new THREE.Vector2(0.55, 0.55), envMapIntensity: 1.4 });
      const sea = new THREE.Mesh(new THREE.PlaneGeometry(40000, 40000).rotateX(-Math.PI / 2), this.mat.sea);
      sea.position.set((b.minX + b.maxX) / 2, 0.3 - this.base, (b.minY + b.maxY) / 2);
      sea.receiveShadow = true;
      this.group.add(sea);
    }

    // Covered sections (Monaco's tunnel): side walls, a roof that shades the road, and a row of lamps.
    buildTunnels() {
      const tr = this.track;
      const raw = window.TRACK_DATA[tr.key];
      if (!raw.tunnels) return;
      const off = Math.round(tr.cfg.startOffset / tr.step);
      const wd = tr.half + tr.cfg.runoff + 0.6;
      // the lamps light the tube: a little emissive keeps the walls from going black in the shadow
      const concrete = new THREE.MeshStandardMaterial({ color: 0x9a958b, emissive: 0x3a352c, roughness: 0.9, side: THREE.DoubleSide });
      this.tunnelWall = concrete;
      this.tunnelLamp = new THREE.MeshStandardMaterial({ color: 0xfff0c8, emissive: 0xffd88a, emissiveIntensity: 2.2, side: THREE.DoubleSide });
      for (const [a, b] of raw.tunnels) {
        const s0 = (a - off) * tr.step - 2;
        let s1 = (b - off) * tr.step + 2;
        if (s1 < s0) s1 += tr.L;
        if (s1 - s0 < 30) continue; // short underpasses: nothing to draw
        for (const side of [-1, 1]) this.wall(s0, s1, (p) => tr.clampD(p, side * wd), 0, 6.2, concrete);
        const roof = this.ribbon(s0, s1, (p) => [tr.clampD(p, -wd - 0.4), tr.clampD(p, wd + 0.4)], 6.2, concrete);
        roof.castShadow = true;
        this.ribbon(s0, s1, (p) => [tr.clampD(p, -wd - 3), tr.clampD(p, wd + 3)], 8, concrete).castShadow = true;
        for (let p = s0 + 4; p < s1 - 4; p += 9) this.ribbon(p, p + 3.5, () => [-0.3, 0.3], 6.1, this.tunnelLamp);
        for (const side of [-1, 1]) this.wall(s0, s1, (p) => tr.clampD(p, side * (wd + 3)), 6.2, 8, concrete);
      }
    }
  }

  // ---------------- tree geometry (unit size; instances scale them) ----------------
  function mergeGeometries(list) {
    const names = ['position', 'normal', 'uv', 'color'];
    const out = {};
    for (const n of names) out[n] = [];
    for (const g0 of list) {
      const g = g0.index ? g0.toNonIndexed() : g0;
      for (const n of names) {
        const a = g.attributes[n].array;
        for (let i = 0; i < a.length; i++) out[n].push(a[i]);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(out.position, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(out.normal, 3));
    geo.setAttribute('uv', new THREE.Float32BufferAttribute(out.uv, 2));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(out.color, 3));
    geo.computeBoundingSphere();
    return geo;
  }
  // Soft "volume" normals (pointing out of the whole crown) and a baked occlusion term in the colours.
  function foliageAttribs(g, centre, ao, uvScale) {
    const p = g.attributes.position;
    const nrm = [];
    const col = [];
    const v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) {
      v.set(p.getX(i) - centre.x, p.getY(i) - centre.y, p.getZ(i) - centre.z).normalize();
      nrm.push(v.x, v.y, v.z);
      const a = ao(p.getX(i), p.getY(i), p.getZ(i));
      col.push(a, a, a * 0.96);
    }
    g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
    const uv = g.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * uvScale[0], uv.getY(i) * uvScale[1]);
    return g;
  }
  let treeGeo = null;
  function treeGeometries() {
    if (treeGeo) return treeGeo;
    // spruce: drooping tiers of branches, each an outer and an inner skirt; total height 1
    const spruce = (tiers, layers, seg) => {
      const parts = [];
      for (let k = 0; k < tiers; k++) {
        const f = k / tiers;
        for (let l = 0; l < layers; l++) {
          const r = (Math.pow(1 - f, 0.9) * 0.95 + 0.1) * (l ? 0.62 : 1);
          const h = (0.34 - 0.12 * f) * (l ? 0.8 : 1);
          const y = 0.05 + f * 0.8 + l * 0.03;
          const g = new THREE.ConeGeometry(r, h, seg, 1, true, k * 0.7 + l);
          g.translate(0, y + h / 2, 0);
          const p = g.attributes.position;
          for (let i = 0; i < p.count; i++) {
            if (p.getY(i) > y + 0.001) continue;
            const a = Math.atan2(p.getZ(i), p.getX(i));
            const j = 0.82 + 0.36 * hash2(Math.round(a * 20) + k * 31, l);
            p.setXYZ(i, p.getX(i) * j, y - 0.035 * hash2(Math.round(a * 20), k), p.getZ(i) * j);
          }
          const top = y + h;
          foliageAttribs(g, new THREE.Vector3(0, y - 0.1, 0), (x, yy, z) => {
            const out = Math.min(1, Math.hypot(x, z) / r);
            return (0.45 + 0.4 * f + 0.15 * (yy > top - 0.02 ? 0 : 1)) * (0.62 + 0.38 * out) * (l ? 0.8 : 1);
          }, [3, 1]);
          parts.push(g);
        }
      }
      return mergeGeometries(parts);
    };
    // broadleaf crown: a cluster of lumpy leaf clumps inside a unit ellipsoid
    const crown = (clumps, detail) => {
      const parts = [];
      for (const [cx, cy, cz, r] of clumps) {
        const g = new THREE.IcosahedronGeometry(r, detail);
        const p = g.attributes.position;
        for (let i = 0; i < p.count; i++) {
          const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
          const k = 0.8 + 0.4 * hash2(Math.round((x / r) * 9 + cx * 5) + 17 * Math.round((z / r) * 9), Math.round((y / r) * 9 + cy * 5));
          p.setXYZ(i, cx + x * k, cy + y * k, cz + z * k);
        }
        foliageAttribs(g, new THREE.Vector3(0, -0.15, 0), (x, y, z) => {
          const out = Math.min(1, Math.hypot(x, y + 0.15, z));
          return (0.5 + 0.5 * smoothstep((y + 0.7) / 1.4)) * (0.55 + 0.45 * out);
        }, [3, 2]);
        parts.push(g);
      }
      return mergeGeometries(parts);
    };
    const oak = [
      [0, 0.08, 0, 0.62], [0.44, -0.08, 0.12, 0.5], [-0.42, -0.02, -0.18, 0.52], [0.06, 0.02, 0.46, 0.48],
      [-0.12, -0.12, -0.46, 0.48], [0.12, 0.5, -0.08, 0.5], [0.34, 0.34, 0.3, 0.4], [-0.32, 0.38, 0.2, 0.42],
    ];
    treeGeo = {
      pine: spruce(7, 2, 9),
      pineFar: spruce(4, 1, 7),
      oak: crown(oak, 1),
      oakFar: crown(oak.filter((c, i) => i % 2 === 0).map(([x, y, z, r]) => [x, y, z, r * 1.25]), 0),
      trunk: new THREE.CylinderGeometry(0.14, 0.26, 1, 6).translate(0, 0.5, 0),
    };
    return treeGeo;
  }

  // Banks and embankments show earth and rock instead of lawn.
  function shadeSlopes(geo, theme) {
    const n = geo.attributes.normal;
    const c = geo.attributes.color;
    const earth = new THREE.Color(theme.earth || '#6f6450');
    const tmp = new THREE.Color();
    for (let i = 0; i < n.count; i++) {
      const k = smoothstep((1 - n.getY(i) - 0.12) / 0.3);
      if (k <= 0) continue;
      tmp.setRGB(c.getX(i), c.getY(i), c.getZ(i)).lerp(earth, k * 0.75);
      c.setXYZ(i, tmp.r, tmp.g, tmp.b);
    }
  }

  // smooth value noise in [0,1]
  function hash2(i, j) {
    const s = Math.sin(i * 127.1 + j * 311.7) * 43758.5453;
    return s - Math.floor(s);
  }
  function noise2(x, y) {
    const i = Math.floor(x);
    const j = Math.floor(y);
    const u = smoothstep(x - i);
    const v = smoothstep(y - j);
    const a = hash2(i, j), b = hash2(i + 1, j), c = hash2(i, j + 1), d = hash2(i + 1, j + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  // ---------------- renderer ----------------
  const CAMERA_MODES = ['chase', 'far', 'bonnet', 'top'];

  const dirFrom = (el, az, out) => {
    const e = (el * Math.PI) / 180;
    const a = (az * Math.PI) / 180;
    return out.set(Math.sin(a) * Math.cos(e), Math.sin(e), -Math.cos(a) * Math.cos(e)).normalize();
  };

  // Graphics quality tiers. 'low' is the original single-shadow renderer; 'high' and 'ultra' add a
  // physical sky with clouds, cascaded shadows out to the horizon, sky-lit reflections and bloom.
  const QUALITY = {
    low: { dpr: 1.25, post: false },
    high: { dpr: 1.5, post: true, cascades: 3, far: 800, map: 2048, bloom: 0.2 },
    ultra: { dpr: 2, post: true, cascades: 4, far: 1400, map: 4096, bloom: 0.26 },
  };

  // Camera-like finishing in linear HDR, before tone mapping: a touch of saturation, lens vignette and
  // fine film grain (kept static-free by animating it).
  class GradePass {
    constructor() {
      this.enabled = true;
      this.needsSwap = true;
      this.clear = false;
      this.renderToScreen = false;
      this.mat = new THREE.ShaderMaterial({
        uniforms: {
          tDiffuse: { value: null }, time: { value: 0 }, aspect: { value: 1 }, sat: { value: 1.08 }, contrast: { value: 1.08 },
          mid: { value: 3 }, vignette: { value: 0.28 }, grain: { value: 0.03 }, cool: { value: 0 },
        },
        vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4( position.xy, 0.0, 1.0 ); }',
        fragmentShader: `
          uniform sampler2D tDiffuse;
          uniform float time, aspect, sat, contrast, mid, vignette, grain, cool;
          varying vec2 vUv;
          void main() {
            vec3 c = texture2D( tDiffuse, vUv ).rgb;
            float l = dot( c, vec3( 0.2126, 0.7152, 0.0722 ) );
            c = max( mix( vec3( l ), c, sat ), 0.0 );
            c = mid * pow( c / mid + 1e-6, vec3( contrast ) );
            c *= mix( vec3( 1.0 ), vec3( 0.92, 0.97, 1.08 ), cool );
            vec2 d = ( vUv - 0.5 ) * vec2( aspect, 1.0 );
            c *= 1.0 - vignette * smoothstep( 0.25, 1.05, length( d ) );
            float n = fract( sin( dot( vUv * 1777.0 + fract( time ) * 91.0, vec2( 12.9898, 78.233 ) ) ) * 43758.5453 );
            c *= 1.0 + ( n - 0.5 ) * grain;
            gl_FragColor = vec4( c, 1.0 );
          }`,
        depthTest: false,
        depthWrite: false,
      });
      this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.mat);
      this.quad.frustumCulled = false;
      this.cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    }
    update(t, aspect, night, rain) {
      const u = this.mat.uniforms;
      u.time.value = t;
      u.aspect.value = aspect;
      u.sat.value = 1.08 - 0.12 * rain - 0.2 * night;
      u.cool.value = Math.min(1, 0.6 * night + 0.5 * rain);
    }
    setSize() {}
    render(renderer, writeBuffer, readBuffer) {
      this.mat.uniforms.tDiffuse.value = readBuffer.texture;
      renderer.setRenderTarget(this.renderToScreen ? null : writeBuffer);
      renderer.render(this.quad, this.cam);
    }
    dispose() {
      this.mat.dispose();
    }
  }

  class Renderer3D {
    constructor(canvas, overlay, quality = 'high') {
      this.canvas = canvas;
      this.overlay = overlay;
      this.octx = overlay.getContext('2d');
      const EX = window.THREE_EXTRAS;
      this.q = QUALITY[quality] && (EX || quality === 'low') ? QUALITY[quality] : QUALITY.low;
      const post = this.q.post;
      this.gl = new THREE.WebGLRenderer({ canvas, antialias: !post, logarithmicDepthBuffer: true, powerPreference: 'high-performance' });
      this.gl.outputColorSpace = THREE.SRGBColorSpace;
      this.gl.toneMapping = post ? THREE.AgXToneMapping : THREE.ACESFilmicToneMapping;
      // The physical sky is in real-ish relative units (clear sky ~10): lights scale up to match it and the
      // exposure comes down, like a camera. The sun gets a little extra so sunlit ground sits a few stops
      // below the sky, as in a photo, rather than ~20x darker.
      this.gl.toneMappingExposure = post ? 0.075 : 1.05;
      this.lightGain = post ? 14 : 1;
      this.sunGain = post ? 1.7 : 1;
      this.gl.shadowMap.enabled = true;
      this.gl.shadowMap.type = THREE.PCFShadowMap;
      this.scene = new THREE.Scene();
      this.camera = new THREE.PerspectiveCamera(62, 1, 0.3, 6000);
      this.worlds = {};
      this.carViews = new Map();
      this.cam = { snap: true };
      this.camHead = 0;
      this.tv = null;
      // reused every frame in the hot path (updateCamera/draw/updateLights) to avoid GC churn
      this._scratch = {
        camP: new THREE.Vector3(), camFwd: new THREE.Vector3(), camTarget: new THREE.Vector3(),
        camWant: new THREE.Vector3(), focusPos: new THREE.Vector3(), tag: new THREE.Vector3(),
      };
      this._rankPool = [];

      // image-based lighting from a simple sky dome: gives paint and glass something to reflect
      const envScene = new THREE.Scene();
      const dome = new THREE.SphereGeometry(100, 32, 16);
      const dc = [];
      const top = new THREE.Color('#5b8fd6'), hor = new THREE.Color('#e8eef4'), gnd = new THREE.Color('#4a5a3a');
      const tmp = new THREE.Color();
      const dp = dome.attributes.position;
      for (let i = 0; i < dp.count; i++) {
        const y = dp.getY(i) / 100;
        if (y > 0) tmp.copy(hor).lerp(top, Math.pow(y, 0.6));
        else tmp.copy(hor).lerp(gnd, Math.min(1, -y * 4));
        dc.push(tmp.r, tmp.g, tmp.b);
      }
      dome.setAttribute('color', new THREE.Float32BufferAttribute(dc, 3));
      envScene.add(new THREE.Mesh(dome, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
      const pmrem = new THREE.PMREMGenerator(this.gl);
      this.scene.environment = pmrem.fromScene(envScene, 0.02).texture;
      this.scene.environmentIntensity = 0.55;

      this.hemi = new THREE.HemisphereLight(0xcfe3ff, 0x3d5a2a, 0.6);
      this.scene.add(this.hemi);
      this.sun = new THREE.DirectionalLight(0xfff1dc, 2.6);
      this.sun.castShadow = true;
      this.sun.shadow.mapSize.set(2048, 2048);
      const sc = this.sun.shadow.camera;
      sc.left = -70;
      sc.right = 70;
      sc.top = 70;
      sc.bottom = -70;
      sc.near = 1;
      sc.far = 400;
      this.sun.shadow.bias = -0.0006;
      this.sun.shadow.normalBias = 0.04;
      this.scene.add(this.sun);
      this.scene.add(this.sun.target);
      this.sunDir = new THREE.Vector3(-0.45, 0.8, 0.35).normalize();

      this.skyCanvas = document.createElement('canvas');
      this.skyCanvas.width = 4;
      this.skyCanvas.height = 256;
      this.skyTex = new THREE.CanvasTexture(this.skyCanvas);
      this.skyTex.colorSpace = THREE.SRGBColorSpace;
      this.scene.background = this.skyTex;
      this.scene.fog = new THREE.Fog(0xcfdce8, 250, 1600);
      this.skyWet = -1;

      const N = 2200;
      const rp = new Float32Array(N * 6);
      this.rainGeo = new THREE.BufferGeometry();
      this.rainGeo.setAttribute('position', new THREE.BufferAttribute(rp, 3));
      this.rain = new THREE.LineSegments(this.rainGeo, new THREE.LineBasicMaterial({ color: 0xc8d4e0, transparent: true, opacity: 0.45 }));
      this.rain.frustumCulled = false;
      this.rainDrops = [];
      for (let i = 0; i < N; i++) this.rainDrops.push({ x: (Math.random() - 0.5) * 80, y: Math.random() * 30, z: (Math.random() - 0.5) * 80 });
      this.scene.add(this.rain);

      // night sky
      const sp = [];
      const sr = mulberry32(3);
      for (let i = 0; i < 1600; i++) {
        const u = sr() * Math.PI * 2;
        const v = Math.asin(0.05 + 0.95 * sr());
        sp.push(Math.cos(u) * Math.cos(v) * 2500, Math.sin(v) * 2500, Math.sin(u) * Math.cos(v) * 2500);
      }
      const sg = new THREE.BufferGeometry();
      sg.setAttribute('position', new THREE.Float32BufferAttribute(sp, 3));
      this.starMat = new THREE.PointsMaterial({ color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false });
      this.stars = new THREE.Points(sg, this.starMat);
      this.stars.frustumCulled = false;
      this.scene.add(this.stars);

      // a fixed pool of headlight beams, handed to the cars nearest the camera after dark
      this.beams = [];
      for (let i = 0; i < 4; i++) {
        const l = new THREE.SpotLight(0xfff1d6, 0, 130, 0.45, 0.5, 1);
        this.scene.add(l);
        this.scene.add(l.target);
        this.beams.push(l);
      }
      this.night = 0;
      this.skyKey = '';

      if (post) this.setupPost(EX);

      this.resize();
      window.addEventListener('resize', () => this.resize());
    }

    setupPost(EX) {
      const q = this.q;
      // physical sky (sun, Rayleigh/Mie scattering, clouds), drawn first behind everything
      this.sky = new EX.Sky();
      this.sky.scale.setScalar(4000);
      this.sky.material.depthTest = false;
      this.sky.renderOrder = -10;
      this.sky.frustumCulled = false;
      const u = this.sky.material.uniforms;
      u.mieDirectionalG.value = 0.82;
      u.cloudScale.value = 0.00025;
      this.scene.add(this.sky);
      this.scene.background = null;
      // grey overcast layer that closes in with the rain
      const ocMat = new THREE.MeshBasicMaterial({ color: 0x9aa3ad, transparent: true, opacity: 0, side: THREE.BackSide, depthTest: false, depthWrite: false, fog: false });
      this.overcast = new THREE.Mesh(new THREE.SphereGeometry(3500, 24, 12), ocMat);
      this.overcast.renderOrder = -9;
      this.overcast.frustumCulled = false;
      this.scene.add(this.overcast);
      // the same sky, small, for image-based lighting (re-baked when the sun or weather changes)
      this.envScene = new THREE.Scene();
      const envSky = new EX.Sky();
      envSky.material.uniforms.showSunDisc.value = 0; // no sun hot-spot in reflections
      this.envSky = envSky;
      envSky.scale.setScalar(100);
      this.envScene.add(envSky);
      const envOc = new THREE.Mesh(new THREE.SphereGeometry(80, 16, 8), ocMat);
      this.envScene.add(envOc);
      const ground = new THREE.Mesh(new THREE.CircleGeometry(90, 24).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x2c3a24 }));
      ground.position.y = -2;
      this.envScene.add(ground);
      this.envGround = ground.material;
      this.pmrem = new THREE.PMREMGenerator(this.gl);
      this.envAt = -1e9;

      // cascaded shadow maps: crisp near the car, still there on the far hillsides
      this.csm = new EX.CSM({
        camera: this.camera, parent: this.scene, cascades: q.cascades, maxFar: q.far, mode: 'practical',
        shadowMapSize: q.map, lightDirection: this.sunDir.clone().negate(), lightIntensity: 2.6,
        shadowBias: -0.00025, lightMargin: 300, lightFar: 4000,
      });
      this.csm.fade = true;
      for (const l of this.csm.lights) l.shadow.normalBias = 0.05;
      this.csmMats = new WeakSet();
      this.sun.visible = false;
      this.sun.castShadow = false;

      // HDR render target with MSAA, bloom for lamps / low sun, grading, then tone mapping + sRGB output
      const rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: 4 });
      this.composer = new EX.EffectComposer(this.gl, rt);
      this.composer.addPass(new EX.RenderPass(this.scene, this.camera));
      // Threshold is in scene (pre-exposure) units and above the brightest sky, so only lamps, lit
      // headlights and the sun disc glow. Only the energy above it blooms (soft knee), clamped so the sun
      // can't flood the frame.
      this.bloom = new EX.UnrealBloomPass(new THREE.Vector2(256, 256), q.bloom, 0.55, 30);
      const hp = this.bloom.materialHighPassFilter;
      hp.fragmentShader = `
        uniform sampler2D tDiffuse;
        uniform float luminosityThreshold;
        varying vec2 vUv;
        void main() {
          vec3 c = min( texture2D( tDiffuse, vUv ).rgb, vec3( 400.0 ) );
          float l = max( max( c.r, c.g ), c.b );
          float k = max( l - luminosityThreshold, 0.0 );
          k = k * k / ( k + luminosityThreshold );
          gl_FragColor = vec4( c * ( k / max( l, 1e-4 ) ), 1.0 );
        }`;
      hp.needsUpdate = true;
      this.composer.addPass(this.bloom);
      this.grade = new GradePass();
      this.composer.addPass(this.grade);
      this.composer.addPass(new EX.OutputPass());
    }

    // Cascaded shadows need their shader chunk in every lit material (world, cars, trees…).
    prepareMaterials(root) {
      if (!this.csm) return;
      root.traverse((o) => {
        if (!o.isMesh) return;
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
          if (!m || !m.isMeshStandardMaterial || this.csmMats.has(m)) continue;
          this.csmMats.add(m);
          const own = m.userData.patches ? m.onBeforeCompile : null;
          this.csm.setupMaterial(m);
          if (own) {
            const csmHook = m.onBeforeCompile;
            m.onBeforeCompile = function (shader, r) {
              csmHook.call(this, shader, r);
              own.call(this, shader, r);
            };
          }
        }
      });
    }

    updateEnv(force) {
      if (!this.pmrem) return;
      const now = performance.now();
      if (!force && now - this.envAt < 2000) return;
      this.envAt = now;
      const old = this.envRT;
      this.envRT = this.pmrem.fromScene(this.envScene, 0.02, 0.1, 1000);
      this.scene.environment = this.envRT.texture;
      if (old) old.dispose();
      this.measureHorizon();
    }

    // Haze takes the colour of the sky just above the horizon (averaged all round), so distant hills
    // fade into the sky instead of into grey.
    measureHorizon() {
      if (!this.hzRT) {
        this.hzRT = new THREE.WebGLRenderTarget(16, 4, { type: THREE.FloatType });
        this.hzCam = new THREE.PerspectiveCamera(8, 4, 0.1, 1000);
        this.hzBuf = new Float32Array(16 * 4 * 4);
      }
      const gl = this.gl;
      const prevTarget = gl.getRenderTarget();
      const prevTone = gl.toneMapping;
      gl.toneMapping = THREE.NoToneMapping;
      const acc = [0, 0, 0];
      for (let k = 0; k < 4; k++) {
        this.hzCam.position.set(0, 0, 0);
        this.hzCam.lookAt(Math.cos(k * Math.PI / 2), 0.07, Math.sin(k * Math.PI / 2));
        gl.setRenderTarget(this.hzRT);
        gl.render(this.envScene, this.hzCam);
        gl.readRenderTargetPixels(this.hzRT, 0, 0, 16, 4, this.hzBuf);
        for (let i = 0; i < 16 * 4; i++) for (let c = 0; c < 3; c++) acc[c] += this.hzBuf[i * 4 + c];
      }
      gl.setRenderTarget(prevTarget);
      gl.toneMapping = prevTone;
      const n = 4 * 16 * 4;
      this.horizon = new THREE.Color(acc[0] / n, acc[1] / n, acc[2] / n);
      this.applyHaze();
    }

    applyHaze() {
      if (!this.horizon || !this.scene.fog) return;
      // blend in the overcast grey for rain (fog colour is added after lighting, in scene units)
      const c = this.horizon.clone().lerp(this.hazeGrey || this.horizon, this.hazeWet || 0);
      this.scene.fog.color.copy(c);
      this.overcast.material.color.copy(c);
    }

    resize() {
      this.W = window.innerWidth;
      this.H = window.innerHeight;
      this.dpr = Math.min(this.q.dpr, window.devicePixelRatio || 1);
      this.gl.setPixelRatio(this.dpr);
      this.gl.setSize(this.W, this.H, false);
      this.camera.aspect = this.W / this.H;
      this.camera.updateProjectionMatrix();
      if (this.composer) {
        this.composer.setPixelRatio(this.dpr);
        this.composer.setSize(this.W, this.H);
        this.bloom.setSize(this.W * this.dpr * 0.5, this.H * this.dpr * 0.5);
      }
      if (this.csm) this.csm.updateFrustums();
      const odpr = Math.min(2, window.devicePixelRatio || 1);
      this.overlay.width = this.W * odpr;
      this.overlay.height = this.H * odpr;
      this.odpr = odpr;
    }

    setTrack(track) {
      if (this.world && this.world.track === track) return;
      if (this.world) this.scene.remove(this.world.group);
      if (!this.worlds[track.key]) this.worlds[track.key] = new TrackWorld(track);
      this.world = this.worlds[track.key];
      this.scene.add(this.world.group);
      this.prepareMaterials(this.world.group);
      this.cam.snap = true;
    }

    // Sky, fog and lights for the weather (wet 0..1) and the local time of day (hours).
    paintSky(wet, hour) {
      const q = Math.round(wet * 20) / 20;
      const sun = sunAt(hour);
      const el = Math.round(sun.el * 2) / 2;
      const day = smoothstep((el + 6) / 14); // 0 after civil dusk, 1 once the sun is 8° up (as sunAt().day)
      const glow = (1 - smoothstep(Math.abs(el + 1) / 9)) * (1 - q) * 0.85; // sunrise/sunset tint
      const key = q + ',' + el + ',' + (sun.az > 180 ? 1 : 0);
      if (key !== this.skyKey) {
        this.skyKey = key;
        const col = (dayWet, dayDry, night, dusk) => {
          const c = new THREE.Color(dayDry).lerp(new THREE.Color(dayWet), q);
          c.lerp(new THREE.Color(night), 1 - day);
          if (dusk) c.lerp(new THREE.Color(dusk), glow);
          return c;
        };
        const g = this.skyCanvas.getContext('2d');
        const grad = g.createLinearGradient(0, 0, 0, 256);
        grad.addColorStop(0, '#' + col('#59616d', '#3f7fd6', '#02040a').getHexString());
        grad.addColorStop(0.55, '#' + col('#8a939e', '#9cc3ea', '#070d1c', '#c77a5a').getHexString());
        grad.addColorStop(1, '#' + col('#aab2bb', '#dfe9f2', '#111a2c', '#f2a25e').getHexString());
        g.fillStyle = grad;
        g.fillRect(0, 0, 4, 256);
        this.skyTex.needsUpdate = true;
        this.scene.fog.color.copy(col('#9aa3ad', '#d4e0ea', '#0b1220', '#d99a72'));
        this.scene.fog.near = 250 - 150 * q;
        this.scene.fog.far = (1600 - 1000 * q) * (0.55 + 0.45 * day);

        // the directional light is the sun by day and a weak bluish moon by night
        if (el > 0) {
          dirFrom(Math.max(el, 3), sun.az, this.sunDir);
          this.sun.intensity = 2.6 * smoothstep(el / 10) * (1 - 0.7 * q);
          this.sun.color.set(0xff8a4a).lerp(new THREE.Color(0xfff1dc), smoothstep(el / 22));
        } else {
          dirFrom(38, 205, this.sunDir);
          this.sun.intensity = 0.35 * (1 - smoothstep((el + 8) / 8)) * (1 - 0.6 * q);
          this.sun.color.set(0x9fb3e0);
        }
        if (this.sky) {
          const u = this.sky.material.uniforms;
          dirFrom(sun.el, sun.az, u.sunPosition.value);
          u.turbidity.value = 1.8 + 8 * q;
          u.rayleigh.value = 1.9 + 1.2 * q + 1.2 * glow;
          u.mieCoefficient.value = 0.003 + 0.01 * q;
          u.cloudCoverage.value = 0.3 + 0.65 * q;
          u.cloudDensity.value = 0.35 + 0.55 * q;
          const eu = this.envSky.material.uniforms;
          for (const k of ['sunPosition', 'turbidity', 'rayleigh', 'mieCoefficient', 'mieDirectionalG', 'cloudCoverage', 'cloudDensity', 'cloudScale']) {
            if (eu[k].value.copy) eu[k].value.copy(u[k].value);
            else eu[k].value = u[k].value;
          }
          this.overcast.material.opacity = 0.8 * q;
          this.envGround.color.set(0x3a4a2c).multiplyScalar((0.15 + 0.85 * day) * 1.6);
          // scene-referred haze: remember the palette colour scaled to sky brightness for rain / night
          this.hazeGrey = this.scene.fog.color.clone().multiplyScalar(9 * (0.03 + 0.97 * day));
          this.hazeWet = Math.max(q, 1 - day);
          this.scene.fog.near = 60 - 40 * q;
          this.scene.fog.far = (4200 - 2500 * q) * (0.45 + 0.55 * day);
          this.updateEnv(true);
          this.applyHaze();
        }
        if (this.csm) {
          this.csm.lightDirection.copy(this.sunDir).negate();
          for (const l of this.csm.lights) {
            l.intensity = this.sun.intensity * this.lightGain * this.sunGain;
            l.color.copy(this.sun.color);
          }
        }
        this.hemi.intensity = (0.1 + 0.5 * day) * (1 + 0.5 * q) * (this.sky ? 0.25 * this.lightGain * (1 - day) : 1);
        this.hemi.color.set(0x24324f).lerp(new THREE.Color(0xcfe3ff), day);
        this.hemi.groundColor.set(0x0b0e12).lerp(new THREE.Color(0x3d5a2a), day);
        this.scene.environmentIntensity = this.sky ? 1 : 0.05 + 0.5 * day;
        this.starMat.opacity = (1 - smoothstep((el + 12) / 8)) * (1 - q) * 0.9;
        this.night = 1 - day;
      }
      const w = this.world;
      if (w && w.skyQ !== q) {
        w.skyQ = q;
        w.mat.asphalt.roughness = 0.92 - 0.6 * q;
        w.mat.asphalt.color.setScalar(1 - 0.45 * q);
        w.mat.asphalt.metalness = 0.15 * q;
      }
      if (w && w.night !== this.night) {
        w.night = this.night;
        const n = this.night;
        if (w.cityMat) w.cityMat.emissiveIntensity = 1.1 * smoothstep(n * 1.4) * this.lightGain;
        if (w.garageMat) w.garageMat.emissiveIntensity = 0.7 * smoothstep(n * 1.4) * this.lightGain;
        if (w.tunnelLamp) w.tunnelLamp.emissiveIntensity = 2.2 * this.lightGain;
        if (w.tunnelWall) w.tunnelWall.emissiveIntensity = this.lightGain;
      }
    }

    // Headlights, tail lights and the pooled beams for the nearest cars.
    updateLights(race) {
      const n = this.night;
      sharedMats().headU.value = (0.05 + 4 * n) * this.lightGain;
      const cam = this.camera.position;
      // reuse a pool of {car,d2} records and sort in place each frame, instead of
      // allocating a fresh array of tuples and a fresh sort comparator every frame
      const pool = this._rankPool;
      let m = 0;
      for (const [car, v] of this.carViews) {
        v.tailBase = 0.25 + 1.4 * n;
        if (car.dnf) continue;
        if (m >= pool.length) pool.push({ car: null, d2: 0 });
        const e = pool[m++];
        e.car = car;
        e.d2 = (car.x - cam.x) ** 2 + (car.y - cam.z) ** 2;
      }
      // cars are already near-sorted frame to frame, so a plain insertion sort settles in ~O(m)
      for (let i = 1; i < m; i++) {
        const cur = pool[i];
        let j = i - 1;
        while (j >= 0 && pool[j].d2 > cur.d2) {
          pool[j + 1] = pool[j];
          j--;
        }
        pool[j + 1] = cur;
      }
      const tr = race.track;
      this.beams.forEach((l, i) => {
        const r = i < m ? pool[i] : null;
        if (!r || n < 0.05 || r.d2 > 180 * 180) {
          l.intensity = 0;
          return;
        }
        const car = r.car;
        const y = this.world.trackY(car.s);
        const ch = Math.cos(car.heading);
        const sh = Math.sin(car.heading);
        l.position.set(car.x + ch * 1.9, y + 0.75, car.y + sh * 1.9);
        l.target.position.set(car.x + ch * 26, this.world.trackY(car.s + 26) - 0.4, car.y + sh * 26);
        l.intensity = (this.sky ? 60 : 90) * n * this.lightGain;
        void tr;
      });
    }

    // world position of a car
    carPos(car, out) {
      const y = this.world.trackY(car.s);
      return out.set(car.x, y, car.y);
    }

    syncCars(race, dt) {
      if (this.race !== race) {
        for (const v of this.carViews.values()) this.scene.remove(v.root);
        this.carViews.clear();
        this.race = race;
        for (const car of race.cars) {
          const v = buildCar(car);
          this.carViews.set(car, v);
          this.scene.add(v.root);
          this.prepareMaterials(v.root);
        }
        this.world.boxMats.forEach((m, i) => {
          const c = race.cars.find((x) => x.box === i);
          m.color.set(c ? c.color : '#888888');
        });
      }
      const tr = race.track;
      for (const [car, v] of this.carViews) {
        v.root.visible = !car.dnf || car.v > 0.1;
        v.root.position.set(car.x, this.world.trackY(car.s), car.y);
        v.root.rotation.y = -car.heading;
        const dh = car.heading - tr.heading(car.s);
        const pitch = Math.atan(tr.sample(tr.GRADE, car.s) * Math.cos(dh));
        const lat = car.v * car.v * tr.curvature(car.s);
        const accel = car.brakeOn ? -1 : car.throttle > 0.3 ? 0.5 : 0;
        v.pitch += (pitch - v.pitch) * Math.min(1, dt * 8);
        v.root.rotation.z = v.pitch;
        if (car.control === 'free' && car.phys) {
          // the physics model's own sprung-body roll and pitch
          v.roll = car.bodyRoll;
          v.body.rotation.x = v.roll;
          v.body.rotation.z = car.bodyPitch;
        } else {
          v.roll += (Math.max(-0.07, Math.min(0.07, -lat * 0.006)) - v.roll) * Math.min(1, dt * 5);
          v.body.rotation.x = v.roll;
          v.body.rotation.z = accel * 0.012;
        }
        if (car.control === 'free' && car.phys) {
          // each wheel turns at its own speed, so lock-ups and wheelspin show
          v.spins = v.spins || [v.spin, v.spin, v.spin, v.spin];
          v.wheels.forEach((w, i) => {
            v.spins[i] -= car.phys.w[i] * dt; // same order as physics: FL, FR, RL, RR
            w.rotation.z = v.spins[i];
          });
        } else {
          v.spin -= ((car.speed != null ? car.speed : car.v) * dt) / 0.277;
          for (const w of v.wheels) w.rotation.z = v.spin;
          v.spins = null;
        }
        const steer = car.control === 'free' ? -(car.steer || 0) : -Math.atan(CAR.wheelbase * tr.curvature(car.s)) * 1.4;
        for (const p of v.steer) p.rotation.y = steer;
        v.tailU.value = (car.brakeOn ? 2.4 + 1.5 * this.night : v.tailBase || 0.25) * this.lightGain;
        const ghost = car.finished && car !== this.focus;
        v.paint.transparent = ghost;
        v.paint.opacity = ghost ? 0.55 : 1;
      }
    }

    updateCamera(focus, dt, mode) {
      if (!this.world) return;
      this.focus = focus;
      const cam = this.camera;
      const p = this._scratch.camP.set(focus.x, this.world.trackY(focus.s), focus.y);
      const snap = this.cam.snap;
      const k = (rate) => (snap ? 1 : 1 - Math.exp(-dt * rate));
      let dh = focus.heading - this.camHead;
      dh = Math.atan2(Math.sin(dh), Math.cos(dh));
      this.camHead += dh * k(mode === 'bonnet' ? 30 : 5);
      const fwd = this._scratch.camFwd.set(Math.cos(this.camHead), 0, Math.sin(this.camHead));
      const v = Math.hypot(focus.vx, focus.vy);
      let fov = 60 + Math.min(14, v * 0.35);
      cam.up.set(0, 1, 0);
      const target = this._scratch.camTarget;
      const want = this._scratch.camWant;
      if (mode === 'tv') {
        const tr = this.world.track;
        if (!this.tv || tr.rel(focus.s - this.tv.s) > 45 || snap) {
          const s = focus.s + 45 + Math.random() * 50;
          const p0 = tr.rel(s);
          const nearPits = p0 > tr.cfg.pitEntry - 60 && p0 < tr.cfg.pitExit + 60;
          const side = nearPits ? -Math.sign(tr.cfg.pitOffset) : Math.random() < 0.5 ? -1 : 1;
          const d = side * (tr.half + tr.cfg.runoff + 3 + Math.random() * 6);
          const q = tr.pos(s, d);
          this.tv = { s, pos: new THREE.Vector3(q.x, this.world.trackY(s) + 3.5 + Math.random() * 5, q.y) };
          this.tv.pos.y = Math.max(this.tv.pos.y, this.world.groundY(q.x, q.y) + 1.8);
        }
        cam.position.copy(this.tv.pos);
        target.copy(p).y += 0.8;
        const dist = cam.position.distanceTo(target);
        fov = THREE.MathUtils.clamp((2 * Math.atan(12 / dist) * 180) / Math.PI, 16, 55);
      } else if (mode === 'bonnet') {
        want.copy(p).addScaledVector(fwd, 0.25).y += 1.3;
        cam.position.copy(want);
        target.copy(p).addScaledVector(fwd, 30);
        target.y = this.world.trackY(focus.s + 30) + 1.0;
        fov += 6;
      } else if (mode === 'top') {
        want.copy(p).y += 55 + v * 0.8;
        cam.position.lerp(want, k(8));
        cam.up.copy(fwd);
        target.copy(p);
        fov = 55;
      } else {
        const far = mode === 'far';
        const dist = far ? 11.5 : 6.2;
        const height = far ? 4.6 : 2.2;
        want.copy(p).addScaledVector(fwd, -dist).y += height;
        const ground = this.world.groundY(want.x, want.z) + 1.0;
        const road = this.world.trackY(focus.s - dist) + height * 0.6;
        want.y = Math.max(want.y, ground, road);
        cam.position.lerp(want, k(far ? 7 : 10));
        target.copy(p).addScaledVector(fwd, far ? 10 : 7).y += far ? 0.6 : 1.0;
      }
      cam.lookAt(target);
      cam.fov += (fov - cam.fov) * k(4);
      cam.updateProjectionMatrix();
      this.cam.snap = false;
    }

    draw(race, focus, opts) {
      this.setTrack(race.track);
      const dt = Math.min(0.1, (performance.now() - (this.lastDraw || performance.now())) / 1000);
      this.lastDraw = performance.now();
      this.paintSky(race.weather.wet * 0.6 + race.weather.rain * 0.4, race.timeOfDay);
      this.syncCars(race, dt);
      this.updateLights(race);
      this.stars.position.copy(this.camera.position);
      const w = this.world;
      w.racingLine.visible = !!opts.racingLine;
      w.updateLod(this.camera.position);
      const now = performance.now() / 1000;
      if (w.mat.sea) w.mat.sea.normalMap.offset.set(now * 0.0021, now * 0.0013);
      const lit = race.phase === 'countdown' ? Math.max(0, Math.min(5, Math.floor(race.clock))) : 0;
      w.lights.forEach((m, i) => (m.emissiveIntensity = i < lit ? 3 * this.lightGain : 0));

      const fp = this._scratch.focusPos.set(focus.x, w.trackY(focus.s), focus.y);
      this.sun.position.copy(fp).addScaledVector(this.sunDir, 200);
      this.sun.target.position.copy(fp);

      const rain = race.weather.rain;
      this.rain.visible = rain > 0.03;
      if (this.rain.visible) {
        const arr = this.rainGeo.attributes.position.array;
        const n = Math.floor(this.rainDrops.length * Math.min(1, rain));
        const c = this.camera.position;
        for (let i = 0; i < this.rainDrops.length; i++) {
          const d = this.rainDrops[i];
          d.y -= dt * 18;
          if (d.y < -4) {
            d.y += 30;
            d.x = (Math.random() - 0.5) * 80;
            d.z = (Math.random() - 0.5) * 80;
          }
          const o = i * 6;
          if (i >= n) {
            arr.fill(0, o, o + 6);
            continue;
          }
          arr[o] = c.x + d.x;
          arr[o + 1] = c.y + d.y - 8;
          arr[o + 2] = c.z + d.z;
          arr[o + 3] = c.x + d.x + 0.15;
          arr[o + 4] = c.y + d.y - 9.1;
          arr[o + 5] = c.z + d.z;
        }
        this.rainGeo.attributes.position.needsUpdate = true;
      }

      if (this.composer) {
        this.sky.material.uniforms.time.value = now;
        this.grade.update(now, this.W / this.H, this.night, race.weather.rain);
        this.csm.updateFrustums();
        this.csm.update();
        this.composer.render(dt);
      } else this.gl.render(this.scene, this.camera);
      this.drawTags(race, focus);
    }

    drawTags(race, focus) {
      const g = this.octx;
      const r = this.odpr;
      g.setTransform(r, 0, 0, r, 0, 0);
      g.clearRect(0, 0, this.W, this.H);
      g.font = '600 11px system-ui, sans-serif';
      g.textAlign = 'center';
      const v = this._scratch.tag;
      for (const car of race.cars) {
        if (car === focus || car.dnf) continue;
        const dx = car.x - focus.x;
        const dy = car.y - focus.y;
        if (dx * dx + dy * dy > 90 * 90) continue;
        v.set(car.x, this.world.trackY(car.s) + 2.1, car.y).project(this.camera);
        if (v.z > 1 || v.z < -1) continue;
        const sx = (v.x * 0.5 + 0.5) * this.W;
        const sy = (-v.y * 0.5 + 0.5) * this.H;
        const mind = car.brain && car.brain.mind;
        const label = `P${car.pos} ${car.name.split(' ').pop()}${mind === 'attack' ? ' ⚔' : mind === 'defend' ? ' 🛡' : ''}`;
        const tw = g.measureText(label).width + 10;
        g.fillStyle = 'rgba(10,12,16,0.62)';
        g.fillRect(sx - tw / 2, sy - 14, tw, 16);
        g.fillStyle = car.color;
        g.fillRect(sx - tw / 2, sy - 14, 3, 16);
        g.fillStyle = '#fff';
        g.fillText(label, sx + 1, sy - 2);
      }
    }
  }

  Renderer3D.MODES = CAMERA_MODES;
  Renderer3D.available = () => !!THREE && webglAvailable();
  SC.Renderer3D = Renderer3D;
})();
