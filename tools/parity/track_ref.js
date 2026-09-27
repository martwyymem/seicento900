// Dumps js/track.js geometry (sampled arrays, sums) and lookups for every track, as the reference for
// godot/tests/test_track.gd.
const SC = require('../harness.js');
const ARRS = ['X', 'Y', 'H', 'GRADE', 'TX', 'TY', 'NX', 'NY', 'ANG', 'KC', 'KP', 'RLD', 'RX', 'RY', 'RDS', 'RK', 'CORNER', 'PROF'];
const out = {};
for (const key of Object.keys(SC.TRACK_CONFIG)) {
  const tr = new SC.Track(key);
  const rand = SC.util.mulberry32(key.length * 31 + 7);
  const t = { n: tr.n, step: tr.step, L: tr.L, hMin: tr.hMin, hMax: tr.hMax, rlLength: tr.rlLength, sectors: tr.sectors,
    bounds: [tr.bounds.minX, tr.bounds.minY, tr.bounds.maxX, tr.bounds.maxY], arrays: {}, sums: {}, lookups: [] };
  for (const a of ARRS) {
    t.arrays[a] = [];
    for (let i = 0; i < tr.n; i += 7) t.arrays[a].push([i, tr[a][i]]);
    t.sums[a] = tr[a].reduce((x, y) => x + Math.abs(y), 0);
  }
  const L = (fn, args, v) => t.lookups.push({ fn, args, v });
  for (let k = 0; k < 150; k++) {
    const s = (rand() * 1.4 - 0.2) * tr.L;
    const d = (rand() - 0.5) * 2 * (tr.half + tr.cfg.runoff + 4);
    L('sample_prof', [s], tr.sample(tr.PROF, s));
    L('sample_rld', [s], tr.sample(tr.RLD, s));
    L('pos', [s, d], [tr.pos(s, d).x, tr.pos(s, d).y]);
    L('heading', [s], tr.heading(s));
    L('s_rate', [s, d], tr.sRate(s, d));
    L('rel', [s], tr.rel(s));
    L('clamp_d', [s, d], tr.clampD(s, d));
    L('pit_blend', [s], tr.pitBlend(s));
    const lim = tr.limits(s);
    L('limits', [s], [lim.lo, lim.hi]);
    L('sector_name', [s], tr.sectorName(s));
    const p = tr.pos(s, d);
    const px = p.x + (rand() - 0.5) * 3, py = p.y + (rand() - 0.5) * 3;
    const a = tr.project(px, py, s + (rand() - 0.5) * 20);
    L('project_hint', [px, py, s], [a.s, a.d, a.dist]);
    if (k % 10 === 0) {
      const b = tr.project(px, py);
      L('project', [px, py], [b.s, b.d, b.dist]);
    }
  }
  for (const s of [-500, -1e-9, 0, tr.L - 1e-9, tr.L, tr.L * 2.5]) L('pos', [s, 1.5], [tr.pos(s, 1.5).x, tr.pos(s, 1.5).y]);
  out[key] = t;
}
// PRNG stream
const r = SC.util.mulberry32(123456789);
const rng = [];
for (let i = 0; i < 50; i++) rng.push(r());
out._rng = { seed: 123456789, values: rng };
const r2 = SC.util.mulberry32(-5);
out._rng2 = { seed: -5, values: Array.from({ length: 20 }, () => r2()) };
require('fs').writeFileSync(require('path').join(__dirname, '../../godot/tests/ref/track.json'), JSON.stringify(out));
console.log('track reference written');
