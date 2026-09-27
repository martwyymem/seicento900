// Menus, HUD, input and the main loop.
(function () {
  'use strict';
  const SC = window.SC;
  const T = SC.Tyres;
  const S = SC.Strategy;
  const $ = (q) => document.querySelector(q);
  const $$ = (q) => Array.from(document.querySelectorAll(q));

  const DEFAULTS = {
    track: 'gp', laps: 6, opponents: 15, difficulty: 'medium', grid: 'middle', weather: 'dry',
    wearMult: 2, fuelMult: 1, crew: 'club', mandatoryStop: true, twoCompounds: false, refuel: true,
    parallel: false, collisions: true, playerName: 'You', playerNumber: 9, playerColor: '#b3121d',
    stripes: true, racingLine: true, autoStrategist: true, cameraRotate: true, gearbox: 'auto', assists: 'full', aiLearning: 'on',
    graphics: '3d', quality: 'high', camera3d: 'chase', format: 'laps', hours: 1, startHour: 14, series: 'single',
  };
  // sensible race length and tyre wear when switching tracks
  const TRACK_DEFAULTS = {
    gp: { laps: 6, wearMult: 2 },
    nordschleife: { laps: 2, wearMult: 1 },
    monaco: { laps: 8, wearMult: 2 },
    indy: { laps: 12, wearMult: 2 },
    lemans: { laps: 2, wearMult: 1 },
    monza: { laps: 6, wearMult: 2 },
    silverstone: { laps: 6, wearMult: 2 },
    spa: { laps: 5, wearMult: 2 },
  };
  // championship: one race per circuit, F1-style points for the top ten
  const CALENDAR = ['monza', 'silverstone', 'spa', 'gp', 'monaco', 'indy', 'lemans', 'nordschleife'];
  const POINTS = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];
  const WARPS = [1, 2, 5, 10, 30, 60];
  const COLORS = ['#b3121d', '#f3c300', '#1c3f94', '#2e6b3f', '#f2f2f2', '#1a1a1a', '#5fa8d3', '#ff7a1a', '#7a1f5c'];
  const STRATEGY_KEYS = new Set(['track', 'laps', 'weather', 'wearMult', 'fuelMult', 'crew', 'mandatoryStop', 'twoCompounds', 'refuel', 'parallel', 'format', 'hours']);
  const STEP = 1 / 120;

  let settings = load();
  const renderer2d = new SC.Renderer($('#game'));
  let renderer3d = null;
  if (SC.Renderer3D && SC.Renderer3D.available()) {
    try {
      renderer3d = new SC.Renderer3D($('#game3d'), $('#overlay'), settings.quality);
    } catch (e) {
      console.warn('3D unavailable, using 2D', e);
    }
  }
  const minimap = new SC.Minimap($('#minimap'));
  let renderer = renderer2d;
  function pickRenderer() {
    const want3d = settings.graphics === '3d' && renderer3d;
    renderer = want3d ? renderer3d : renderer2d;
    $('#game').classList.toggle('hidden', !!want3d);
    $('#game3d').classList.toggle('hidden', !want3d);
    $('#overlay').classList.toggle('hidden', !want3d);
    renderer.cam.snap = true;
  }
  const is3d = () => renderer === renderer3d;
  const camMode = (race) => (is3d() ? settings.camera3d : settings.cameraRotate);
  const audio = new SC.EngineAudio();
  let mode = 'menu';
  let race = null;
  let options = [];
  let chosen = { kind: 'option', index: 0 };
  let custom = null;
  let currentPlan = null;
  let champ = loadChamp();
  let acc = 0;
  let hudT = 0;
  let lastEventSeen = 0;
  let warp = 1;
  const keys = {};
  const input = { throttle: 0, brake: 0, steer: 0, shiftUp: false, shiftDown: false };
  const pad = { active: false, steer: 0, throttle: 0, brake: 0, prev: [] };

  function load() {
    try {
      return Object.assign({}, DEFAULTS, JSON.parse(localStorage.getItem('seicento-settings') || '{}'));
    } catch (e) {
      return Object.assign({}, DEFAULTS);
    }
  }
  function save() {
    localStorage.setItem('seicento-settings', JSON.stringify(settings));
  }
  // the championship survives reloads: { round, scored, table: { carId: { id, name, color, number, isPlayer, points, wins } } }
  function loadChamp() {
    try {
      const c = JSON.parse(localStorage.getItem('seicento-championship'));
      return c && c.table && c.round >= 0 && c.round < CALENDAR.length ? c : null;
    } catch (e) {
      return null;
    }
  }
  function saveChamp() {
    if (champ) localStorage.setItem('seicento-championship', JSON.stringify(champ));
    else localStorage.removeItem('seicento-championship');
  }
  // the round to drive next: a round whose results were already seen is done
  function nextRound() {
    return champ.scored ? champ.round + 1 : champ.round;
  }

  // ---------------- menu ----------------
  function bindMenu() {
    $$('.seg[data-key]').forEach((seg) => {
      const key = seg.dataset.key;
      seg.querySelectorAll('button[data-v]').forEach((b) =>
        b.addEventListener('click', () => {
          if (key === 'track' && settings.track !== b.dataset.v) {
            // e.g. a 20.7 km Nordschleife lap needs a shorter race and gentler tyre wear
            Object.assign(settings, TRACK_DEFAULTS[b.dataset.v]);
          }
          if (key === 'format' && b.dataset.v === 'time' && settings.format !== 'time') {
            // endurance: refuelling on, and tyres that last a stint
            Object.assign(settings, { refuel: true, wearMult: Math.min(settings.wearMult, 1) });
          }
          settings[key] = b.dataset.v !== '' && !isNaN(+b.dataset.v) ? +b.dataset.v : b.dataset.v;
          changed(key);
        })
      );
    });
    $$('input[data-key]').forEach((inp) => {
      const key = inp.dataset.key;
      inp.addEventListener(inp.type === 'checkbox' ? 'change' : 'input', () => {
        if (inp.type === 'checkbox') settings[key] = inp.checked;
        else if (inp.type === 'range' || inp.type === 'number') {
          if (inp.value === '') return;
          settings[key] = Number(inp.value);
        } else settings[key] = inp.value;
        changed(key);
      });
    });
    const sw = $('#swatches');
    for (const c of COLORS) {
      const b = document.createElement('button');
      b.style.background = c;
      b.dataset.c = c;
      b.title = c;
      b.addEventListener('click', () => {
        settings.playerColor = c;
        changed('playerColor');
      });
      sw.appendChild(b);
    }
    const picker = document.createElement('input');
    picker.type = 'color';
    picker.title = 'Custom colour';
    picker.addEventListener('input', () => {
      settings.playerColor = picker.value;
      changed('playerColor');
    });
    sw.appendChild(picker);
    $$('[data-go]').forEach((b) => b.addEventListener('click', () => go(b.dataset.go)));
    $('#champ-reset').addEventListener('click', () => {
      if (!champ || !confirm('Discard the saved championship standings?')) return;
      champ = null;
      saveChamp();
      syncMenu();
    });
    $('#strat-add').addEventListener('click', () => {
      const base = editorStints();
      const last = base[base.length - 1] || { c: 'M', laps: 1 };
      setCustom(base.concat([{ c: last.c, laps: 1 }]));
    });
    $$('[data-act]').forEach((b) => b.addEventListener('click', () => action(b.dataset.act)));
  }

  function syncMenu() {
    $$('.seg[data-key]').forEach((seg) => {
      seg.querySelectorAll('button[data-v]').forEach((b) => b.classList.toggle('on', b.dataset.v === String(settings[seg.dataset.key])));
    });
    $$('input[data-key]').forEach((inp) => {
      const v = settings[inp.dataset.key];
      if (inp.type === 'checkbox') inp.checked = !!v;
      else if (document.activeElement !== inp) inp.value = v;
    });
    $$('output[data-for]').forEach((o) => {
      const k = o.dataset.for;
      o.textContent = k === 'wearMult' || k === 'fuelMult' ? '×' + Number(settings[k]).toFixed(1) : settings[k];
    });
    $$('#swatches button').forEach((b) => b.classList.toggle('on', b.dataset.c === settings.playerColor));
    const resume = champ && nextRound() < CALENDAR.length;
    $('#champ-info').textContent =
      `${CALENDAR.length} rounds, one on each circuit, ${POINTS.join('-')} points. Race length and tyre wear are set per circuit and the strategist plans every round.` +
      (resume ? ` Saved championship: next is round ${nextRound() + 1}, ${SC.getTrack(CALENDAR[nextRound()]).name}.` : '');
    $('#champ-reset').classList.toggle('disabled', !champ);
    $('#champ-go').textContent = resume ? `Continue championship · round ${nextRound() + 1}` : 'Start championship';
    $('#strat-custom').classList.toggle('hidden', raceLaps() > S.LONG_RACE);
    $('input[data-key=laps]').max = settings.track === 'indy' ? 200 : 60;
    aiMemory();
    drawPreview();
    champSide();
  }

  // the championship page's side panel: calendar with progress, then the saved standings
  function champSide() {
    const done = champ ? nextRound() : 0;
    $('#champ-cal').innerHTML = CALENDAR.map((t, i) =>
      `<div class="cal${i < done ? ' done' : i === done ? ' next' : ''}"><span>${i + 1}</span>${SC.getTrack(t).name}</div>`).join('');
    const table = champ ? Object.values(champ.table).sort((a, b) => b.points - a.points || b.wins - a.wins || a.id - b.id) : [];
    $('#champ-standings').innerHTML = table.length
      ? '<table>' + table.map((e, i) =>
        `<tr class="${e.isPlayer ? 'me' : ''}"><td>${i + 1}</td><td><span class="sw" style="background:${e.color}"></span>${e.name}</td><td><b>${e.points}</b></td></tr>`).join('') + '</table>'
      : '<p class="hint">No rounds driven yet.</p>';
  }

  // what the learning AI remembers about you on the selected track
  function aiMemory() {
    const el = $('#ai-memory');
    if (!el || !SC.Brain) return;
    const m = SC.Brain.summary(settings.track);
    const name = SC.getTrack(settings.track).cfg.short || SC.getTrack(settings.track).name;
    if (settings.aiLearning === 'off') el.textContent = 'Every bot drives one fixed pace, and nothing is learned.';
    else if (!m || !m.laps) el.textContent = `The bots haven't seen you drive at ${name} yet. They learn from every lap you drive yourself.`;
    else
      el.innerHTML =
        `The field has studied ${m.laps} of your laps at ${name} (${m.sections} corners mapped` +
        (m.pace ? `, your pace ≈ ${(m.pace * 100).toFixed(1)} % of the limit` : '') +
        `). You block ${Math.round((m.block || 0) * 100)} % of attacks${m.rough > 0.3 ? ' and race rough' : ''}.` +
        `<button class="link" id="ai-forget">Forget</button>`;
  }

  function changed(key) {
    save();
    syncMenu();
    if (STRATEGY_KEYS.has(key)) {
      custom = null;
      chosen = { kind: 'option', index: 0 };
      refreshStrategy();
    }
    if (key === 'series') renderEditor();
    if (key === 'graphics') pickRenderer();
    // the WebGL pipeline is set up once, so a new quality level needs a fresh page; come back to the same page
    if (key === 'quality') {
      sessionStorage.setItem('seicento-page', fePage ? fePage.id : '');
      location.reload();
    }
  }

  function drawPreview() {
    const c = $('#car-preview');
    const g = c.getContext('2d');
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, c.width, c.height);
    const k = c.width / 5.5;
    g.setTransform(k, 0, 0, k, c.width / 2, c.height / 2);
    SC.drawSeicento(g, { x: 0, y: 0, heading: 0, color: settings.playerColor, number: settings.playerNumber, stripes: settings.stripes }, 1);
  }

  // laps the strategist plans for: the lap count, or the expected laps of a timed race
  function raceLaps() {
    const track = SC.getTrack(settings.track);
    return settings.format === 'time' ? S.estimateLaps(track, settings.hours * 3600, settings) : settings.laps;
  }

  function planOpts(track, extra) {
    return Object.assign(
      {
        track, laps: raceLaps(), wet: settings.weather === 'wet' ? 0.85 : 0,
        wearMult: settings.wearMult, fuelMult: settings.fuelMult,
        rules: { mandatoryStop: settings.mandatoryStop, twoCompounds: settings.twoCompounds, refuel: settings.refuel },
        crew: settings.crew, parallel: settings.parallel,
      },
      extra
    );
  }

  const badge = (c, big) => `<span class="ty${big ? ' big' : ''}" style="--c:${T.COMPOUNDS[c].color}">${c}</span>`;
  const stintHtml = (stints) =>
    stints.map((st) => `${badge(st.c)}<b>${st.laps}</b>`).join('<span class="arrow">→</span>');

  function refreshStrategy() {
    const track = SC.getTrack(settings.track);
    const cal = S.calibrate(track);
    const po = planOpts(track);
    options = S.plan(Object.assign({}, po, { diverse: true })).slice(0, 7);
    const fpl = cal.fuelPerLap * settings.fuelMult;
    const lives = T.COMPOUND_KEYS.map((c) => [c, S.tyreLifeLaps(track, c, po.wet, settings.wearMult)]);
    const lap = S.lapTime(cal, T.compoundGrip('M', po.wet) * 0.95 * 0.95, SC.Car.massWithFuel(10));
    const typicalStop = cal.pitDriveLoss + S.serviceTime(settings.crew, settings.parallel, true, settings.refuel ? fpl * 3 : 0);
    let html =
      `Lap ≈ <b>${SC.fmtTime(lap)}</b> · fuel <b>${fpl.toFixed(2)} L</b>/lap (tank ${SC.Car.CAR.tank} L = ${(SC.Car.CAR.tank / fpl).toFixed(1)} laps)` +
      ` · pit stop ≈ <b>${typicalStop.toFixed(0)} s</b>` +
      `<div class="lives">Tyre life: ${lives.map(([c, l]) => `<span>${badge(c)} ${l.toFixed(1)} laps</span>`).join('')}</div>`;
    if (!options.length) {
      let why = 'No plan satisfies these rules.';
      if (lives.every(([, l]) => l < 1)) why = 'No tyre survives a single lap — lower the tyre wear.';
      else if (!settings.refuel && S.fuelNeed(po.laps, fpl) > SC.Car.CAR.tank)
        why = `Without refuelling the race needs ${S.fuelNeed(po.laps, fpl).toFixed(1)} L — more than the ${SC.Car.CAR.tank} L tank.`;
      html += `<div class="warn">⚠ ${why}</div>`;
    }
    if (settings.format === 'time') {
      $('#race-length').textContent = `${fmtHours(settings.hours)} race ≈ ${po.laps} laps · ${Math.round((po.laps * track.L) / 1000)} km — winner is whoever leads when the clock runs out`;
    } else {
      const mins = (settings.laps * lap * 1.02) / 60;
      $('#race-length').textContent = `≈ ${mins < 90 ? Math.round(mins) + ' min' : (mins / 60).toFixed(1) + ' h'} · ${((settings.laps * track.L) / 1000).toFixed(1)} km`;
    }
    if (options[0] && options[0].horizon)
      html += `<div class="hint">Endurance: the strategist plans the next ${options[0].horizon} laps and keeps extending the plan (≈ ${Math.round((po.laps / options[0].horizon) * options[0].stops)} stops in all).</div>`;
    $('#strat-info').innerHTML = html;

    const list = $('#strat-list');
    list.innerHTML = '';
    options.forEach((o, i) => {
      const b = document.createElement('button');
      b.className = 'opt' + (chosen.kind === 'option' && chosen.index === i ? ' on' : '');
      const delta = o.time - options[0].time;
      const shown = o.stints.length > 7 ? o.stints.slice(0, 6) : o.stints;
      b.innerHTML =
        `<div class="stints">${stintHtml(shown)}${shown.length < o.stints.length ? `<span class="arrow">→ … ${o.stints.length - 6} more</span>` : ''}</div>` +
        `<div class="t">${i === 0 ? SC.fmtTime(o.time).replace(/\.\d+$/, '') : '+' + delta.toFixed(1) + ' s'}<small>${o.stops} stop${o.stops === 1 ? '' : 's'}</small></div>` +
        `<div class="lbl">${i === 0 ? 'Fastest on paper · ' : ''}start ${o.stints[0].fuel.toFixed(1)} L</div>`;
      b.addEventListener('click', () => {
        chosen = { kind: 'option', index: i };
        custom = null;
        refreshStrategy();
      });
      list.appendChild(b);
    });
    renderEditor();
  }

  function editorStints() {
    if (chosen.kind === 'custom' && custom) return custom.map((s) => ({ c: s.c, laps: s.laps }));
    const o = options[chosen.index];
    return o ? o.stints.map((s) => ({ c: s.c, laps: s.laps })) : [{ c: settings.weather === 'wet' ? 'W' : 'M', laps: raceLaps() }];
  }

  function setCustom(stints) {
    custom = stints;
    chosen = { kind: 'custom' };
    $$('#strat-list .opt').forEach((b) => b.classList.remove('on'));
    renderEditor();
  }

  function renderEditor() {
    const stints = editorStints();
    const box = $('#strat-stints');
    box.innerHTML = '';
    stints.forEach((st, k) => {
      const row = document.createElement('div');
      row.className = 'stint-row';
      row.innerHTML =
        `<span class="k">${k + 1}.</span>` +
        `<select>${T.COMPOUND_KEYS.map((c) => `<option value="${c}"${c === st.c ? ' selected' : ''}>${T.COMPOUNDS[c].name}</option>`).join('')}</select>` +
        `<input type="number" min="1" max="${raceLaps()}" value="${st.laps}">` +
        `<button title="Remove stint">✕</button>`;
      const [sel, num, del] = [row.querySelector('select'), row.querySelector('input'), row.querySelector('button')];
      sel.addEventListener('change', () => {
        const s2 = editorStints();
        s2[k].c = sel.value;
        setCustom(s2);
      });
      num.addEventListener('change', () => {
        const s2 = editorStints();
        s2[k].laps = Math.max(1, Math.round(Number(num.value) || 1));
        setCustom(s2);
      });
      del.addEventListener('click', () => {
        const s2 = editorStints();
        if (s2.length > 1) s2.splice(k, 1);
        setCustom(s2);
      });
      box.appendChild(row);
    });

    const ev = $('#strat-eval');
    const track = SC.getTrack(settings.track);
    if (chosen.kind === 'custom') {
      const res = S.evaluate(planOpts(track), stints);
      if (res.errors.length) {
        ev.innerHTML = res.errors.map((e) => `<div class="err">⚠ ${e}</div>`).join('');
        currentPlan = null;
      } else {
        const best = options[0] ? options[0].time : res.time;
        ev.innerHTML = `<div class="ok">✓ Valid · est. ${SC.fmtTime(res.time).replace(/\.\d+$/, '')} (${res.time - best >= 0 ? '+' : ''}${(res.time - best).toFixed(1)} s vs best)</div>`;
        currentPlan = res;
      }
    } else {
      ev.innerHTML = options.length ? '<span class="hint">Edit any stint to build your own plan.</span>' : '';
      currentPlan = options[chosen.index] || null;
    }
    ['#r-go-single', '#r-go-endurance'].forEach((q) => $(q).classList.toggle('disabled', !currentPlan));
    $('#plan-val').textContent =
      chosen.kind === 'custom' ? (currentPlan ? 'Custom plan' : 'Custom plan (invalid)')
      : options.length ? `${chosen.index === 0 ? 'Fastest' : 'Option ' + (chosen.index + 1)} · ${options[chosen.index].stops} stop${options[chosen.index].stops === 1 ? '' : 's'}`
      : 'No valid plan';
  }

  // step through the strategist's plans from the keyboard
  function planStep(dir) {
    if (!options.length) return;
    const i = chosen.kind === 'option' ? chosen.index : -1;
    chosen = { kind: 'option', index: (i + dir + options.length) % options.length };
    custom = null;
    refreshStrategy();
  }

  // ---------------- race lifecycle ----------------
  function startRace() {
    let rs = Object.assign({}, settings);
    let plan = currentPlan;
    if (settings.series === 'championship') {
      if (champ && nextRound() >= CALENDAR.length) champ = null;
      if (!champ) champ = { round: 0, scored: false, table: {} };
      if (champ.scored) champ = Object.assign(champ, { round: champ.round + 1, scored: false });
      saveChamp();
      const t = CALENDAR[champ.round];
      rs = Object.assign(rs, TRACK_DEFAULTS[t], { track: t, format: 'laps' });
      plan = S.plan(planOpts(SC.getTrack(t), { laps: rs.laps, wearMult: rs.wearMult }))[0];
    }
    if (!plan) return;
    race = new SC.Race(rs, plan);
    race.player.stripes = settings.stripes;
    lastEventSeen = 0;
    warp = 1;
    acc = 0;
    input.throttle = input.brake = input.steer = 0;
    showScreen(null);
    $('#hud').classList.remove('hidden');
    $('#help').classList.remove('hidden');
    mode = 'race';
    renderer.cam.snap = true;
    audio.start();
  }

  function showScreen(id) {
    ['#front', '#pause', '#results'].forEach((q) => $(q).classList.toggle('hidden', q !== id));
    listSel = 0;
    if (id === '#pause' || id === '#results') listMove(0);
  }

  // start from a page: each page decides what kind of race it starts
  function go(kind) {
    if (kind !== 'championship' && !currentPlan) return;
    feEnter(kind);
    startRace();
  }

  function action(act) {
    if (act === 'resume') {
      showScreen(null);
      mode = 'race';
    } else if (act === 'restart') {
      startRace();
    } else if (act === 'retire') {
      race.player.dnf = true;
      race.player.dnfReason = 'Retired';
      showScreen(null);
      mode = 'skipping';
    } else if (act === 'next') {
      startRace();
    } else if (act === 'menu') {
      race = null;
      mode = 'menu';
      $('#hud').classList.add('hidden');
      showScreen('#front');
      audio.update({ rpm: 0, throttle: 0, understeer: 0, slip: 0 }, false);
      refreshStrategy();
      syncMenu();
      feClose();
      feClock = 0;
    }
  }

  // ---------------- front end (rally-game style: word carousel along the bottom, one page per word) ----------------
  // Every word opens its own page; a page is an ordered list of rows taken from #fe-pool plus an optional side panel.
  const FE = [
    { id: 'championship', word: 'championship', title: 'Championship', side: 'side-standings',
      rows: ['r-champ-info', 'r-opponents', 'r-difficulty', 'r-grid', 'r-weather', 'r-start', 'r-go-champ', 'champ-reset'],
      desc: () => (champ && nextRound() < CALENDAR.length ? `Saved championship: round ${nextRound() + 1} of ${CALENDAR.length} is next.` : `${CALENDAR.length} rounds, one on each circuit, with F1-style points.`) },
    { id: 'single', word: 'single race', title: 'Single Race', side: 'side-strategy',
      rows: ['r-track', 'r-laps', 'r-length', 'r-weather', 'r-start', 'r-opponents', 'r-difficulty', 'r-grid', 'r-plan', 'r-go-single'],
      desc: () => 'One race over a set number of laps: your circuit, your weather, your pit plan.' },
    { id: 'endurance', word: 'endurance', title: 'Endurance', side: 'side-strategy',
      rows: ['r-track', 'r-hours', 'r-length', 'r-start', 'r-weather', 'r-opponents', 'r-difficulty', 'r-grid', 'r-plan', 'r-go-endurance'],
      desc: () => 'Race the clock instead of the lap count, up to a full 24 hours through the night.' },
    { id: 'garage', word: 'garage', title: 'Garage', side: 'side-car',
      rows: ['r-name', 'r-number', 'r-colour', 'r-stripes', 'r-gearbox', 'r-assists'],
      desc: () => 'Your Seicento: name, number, colours, gearbox and driving aids.' },
    { id: 'rules', word: 'rules', title: 'Rules & Pit Lane',
      rows: ['r-wear', 'r-fuel', 'r-crew', 'r-mandatory', 'r-two', 'r-refuel', 'r-parallel', 'r-contact'],
      desc: () => 'Tyre wear, fuel burn, pit crew and the sporting regulations.' },
    { id: 'options', word: 'options', title: 'Options',
      rows: ['r-graphics', 'r-quality', 'r-line', 'r-strategist', 'r-ai', 'r-aimem'],
      desc: () => 'Graphics, on-track helpers and the learning AI.' },
    { id: 'controls', word: 'controls', title: 'Controls',
      rows: ['k-drive', 'k-steer', 'k-gear', 'k-pit', 'k-service', 'k-replan', 'k-cam', 'k-line', 'k-warp', 'k-misc', 'k-pad'],
      desc: () => 'Keyboard and gamepad.' },
  ];
  const COPIES = 5; // the strip repeats so the carousel can wrap forever
  let feIdx = 0;
  let feVirt = 2 * FE.length;
  let fePage = null;
  let feRow = 0;
  let feClock = 0;

  // entering a page sets up the kind of race it's about, so each word really is its own mode
  function feEnter(id) {
    if (id === 'championship') settings.series = 'championship';
    else if (id === 'single' || id === 'endurance') {
      settings.series = 'single';
      const fmt = id === 'endurance' ? 'time' : 'laps';
      if (fmt === 'time' && settings.format !== 'time') Object.assign(settings, { refuel: true, wearMult: Math.min(settings.wearMult, 1) });
      if (settings.format !== fmt) {
        settings.format = fmt;
        changed('format');
        return;
      }
    } else return;
    save();
    syncMenu();
  }

  function bindFront() {
    const strip = $('#fe-strip');
    for (let c = 0; c < COPIES; c++)
      FE.forEach((it, i) => {
        const b = document.createElement('button');
        b.className = 'fe-item';
        b.textContent = it.word;
        b.addEventListener('click', () => {
          const v = c * FE.length + i;
          if (v === feVirt) feOpen();
          else {
            feClose();
            feGo(v - feVirt);
          }
        });
        strip.appendChild(b);
      });
    strip.addEventListener('transitionend', () => {
      // after sliding, jump back to the middle copy so there is always room either side
      const n = FE.length;
      if (feVirt >= n && feVirt < (COPIES - 1) * n) return;
      feVirt = 2 * n + feIdx;
      feLayout(false);
    });
    $$('#fe-pool .seg.cycle').forEach((seg) => {
      const row = seg.closest('.row');
      const mk = (d, t) => {
        const a = document.createElement('span');
        a.className = 'cyc';
        a.textContent = t;
        a.addEventListener('click', () => rowAdjust(row, d));
        return a;
      };
      seg.prepend(mk(-1, '◂'));
      seg.append(mk(1, '▸'));
    });
    $$('#fe-pool .row.nav').forEach((row) => {
      row.addEventListener('mouseenter', () => {
        const rows = feRows();
        if (rows.includes(row)) feFocus(rows.indexOf(row));
      });
    });
    // text fields: Enter or Esc hands the keyboard back to the menu
    $$('#fe-pool input[type=text], #fe-pool input[type=number]').forEach((inp) =>
      inp.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === 'Escape') {
          e.stopPropagation();
          inp.blur();
        }
      })
    );
    window.addEventListener('resize', () => feLayout(false));
    const back = sessionStorage.getItem('seicento-page');
    sessionStorage.removeItem('seicento-page');
    const k = FE.findIndex((it) => it.id === back);
    if (k >= 0) {
      feIdx = k;
      feVirt = 2 * FE.length + k;
    }
    feLayout(false);
    if (k >= 0) feOpen();
  }

  function feLayout(animate) {
    const strip = $('#fe-strip');
    const items = strip.children;
    Array.from(items).forEach((b, v) => b.classList.toggle('on', v === feVirt));
    strip.style.transition = animate ? '' : 'none';
    strip.style.transform = `translateX(${Math.round(window.innerWidth * 0.16 - items[feVirt].offsetLeft)}px)`;
    if (!animate) void strip.offsetWidth;
    strip.style.transition = '';
    const it = FE[feIdx];
    $('#fe-desc').textContent = fePage ? '' : it.desc();
    $('#fe-page-title').textContent = fePage ? fePage.title : '';
    $('#fe-hint').innerHTML = fePage
      ? '<b>↑ ↓</b> choose &nbsp; <b>◂ ▸</b> change &nbsp; <b>Enter</b> select &nbsp; <b>Esc</b> back to the main menu'
      : 'Press <b>Enter</b> to make selection. &nbsp; <b>◂ ▸</b> browse';
  }

  function feGo(d) {
    feVirt += d;
    feIdx = ((feVirt % FE.length) + FE.length) % FE.length;
    feLayout(true);
  }

  function feOpen() {
    const it = FE[feIdx];
    fePage = it;
    feEnter(it.id);
    const rows = $('#fe-page .fe-rows');
    const side = $('#fe-page .fe-side');
    it.rows.forEach((id) => rows.appendChild($('#' + id)));
    if (it.side) side.appendChild($('#' + it.side));
    $('#fe-page').classList.toggle('no-side', !it.side);
    $('#fe-page').classList.remove('hidden');
    $('#front').classList.add('paged');
    feRow = 0;
    feFocus(0);
    feLayout(false);
  }

  function feClose() {
    if (!fePage) return;
    const pool = $('#fe-pool');
    $$('#fe-page .fe-rows > *, #fe-page .fe-side > *').forEach((el) => pool.appendChild(el));
    $$('#fe-pool .row.focus').forEach((r) => r.classList.remove('focus'));
    fePage = null;
    $('#fe-page').classList.add('hidden');
    $('#front').classList.remove('paged');
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    feLayout(false);
  }

  const feRows = () => $$('#fe-page .fe-rows > .row.nav').filter((r) => !r.classList.contains('hidden'));

  function feFocus(i) {
    const rows = feRows();
    if (!rows.length) return;
    feRow = (i + rows.length) % rows.length;
    rows.forEach((r, k) => r.classList.toggle('focus', k === feRow));
    rows[feRow].scrollIntoView({ block: 'nearest' });
  }

  // ◂ ▸ on a row: step a choice, slider, switch, swatch or plan
  function rowAdjust(row, dir) {
    if (row.id === 'r-plan') return planStep(dir);
    if (row.id === 'r-colour') {
      const i = COLORS.indexOf(settings.playerColor);
      settings.playerColor = COLORS[(i + dir + COLORS.length) % COLORS.length];
      return changed('playerColor');
    }
    const seg = row.querySelector('.seg[data-key]');
    if (seg) {
      const bs = Array.from(seg.querySelectorAll('button[data-v]'));
      const i = bs.findIndex((b) => b.classList.contains('on'));
      return bs[(i + dir + bs.length) % bs.length].click();
    }
    const chk = row.querySelector('input[type=checkbox]');
    if (chk) return chk.click();
    const inp = row.querySelector('input[type=range], input[type=number]');
    if (inp) {
      if (dir > 0) inp.stepUp();
      else inp.stepDown();
      inp.dispatchEvent(new Event('input'));
    }
  }

  function rowActivate(row) {
    if (row.classList.contains('act')) return row.classList.contains('disabled') ? null : row.click();
    const txt = row.querySelector('input[type=text], input[type=number]');
    if (txt) {
      txt.focus();
      return txt.select();
    }
    rowAdjust(row, 1);
  }

  function feKey(e) {
    const k = e.code;
    const left = k === 'ArrowLeft' || k === 'KeyA';
    const right = k === 'ArrowRight' || k === 'KeyD';
    const enter = k === 'Enter' || k === 'Space';
    if (!fePage) {
      if (left) feGo(-1);
      else if (right) feGo(1);
      else if (enter || k === 'ArrowDown') feOpen();
      return;
    }
    const rows = feRows();
    if (k === 'Escape' || k === 'Backspace') feClose();
    else if (k === 'ArrowDown' || k === 'KeyS') feFocus(feRow + 1);
    else if (k === 'ArrowUp' || k === 'KeyW') feFocus(feRow - 1);
    else if (!rows[feRow]) return;
    else if (left || right) rowAdjust(rows[feRow], left ? -1 : 1);
    else if (enter) rowActivate(rows[feRow]);
  }

  // pause / results: ↑ ↓ and Enter over the buttons
  let listSel = 0;
  function listMove(d) {
    const scr = !$('#pause').classList.contains('hidden') ? '#pause' : '#results';
    const bs = $$(scr + ' .modal button').filter((b) => !b.classList.contains('hidden'));
    if (!bs.length) return null;
    listSel = (listSel + d + bs.length) % bs.length;
    bs.forEach((b, i) => b.classList.toggle('sel', i === listSel));
    return bs[listSel];
  }

  // ---------------- the track drawn in type, like an old rally game's front end ----------------
  const artCache = {};
  function artTrack(key) {
    if (artCache[key]) return artCache[key];
    const tr = SC.getTrack(key);
    const M = Math.min(260, Math.max(150, Math.round(tr.L / 45)));
    const xs = [], ys = [], hs = [];
    for (let k = 0; k < M; k++) {
      const i = Math.floor((k / M) * tr.n);
      xs.push(tr.X[i]);
      ys.push(tr.Y[i]);
      hs.push(tr.H[i]);
    }
    const mx = xs.reduce((a, b) => a + b) / M;
    const my = ys.reduce((a, b) => a + b) / M;
    let sxx = 0, syy = 0, sxy = 0;
    for (let k = 0; k < M; k++) {
      const dx = xs[k] - mx, dy = ys[k] - my;
      sxx += dx * dx; syy += dy * dy; sxy += dx * dy;
    }
    // lay the long axis of the circuit across the screen
    const a0 = 0.5 * Math.atan2(2 * sxy, sxx - syy);
    const c = Math.cos(-a0), s = Math.sin(-a0);
    const px = [], pz = [];
    for (let k = 0; k < M; k++) {
      const dx = xs[k] - mx, dy = ys[k] - my;
      px.push(dx * c - dy * s);
      pz.push(dx * s + dy * c);
    }
    const ext = Math.max(...px.map(Math.abs), ...pz.map(Math.abs) .map((v) => v * 1.6)) || 1;
    const hMin = Math.min(...hs), hMax = Math.max(...hs);
    const lift = Math.min(0.22, ((hMax - hMin) / ext) * 5) / (hMax - hMin || 1);
    const words = tr.sectors.map((x) => x[1]).filter((v, i, a) => a.indexOf(v) === i);
    const text = (words.length ? words.join(' ') : tr.name).toLowerCase().replace(/\s+/g, ' ') + ' ';
    return (artCache[key] = {
      M, text, name: tr.name, L: tr.L,
      x: px.map((v) => v / ext), z: pz.map((v) => v / ext), h: hs.map((v) => (v - hMin) * lift),
    });
  }

  function artKey() {
    const id = (fePage || FE[feIdx]).id;
    return id === 'championship' ? CALENDAR[Math.min(champ ? nextRound() : 0, CALENDAR.length - 1)] : settings.track;
  }

  function drawFront(dt) {
    feClock += dt;
    const m = Math.floor(feClock / 60) % 100;
    $('#fe-clock').textContent = `${String(m).padStart(2, '0')}:${(feClock % 60).toFixed(2).padStart(5, '0')}`;
    const cv = $('#fe-art');
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = Math.round(cv.clientWidth * dpr), H = Math.round(cv.clientHeight * dpr);
    if (cv.width !== W || cv.height !== H) Object.assign(cv, { width: W, height: H });
    const g = cv.getContext('2d');
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, W, H);
    if (!W || !H) return;
    const id = (fePage || FE[feIdx]).id;
    if (id === 'garage') return drawGarageArt(g, W, H);

    const key = artKey();
    const a = artTrack(key);
    const t = feClock;
    const yaw = 0.22 * Math.sin(t * 0.12);
    const cy = Math.cos(yaw), sy = Math.sin(yaw);
    const pitch = 0.55, cp = Math.cos(pitch), sp = Math.sin(pitch);
    const D = 3.4;
    const f = Math.min(W * 0.5, (H * 0.46) / 0.62) * D;
    const cx = W / 2, cyS = H * 0.5;
    const proj = (x, z, h) => {
      const xr = x * cy - z * sy, zr = x * sy + z * cy;
      const depth = D + zr * cp - h * sp;
      return [cx + (f * xr) / depth, cyS - (f * (h * cp + zr * sp)) / depth, depth];
    };
    const car = (t * 0.035 * Math.min(1.6, 5000 / a.L + 0.4)) % 1 * a.M;
    const glyphs = [];
    for (let k = 0; k < a.M; k++) {
      const k2 = (k + 1) % a.M;
      let nx = -(a.z[k2] - a.z[k]), nz = a.x[k2] - a.x[k];
      const nl = Math.hypot(nx, nz) || 1;
      nx = (nx / nl) * 0.012;
      nz = (nz / nl) * 0.012;
      const behind = (car - k + a.M) % a.M;
      const hot = behind < 10 ? 1 - behind / 10 : 0;
      const ch = a.text[k % a.text.length];
      for (const side of [-1, 1]) {
        const [sx, syS, depth] = proj(a.x[k] + nx * side, a.z[k] + nz * side, a.h[k]);
        glyphs.push({ sx, sy: syS, depth, ch: side < 0 ? ch : ch === ' ' ? '·' : ch, hot, lane: side });
      }
    }
    glyphs.sort((p, q) => q.depth - p.depth);
    const base = (f / D) * 0.034;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    for (const q of glyphs) {
      const sc = D / q.depth;
      const size = base * sc * (q.lane < 0 ? 1 : 0.8);
      g.font = `${Math.max(6, size).toFixed(1)}px ui-monospace, Menlo, Consolas, monospace`;
      const alpha = Math.max(0.18, Math.min(0.9, 0.3 + (sc - 0.8) * 1.4)) + q.hot * 0.4;
      g.fillStyle = `rgba(${q.hot ? 255 : 214}, ${q.hot ? 255 : 222}, ${q.hot ? 255 : 232}, ${Math.min(1, alpha)})`;
      g.setTransform(1, 0, 0, 0.72, q.sx, q.sy);
      g.fillText(q.ch, 0, 0);
    }
    // the car: a bright blob running round the lap
    const k0 = Math.floor(car), fr = car - k0, k1 = (k0 + 1) % a.M;
    const [sx, syS, depth] = proj(a.x[k0] + (a.x[k1] - a.x[k0]) * fr, a.z[k0] + (a.z[k1] - a.z[k0]) * fr, a.h[k0] + (a.h[k1] - a.h[k0]) * fr);
    const r = base * (D / depth) * 0.55;
    g.setTransform(1, 0, 0, 0.7, sx, syS);
    const glow = g.createRadialGradient(0, 0, 0, 0, 0, r * 3);
    glow.addColorStop(0, 'rgba(255,255,255,0.55)');
    glow.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = glow;
    g.fillRect(-r * 3, -r * 3, r * 6, r * 6);
    g.fillStyle = '#fff';
    g.beginPath();
    g.ellipse(0, 0, r * 1.3, r, 0, 0, Math.PI * 2);
    g.fill();

    let cap = `${a.name} · ${(a.L / 1000).toFixed(2)} km`;
    if (id === 'championship') cap = `round ${Math.min(champ ? nextRound() : 0, CALENDAR.length - 1) + 1} of ${CALENDAR.length} · ${cap}`;
    else if (id === 'endurance') cap = `${fmtHours(settings.hours)} · ${cap} · start ${settings.startHour}:00`;
    else if (id === 'single') cap = `${settings.laps} laps · ${cap}`;
    const capEl = $('#fe-caption');
    if (capEl.textContent !== cap.toLowerCase()) capEl.textContent = cap.toLowerCase();
  }

  // the garage: your car on a turntable, ringed with its name in type
  function drawGarageArt(g, W, H) {
    const t = feClock;
    const R = Math.min(W * 0.2, H * 0.36);
    const text = `${settings.playerName} #${settings.playerNumber} · seicento 900 · `.toLowerCase();
    const N = 90;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.font = `${(R * 0.07).toFixed(1)}px ui-monospace, Menlo, Consolas, monospace`;
    for (let k = 0; k < N; k++) {
      const an = (k / N) * Math.PI * 2 + t * 0.15;
      const x = W / 2 + Math.cos(an) * R * 1.35;
      const y = H / 2 + Math.sin(an) * R * 0.5;
      g.setTransform(1, 0, 0, 0.72, x, y);
      g.fillStyle = `rgba(214,222,232,${(0.35 + 0.35 * (Math.sin(an) + 1) / 2).toFixed(2)})`;
      g.fillText(text[k % text.length], 0, 0);
    }
    const s = R / 2.2;
    g.setTransform(s, 0, 0, s * 0.6, W / 2, H / 2);
    SC.drawSeicento(g, { x: 0, y: 0, heading: t * 0.35, color: settings.playerColor, number: settings.playerNumber, stripes: settings.stripes }, 1);
    const capEl = $('#fe-caption');
    const cap = `${settings.playerName} · #${settings.playerNumber} · ${settings.gearbox} gearbox`.toLowerCase();
    if (capEl.textContent !== cap) capEl.textContent = cap;
  }

  function pause() {
    mode = 'pause';
    showScreen('#pause');
    audio.update(race.player, false);
  }

  function showResults() {
    mode = 'results';
    $('#hud').classList.add('hidden');
    audio.update(race.player, false);
    const res = race.results();
    const me = res.find((r) => r.car.isPlayer);
    const fast = race.fastest;
    $('#res-title').textContent = me.car.dnf ? `DNF — ${me.car.dnfReason}` : `🏁 P${me.pos} of ${res.length}`;
    $('#res-sub').textContent =
      `${race.track.name} · ${race.timed ? fmtHours(race.duration / 3600) + ' · ' : ''}${race.winner ? race.winner.finishLap : race.R} laps · ${{ dry: 'Dry', wet: 'Wet', variable: 'Variable weather' }[race.s.weather]}` +
      (fast ? ` · Fastest lap ${fast.car.name} ${SC.fmtTime(fast.t)}` : '');
    const isChamp = !!champ && race.s.series === 'championship';
    if (isChamp && !champ.scored) scoreRound(res);
    const learned = race.brain ? race.brain.progress().filter((x) => x.gain > 0.05) : [];
    $('#res-ai').textContent = learned.length
      ? `🧠 The field learned from you: ${learned.slice(0, 3).map((x) => `${x.car.name.split(' ').pop()} −${x.gain.toFixed(1)} s/lap`).join(', ')}` +
        (learned.length > 3 ? ` and ${learned.length - 3} more` : '') + '.'
      : '';
    const rows = res
      .map((r) => {
        const c = r.car;
        const isFast = fast && fast.car === c;
        const time = r.pos === 1 && r.total != null ? SC.fmtTime(r.total) : r.gap || (r.status ? '' : '—');
        return (
          `<tr class="${c.isPlayer ? 'me' : ''}">` +
          `<td>${c.dnf ? 'DNF' : r.pos}</td><td>${c.number}</td>` +
          `<td><span class="sw" style="background:${c.color}"></span>${c.name}</td>` +
          `<td>${r.laps}</td><td>${time}${r.status ? ` <span class="pen">${r.status}</span>` : ''}` +
          `${c.penalties.map((p) => ` <span class="pen">+${p[1]} s ${p[0]}</span>`).join('')}</td>` +
          `<td>${isFast ? `<span class="purple">${SC.fmtTime(c.bestLap)}</span>` : SC.fmtTime(c.bestLap)}</td>` +
          `<td>${c.stops}</td><td><span class="tyres">${c.history.map((h) => badge(h)).join('')}</span></td>` +
          `${isChamp ? `<td><b>+${roundPoints(r)}</b></td>` : ''}</tr>`
        );
      })
      .join('');
    $('#res-table').innerHTML = `<tr><th>Pos</th><th>No.</th><th>Driver</th><th>Laps</th><th>Time / gap</th><th>Best lap</th><th>Stops</th><th>Tyres</th>${isChamp ? '<th>Pts</th>' : ''}</tr>${rows}`;
    showChampionship(isChamp);
    showScreen('#results');
  }

  const roundPoints = (r) => (r.car.dnf ? 0 : POINTS[r.pos - 1] || 0);

  function scoreRound(res) {
    champ.scored = true;
    for (const r of res) {
      const c = r.car;
      const e = champ.table[c.id] || (champ.table[c.id] = { points: 0, wins: 0 });
      Object.assign(e, { id: c.id, name: c.name, color: c.color, number: c.number, isPlayer: c.isPlayer });
      e.points += roundPoints(r);
      if (r.pos === 1 && !c.dnf) e.wins++;
    }
    saveChamp();
  }

  function showChampionship(on) {
    $('#champ-wrap').classList.toggle('hidden', !on);
    $('#champ-next').classList.toggle('hidden', !on);
    $('#res-again').classList.toggle('hidden', on);
    if (!on) return;
    const last = champ.round >= CALENDAR.length - 1;
    const table = Object.values(champ.table).sort((a, b) => b.points - a.points || b.wins - a.wins || a.id - b.id);
    $('#champ-title').textContent = last
      ? table[0].isPlayer ? '🏆 You are the champion!' : `🏆 Champion: ${table[0].name}`
      : `Standings after round ${champ.round + 1} of ${CALENDAR.length}`;
    $('#champ-table').innerHTML =
      '<tr><th>Pos</th><th>No.</th><th>Driver</th><th>Wins</th><th>Points</th></tr>' +
      table
        .map(
          (e, i) =>
            `<tr class="${e.isPlayer ? 'me' : ''}"><td>${i + 1}</td><td>${e.number}</td>` +
            `<td><span class="sw" style="background:${e.color}"></span>${e.name}</td><td>${e.wins}</td><td><b>${e.points}</b></td></tr>`
        )
        .join('');
    const next = $('#champ-next');
    next.textContent = last ? 'Finish championship' : `Next round: ${SC.getTrack(CALENDAR[champ.round + 1]).name} ▸`;
    next.dataset.act = last ? 'menu' : 'next';
  }

  // ---------------- input ----------------
  window.addEventListener('keydown', (e) => {
    const tag = e.target.tagName;
    if ((tag === 'INPUT' && !['range', 'checkbox'].includes(e.target.type)) || tag === 'SELECT') return;
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
    keys[e.code] = true;
    // menus: the keyboard drives them (held arrows repeat), so a focused button mustn't also fire on Enter
    if (mode === 'menu' || mode === 'pause' || mode === 'results') {
      if (e.code === 'Enter') e.preventDefault();
      if (mode === 'menu') return feKey(e);
      if (e.code === 'ArrowDown' || e.code === 'KeyS') return listMove(1);
      if (e.code === 'ArrowUp' || e.code === 'KeyW') return listMove(-1);
      if (e.code === 'Enter' && !e.repeat) {
        const b = listMove(0);
        if (b) b.click();
        return;
      }
    }
    if (e.repeat) return;
    if (mode === 'race' && race) {
      const p = race.player;
      switch (e.code) {
        case 'KeyP': race.playerTogglePit(); break;
        case 'BracketLeft': race.playerCycleCompound(-1); break;
        case 'BracketRight': race.playerCycleCompound(1); break;
        case 'Minus': case 'NumpadSubtract': race.playerAdjustFuel(-1); break;
        case 'Equal': case 'NumpadAdd': race.playerAdjustFuel(1); break;
        case 'KeyR': race.playerReplan(); break;
        case 'KeyO': race.setAutopilot(!p.autopilot); break;
        case 'KeyC':
          if (is3d()) {
            const modes = SC.Renderer3D.MODES;
            settings.camera3d = modes[(modes.indexOf(settings.camera3d) + 1) % modes.length];
            race.log(`Camera: ${{ chase: 'chase', far: 'far chase', bonnet: 'roof cam', top: "bird's-eye" }[settings.camera3d]}`);
          } else settings.cameraRotate = !settings.cameraRotate;
          save();
          break;
        case 'KeyL': settings.racingLine = !settings.racingLine; save(); break;
        case 'KeyH': $('#help').classList.toggle('hidden'); break;
        case 'KeyM': audio.toggleMute(); break;
        case 'KeyE': input.shiftUp = true; break;
        case 'KeyQ': input.shiftDown = true; break;
        case 'Escape': pause(); break;
        case 'Enter': if (p.finished || p.dnf) mode = 'skipping'; break;
        case 'Period': setWarp(1); break;
        case 'Comma': setWarp(-1); break;
      }
    } else if (mode === 'pause' && e.code === 'Escape') action('resume');
  });
  window.addEventListener('keyup', (e) => (keys[e.code] = false));
  window.addEventListener('blur', () => Object.keys(keys).forEach((k) => (keys[k] = false)));

  function setWarp(dir) {
    const k = WARPS.indexOf(warp);
    const next = WARPS[Math.max(0, Math.min(WARPS.length - 1, k + dir))];
    if (next === warp) return;
    warp = next;
    const p = race.player;
    if (warp > 1 && !p.autopilot && !p.finished && !p.dnf) {
      race.setAutopilot(true);
      if (p.autopilot) race.log('Co-driver takes the wheel — press O to take it back');
    }
    race.log(warp > 1 ? `Time warp ×${warp}` : 'Real time');
  }

  function fmtHours(h) {
    return h < 1 ? Math.round(h * 60) + ' min' : h + ' h';
  }

  function fmtClock(sec) {
    const t = Math.max(0, Math.floor(sec));
    const h = Math.floor(t / 3600);
    const m = Math.floor((t % 3600) / 60);
    const s2 = t % 60;
    return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s2).padStart(2, '0');
  }

  function pollPad() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const gp = Array.from(pads).find(Boolean);
    if (!gp) return;
    const ax = gp.axes[0] || 0;
    const rt = gp.buttons[7] ? gp.buttons[7].value : 0;
    const lt = gp.buttons[6] ? gp.buttons[6].value : 0;
    if (Math.abs(ax) > 0.15 || rt > 0.05 || lt > 0.05) pad.active = true;
    const dz = Math.max(0, (Math.abs(ax) - 0.1) / 0.9);
    pad.steer = Math.sign(ax) * dz * dz;
    pad.throttle = rt;
    pad.brake = lt;
    const pressed = gp.buttons.map((b) => b.pressed);
    const edge = (i) => pressed[i] && !pad.prev[i];
    if (mode === 'race' && race) {
      if (edge(5)) input.shiftUp = true;
      if (edge(4)) input.shiftDown = true;
      if (edge(3)) race.playerTogglePit();
      if (edge(9)) pause();
    } else if (mode === 'pause' && edge(9)) action('resume');
    pad.prev = pressed;
  }

  function updateInput(dt) {
    const toward = (v, t, rate) => (v < t ? Math.min(t, v + rate * dt) : Math.max(t, v - rate * dt));
    const kb = keys.ArrowUp || keys.KeyW || keys.ArrowDown || keys.KeyS || keys.ArrowLeft || keys.KeyA || keys.ArrowRight || keys.KeyD;
    if (kb) pad.active = false;
    if (pad.active) {
      input.steer = pad.steer;
      input.throttle = pad.throttle;
      input.brake = pad.brake;
      return;
    }
    const st = (keys.ArrowRight || keys.KeyD ? 1 : 0) - (keys.ArrowLeft || keys.KeyA ? 1 : 0);
    const back = st === 0 || Math.sign(st) !== Math.sign(input.steer);
    input.steer = toward(input.steer, st, back ? 7 : 3.2);
    input.throttle = toward(input.throttle, keys.ArrowUp || keys.KeyW ? 1 : 0, 6);
    input.brake = toward(input.brake, keys.ArrowDown || keys.KeyS || keys.Space ? 1 : 0, 8);
  }

  // ---------------- HUD ----------------
  function updateDash() {
    const p = race.player;
    const kmh = Math.round(Math.abs(p.speed || 0) * 3.6);
    $('#dash-speed').textContent = kmh;
    $('#dash-gear').textContent = p.rev || (p.speed || 0) < -0.3 ? 'R' : kmh < 1 && p.control === 'free' && p.throttle < 0.05 ? 'N' : p.gear + 1;
    $('#dash-rpm-fill').style.width = Math.min(100, (p.rpm / SC.Car.CAR.limiter) * 100) + '%';
  }

  function gapText(car, leader, i) {
    const L = race.track.L;
    if (car.dnf) return 'OUT';
    if (i === 0) return car.finished ? 'FINISH' : `LAP ${race.timed ? car.lap + 1 : Math.min(car.lap + 1, race.R)}`;
    if (car.finished && leader.finishTime != null && car.finishTime != null) {
      const down = leader.finishLap - car.finishLap;
      return down > 0 ? `+${down}L` : '+' + (car.finishTime - leader.finishTime).toFixed(1);
    }
    if (car.mode === 'pit') return 'PIT';
    const lead = leader.finished ? leader.finishLap * L : leader.lap * L + leader.s;
    const down = Math.floor((lead - (car.lap * L + car.s)) / L);
    if (down >= 1) return `+${down}L`;
    return '+' + Math.max(0, car.gap).toFixed(1);
  }

  function updateHud(dt) {
    updateDash();
    minimap.draw(race, race.player);
    hudT -= dt;
    if (hudT > 0) return;
    hudT = 0.12;
    const p = race.player;
    const tr = race.track;
    const R = race.R;

    $('#tb-lap').textContent = race.timed ? `${p.lap + 1}` : `${Math.min(p.lap + 1, R)}/${R}`;
    $('#tb-pos').textContent = `${p.pos}/${race.cars.length}`;
    if (race.timed) $('#tb-time').textContent = race.phase === 'countdown' ? fmtClock(race.duration) : race.timeLeft > 0 ? fmtClock(race.timeLeft) + ' left' : 'FINAL LAP';
    else $('#tb-time').textContent = race.phase === 'countdown' ? '0:00' : SC.fmtTime(race.raceTime).replace(/\.\d+$/, '');
    const tod = race.timeOfDay;
    const night = SC.util.sunAt(tod).day < 0.5;
    $('#tb-clock').textContent = `${night ? '🌙' : '☀'} ${String(Math.floor(tod)).padStart(2, '0')}:${String(Math.floor((tod % 1) * 60)).padStart(2, '0')}${warp > 1 ? ` ×${warp}` : ''}`;
    $('#tb-sector').textContent = tr.sectorName(p.s);
    const w = race.weather;
    const icon = w.rain > 0.05 ? '🌧' : w.wet > 0.05 ? '🌥' : '☀';
    $('#tb-weather').textContent = `${icon} ${Math.round(w.wet * 100)}% wet · ${w.forecast(Math.max(0, race.raceTime))}`;

    const leader = race.order[0];
    $('#tower').innerHTML = race.order
      .map((c, i) => {
        const cls = ['row', c.isPlayer ? 'me' : '', c.mode === 'pit' ? 'pit' : '', c.dnf ? 'out' : ''].join(' ');
        return (
          `<div class="${cls}"><span class="p">${i + 1}</span><span class="bar" style="background:${c.color}"></span>` +
          `<span class="n">${c.number}</span><span class="nm">${c.isPlayer ? c.name : c.name.split(' ').pop().toUpperCase()}</span>` +
          `<span class="gap">${gapText(c, leader, i)}</span>${badge(c.tyre.c)}<span class="st">${c.stops}</span></div>`
        );
      })
      .join('');

    // lights & banner
    const lights = $('#lights');
    if (race.phase === 'countdown' || race.raceTime < 1.2) {
      lights.classList.remove('hidden');
      const lit = race.phase === 'countdown' ? Math.max(0, Math.min(5, Math.floor(race.clock))) : 0;
      lights.querySelectorAll('i').forEach((el, k) => el.classList.toggle('on', k < lit));
    } else lights.classList.add('hidden');
    const banner = $('#banner');
    let text = '';
    let cls = '';
    if (race.phase === 'countdown') text = race.clock < 1 ? `Grid P${p.grid}<small>Hold the throttle for a good launch — wait for lights out</small>` : '';
    else if (race.raceTime < 1.5) text = 'GO!';
    else if (p.dnf) text = `RETIRED<small>Enter — skip to results</small>`;
    else if (p.finished) text = `FINISHED P${p.pos}<small>Enter — skip to results</small>`;
    else if (p.mode === 'pit' && p.pit.phase === 'service') text = `PIT STOP ${p.pit.left.toFixed(1)} s`;
    else if (p.outOfFuel) text = 'OUT OF FUEL';
    else if (p.pitRequest) {
      text = 'BOX  BOX';
      cls = 'box';
    } else if (p.control === 'free' && p.v > 4 && Math.cos(p.heading - tr.heading(p.s)) < -0.3) text = 'WRONG WAY';
    else if (p.autopilot) text = `<small>${warp > 1 ? `CO-DRIVER · TIME ×${warp} ( , . )` : 'AUTOPILOT (O)'}</small>`;
    banner.innerHTML = text;
    banner.className = cls;

    // pit wall
    const t = p.tyre;
    const perLap = tr.L * T.wearPerMetre(t.c, w.wet, settings.wearMult);
    const tyreLaps = t.wear / perLap;
    const sv = p.service || (p.mode === 'race' && !p.finished ? race.defaultService(p) : null);
    const nextStop = race.playerNextStopLap();
    const from = Math.max(0, p.stintIdx - 2);
    const planHtml = (from > 0 ? `<span class="stint done">+${from}</span>` : '') + p.plan
      .slice(from, from + 8)
      .map((st, k) => `<span class="stint ${k + from < p.stintIdx ? 'done' : k + from === p.stintIdx ? 'cur' : ''}">${badge(st.c)}${st.laps}</span>`)
      .join('');
    let status = '';
    if (p.mode === 'pit') {
      if (p.pit.phase === 'in') status = 'Pit lane — limiter 60 km/h';
      else if (p.pit.phase === 'service') status = `Crew working… ${(p.pit.total - p.pit.left).toFixed(1)} / ${p.pit.total.toFixed(1)} s`;
      else status = 'Released — pit exit ahead';
    } else if (p.pitRequest) status = '<b>Box this lap</b> — follow the pit entry';
    else if (nextStop) status = nextStop === p.lap + 1 ? '<b>Plan: box this lap</b> (P to confirm)' : `Plan: box after lap ${nextStop}`;
    else status = 'No more stops planned';
    const fuelLaps = p.fuel / race.fpl;
    $('#pitwall').innerHTML =
      `<div class="pw-title">PIT WALL <span class="req ${p.pitRequest ? 'on' : ''}">${p.pitRequest ? 'BOX REQUESTED' : 'P = REQUEST BOX'}</span></div>` +
      `<div class="pw-row">${badge(t.c, true)}<div style="flex:1"><div style="display:flex;justify-content:space-between"><span>${T.COMPOUNDS[t.c].name} · <b>${Math.round(t.wear * 100)}%</b></span>` +
      `<small>${t.temp < 0.75 ? '❄ cold' : 'warm'} · ≈${tyreLaps.toFixed(1)} laps</small></div>` +
      `<div class="meter"><i style="width:${t.wear * 100}%;background:${t.wear < 0.25 ? '#ff3b3b' : t.wear < 0.5 ? '#ffcc00' : '#3ddc84'}"></i></div></div></div>` +
      `<div class="pw-row">⛽ <b>${p.fuel.toFixed(1)} L</b> <small>≈ ${fuelLaps.toFixed(1)} laps · ${race.fpl.toFixed(2)} L/lap</small>` +
      `<div class="meter"><i style="width:${(p.fuel / SC.Car.CAR.tank) * 100}%;background:#4aa3ff"></i></div></div>` +
      `<div class="pw-row plan">${planHtml}</div>` +
      `<div class="pw-row">${status}</div>` +
      (sv
        ? `<div class="service">Next stop: ${sv.c ? badge(sv.c) + ' ' + T.COMPOUNDS[sv.c].name : 'keep tyres'}` +
          `${race.rules.refuel ? ` · <b>+${sv.litres.toFixed(1)} L</b>` : ''} · ≈${sv.time.toFixed(1)} s` +
          `<div class="keys">[ ] tyre${race.rules.refuel ? ' · − = fuel' : ''} · R ask strategist</div></div>`
        : '');

    $('#dash-laps').innerHTML =
      `<span>Last</span><b>${SC.fmtTime(p.lastLap)}</b><span>Best</span><b class="${race.fastest && race.fastest.car === p ? 'purple' : ''}">${SC.fmtTime(p.bestLap)}</b>` +
      `<span>Lap</span><b>${race.phase === 'racing' ? SC.fmtTime(race.raceTime - p.lapStart) : '—'}</b>`;

    // event feed
    const now = race.clock;
    for (const e of race.events) {
      if (e.id <= lastEventSeen) continue;
      lastEventSeen = e.id;
      if (e.kind === 'box') audio.beep(880, 0.1, 2);
      if (e.kind === 'good') audio.beep(660, 0.15, 1);
    }
    $('#feed').innerHTML = race.events
      .filter((e) => now - e.t < 10)
      .slice(-6)
      .map((e) => `<div class="${e.kind}" style="opacity:${Math.min(1, (10 - (now - e.t)) / 2)}">${e.text}</div>`)
      .join('');
  }

  // ---------------- main loop ----------------
  function stepSim(r, dt, inp, scale = 1) {
    acc += dt * scale;
    let n = 0;
    const cap = 40 * scale;
    const t0 = performance.now();
    while (acc >= STEP && n < cap) {
      r.step(STEP, inp);
      acc -= STEP;
      n++;
      // never let a slow machine fall into a spiral at high warp
      if ((n & 63) === 0 && performance.now() - t0 > 40) break;
    }
    if (n >= cap || acc > STEP * 4 * scale) acc = 0;
  }

  const idle = { throttle: 0, brake: 0, steer: 0 };
  let last = performance.now();
  function frame(now) {
    const dt = Math.max(0, Math.min(0.1, (now - last) / 1000));
    last = now;
    pollPad();
    updateInput(dt);
    if (mode === 'menu') {
      drawFront(dt);
    } else if (race) {
      if (mode === 'race') {
        const p = race.player;
        if (warp > 1 && !p.autopilot && p.mode === 'race' && !p.finished && !p.dnf) race.setAutopilot(true);
        race.warp = warp;
        stepSim(race, dt, input, warp);
        if (race.phase === 'finished') showResults();
      } else if (mode === 'skipping') {
        const t0 = performance.now();
        while (race.phase !== 'finished' && performance.now() - t0 < 25) for (let i = 0; i < 200; i++) race.step(1 / 60, idle);
        const home = race.cars.filter((c) => c.finished || c.dnf).length;
        $('#banner').innerHTML = `Simulating the rest of the race…<small>${race.timed && race.timeLeft > 0 ? fmtClock(race.timeLeft) + ' to go' : `${home}/${race.cars.length} cars home`}</small>`;
        if (race.phase === 'finished') showResults();
      }
      // camera smoothing runs on simulated time so it keeps up under time warp
      const restore = race.interpolate(mode === 'race' ? acc / STEP : 1);
      renderer.updateCamera(race.player, mode === 'race' ? Math.min(0.5, dt * warp) : dt, camMode(race));
      renderer.draw(race, race.player, { racingLine: settings.racingLine });
      restore();
      if (mode === 'race') {
        updateHud(dt);
        audio.update(race.player, !race.player.finished && !race.player.dnf);
      }
    }
    requestAnimationFrame(frame);
  }

  document.addEventListener('click', (e) => {
    if (e.target.id !== 'ai-forget') return;
    if (!confirm(`Make the bots forget everything they learned about you at ${SC.getTrack(settings.track).name}?`)) return;
    SC.Brain.forget(settings.track);
    aiMemory();
  });
  // keep what the bots learned if the tab is closed mid-race
  window.addEventListener('beforeunload', () => race && race.brain && race.brain.commit());

  bindMenu();
  pickRenderer();
  syncMenu();
  refreshStrategy();
  bindFront();
  requestAnimationFrame(frame);

  // exposed for debugging from the console
  window.SEICENTO = { get race() { return race; }, settings, startRace, renderer, showResults: () => showResults() };
})();
