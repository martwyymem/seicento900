## Learning AI (port of js/brain.js). Each bot drives by a pace it has learned for every 30 m section of the
## track. It finds its limit by trial and error (push a little, back off after a moment) and studies the
## player: how fast you take each corner, the line you use, where and on which side you pass, whether you
## block, and how cleanly you race. Everything learned is kept per track in user://brain.json, so the field
## gets to know you over time. Arrays are float32 like the JS Float32Arrays, so results match bit for bit.
class_name Brain
extends RefCounted

const STORE_PATH := "user://brain.json"
const VER := 1
const BIN := 30 ## metres per learned section

# ---------------- persistent memory ----------------
static var _store = null
## Off in tests: learning then lives in memory only.
static var use_disk := true

static func load_store() -> Dictionary:
	if _store != null:
		return _store
	var s = null
	if use_disk and FileAccess.file_exists(STORE_PATH):
		s = JSON.parse_string(FileAccess.get_file_as_string(STORE_PATH))
	if not (s is Dictionary) or s.get("v") != float(VER):
		s = {"v": VER, "tracks": {}}
	_store = s
	return _store

static func save_store() -> void:
	if not use_disk:
		return
	var f := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_store))

## Replace the persistent memory (tests use an empty one).
static func set_store(s: Dictionary) -> void:
	_store = s

# ratios are stored as integers (×10⁴) to keep the JSON small
static func enc(a: PackedFloat32Array, k := 1e4) -> Array:
	var out := []
	for x in a:
		out.append(SimUtil.js_round(x * k))
	return out

static func dec(a, n: int, k := 1e4) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	if a is Array and a.size() == n:
		for i in n:
			out[i] = (float(a[i]) if a[i] else 0.0) / k
	return out

class Memory:
	var nb := 0
	var pr := PackedFloat32Array() ## player's pace in each section, as a fraction of the grip limit
	var pn := PackedFloat32Array() ## samples behind it
	var pd := PackedFloat32Array() ## player's usual offset from the racing line (m)
	var aS := PackedFloat32Array() ## where you overtake: sum of sides (+1 right, −1 left)
	var aN := PackedFloat32Array()
	var laps := 0
	var races := 0
	var block := 0.3 ## how often you cover the side a bot goes for
	var rough := 0.0 ## how often contact is your fault (0 clean … 1 dodgem)
	var bots := {}

static func track_memory(key: String, nb: int) -> Memory:
	var raw: Dictionary = load_store().tracks.get(key, {})
	var ok: bool = raw.get("nb") == float(nb) or raw.get("nb") == nb
	var m := Memory.new()
	m.nb = nb
	m.pr = dec(raw.get("pr") if ok else null, nb)
	m.pn = dec(raw.get("pn") if ok else null, nb, 1)
	m.pd = dec(raw.get("pd") if ok else null, nb, 100)
	m.aS = dec(raw.get("aS") if ok else null, nb, 100)
	m.aN = dec(raw.get("aN") if ok else null, nb, 1)
	m.laps = int(raw.get("laps", 0))
	m.races = int(raw.get("races", 0))
	m.block = raw.get("block", 0.3) if raw.get("block") != null else 0.3
	m.rough = raw.get("rough", 0.0)
	m.bots = raw.get("bots", {}) if ok else {}
	return m

var race # Race
var persist := false
var tr: Track
var key := ""
var nb := 0
var mem: Memory
var W := PackedFloat32Array() ## how much each section is grip-limited: 0 on flat-out straights, 1 in corners
var v_ref := PackedFloat32Array()
var gaps := {} ## RaceCar -> signed distance to the player
var obs = null
var last_say := -99.0
var last_contact := -99.0
var last_commit := 0.0
var player_lap = null
var bots: Array[RaceCar] = []

func _init(race_, persist_ := false) -> void:
	race = race_
	persist = persist_
	tr = race.track
	key = race.s.track
	nb = ceili(tr.L / BIN)
	mem = track_memory(key, nb)
	W.resize(nb)
	v_ref.resize(nb)
	for b in nb:
		var lo := INF
		var s := float(b * BIN)
		while s < minf(tr.L, (b + 1) * BIN):
			lo = minf(lo, tr.sample(tr.PROF, s))
			s += tr.step
		v_ref[b] = lo
		W[b] = clampf((40.0 - lo) / 6.0, 0.0, 1.0)

func bin(s: float) -> int:
	return int(floorf(tr.wrap_s(s) / BIN)) % nb

# ---------------- bots ----------------
func add_bot(car: RaceCar, spread: float) -> void:
	var rng: SimUtil.Rng = race.rng
	# talent: the pace this driver can hold without mistakes; learning can push a little beyond it
	var talent := minf(0.999, car.skill + 0.008 + (spread + 0.006) * rng.next())
	var b := BotBrain.new()
	b.talent = talent
	b.cap = minf(1.004, talent + 0.012)
	b.floor_ = car.skill - 0.04
	var e := PackedFloat32Array()
	e.resize(nb)
	e.fill(car.skill)
	var saved = mem.bots.get(car.name)
	if saved is Array and saved.size() == nb:
		for i in nb:
			if saved[i]:
				e[i] = clampf(saved[i] / 1e4, b.floor_, b.cap)
	b.e = e
	b.e0 = e.duplicate()
	b.think_t = rng.next() * 0.4
	car.brain = b
	bots.append(car)

## Learned pace (fraction of the grip limit) at s, blended between sections, plus the current state of mind.
func pace_at(car: RaceCar, s: float) -> float:
	var b := car.brain
	var u := tr.wrap_s(s) / BIN - 0.5
	var fu := floorf(u)
	var i := posmod(int(fu), nb)
	var f := u - fu
	var p: float = b.e[i] + (b.e[(i + 1) % nb] - b.e[i]) * f
	if b.mind == "attack" and b.zone >= 0 and absi(bin_dist(bin(s), b.zone)) <= 2:
		p += 0.005
	if b.boost_t > 0.0:
		p += 0.003 # fired up after being passed
	if b.mind == "manage":
		p -= 0.004
	return p

func bin_dist(a: int, b: int) -> int:
	var d := a - b
	if d > nb / 2.0:
		d -= nb
	if d < -nb / 2.0:
		d += nb
	return d

## Called every rail step. no_learn: the section wasn't driven freely (traffic, pits), so it teaches nothing.
func rail_step(car: RaceCar, dt: float, no_learn: bool) -> void:
	var b := car.brain
	if b.boost_t > 0.0:
		b.boost_t -= dt
	b.think_t -= dt
	if b.think_t <= 0.0:
		b.think_t = 0.4
		think(car)
	var i := bin(car.s)
	if no_learn:
		b.dirty = true
	if i == b.bin:
		return
	if b.bin >= 0 and not b.dirty and race.phase == "racing":
		learn(car, b.bin)
	b.bin = i
	b.dirty = no_learn
	if race.phase != "racing" or car.mode != "race" or car.finished or W[i] <= 0.0:
		return
	# over the limit there is a chance of a moment: a lock-up or running wide
	var over := (pace_at(car, i * BIN + BIN / 2.0) - b.talent) / 0.01
	if over > 0.0:
		var p: float = 0.006 * over * over * W[i] * (1.0 + 1.5 * race.weather.wet)
		if race.rng.next() < p:
			mistake(car, i)

func mistake(car: RaceCar, i: int) -> void:
	var b := car.brain
	b.dirty = true
	b.mistakes += 1
	race.bot_mistake(car)
	# learn from it: this section, and a little either side, is taken more carefully from now on
	for j in range(-1, 2):
		var q := (i + j + nb) % nb
		b.e[q] = clampf(b.e[q] - (0.015 if j == 0 else 0.007), b.floor_, b.cap)
	if near(car, 3):
		say(car, "%s runs wide at %s — pushing too hard, backing off there next lap" % [short(car), where(i)], "wide")

func learn(car: RaceCar, i: int) -> void:
	var b := car.brain
	var w := W[i]
	if w <= 0.0:
		return
	var e := b.e[i]
	# trial and error: creep towards the limit; slower once above it, where mistakes start
	var gap := b.talent - e
	e += 0.015 * gap * w + 0.00004 if gap > 0.0 else 0.00004 * w
	# imitation: you showed that this section can be taken faster
	var m := mem
	if m.pn[i] >= 1.0 and m.pr[i] > e:
		var before := e
		e += 0.35 * w * (minf(m.pr[i], b.cap) - e)
		if e - before > 0.002:
			b.copied += 1
			b.copy_gain += (e - before) / e * (BIN / maxf(8.0, v_ref[i] * e))
	b.e[i] = clampf(e, b.floor_, b.cap)

# ---------------- thinking ----------------
func think(car: RaceCar) -> void:
	var b := car.brain
	var p: RaceCar = race.player
	var L := tr.L
	b.mind = "race"
	if car.mode != "race" or car.finished or race.phase != "racing":
		return
	var live := p.mode == "race" and not p.finished and not p.dnf
	var gap := p.lap * L + p.s - (car.lap * L + car.s) if live else INF
	if gap > 0.0 and gap < 80.0:
		# chasing you: look for where you are slower than me in the next ~600 m
		b.mind = "attack"
		if b.zone < 0 or bin_dist(b.zone, bin(car.s)) < -2:
			b.zone = -1
			var i0 := bin(car.s)
			var best := 0.02
			for j in range(2, 600 / BIN):
				var q := (i0 + j) % nb
				if mem.pn[q] < 1.0 or W[q] < 0.5:
					continue
				var deficit := b.e[q] - mem.pr[q]
				if deficit > best:
					best = deficit
					b.zone = q
			if b.zone >= 0 and gap < 40.0 and near(car, 2):
				say(car, "%s has noticed you're slow through %s — expect an attack there" % [short(car), where(b.zone)], "zone")
	elif gap < 0.0 and gap > -35.0:
		var pv := sqrt(p.vx * p.vx + p.vy * p.vy)
		if gap > -14.0 or pv > car.v + 0.5:
			b.mind = "defend"
	else:
		b.zone = -1
		# alone on track with worn tyres: look after them
		var order: Array = race.order
		var ahead: RaceCar = order[car.pos - 2] if car.pos - 2 >= 0 and car.pos - 2 < order.size() else null
		var behind: RaceCar = order[car.pos] if car.pos < order.size() else null
		var clear := func(o: RaceCar) -> bool:
			return o == null or absf(o.lap * L + o.s - (car.lap * L + car.s)) > 110.0
		if car.tyre.wear < 0.55 and clear.call(ahead) and clear.call(behind):
			b.mind = "manage"
	# judge an attack on you: did you move across to cover it?
	if b.att and not b.att.judged and race.clock - b.att.t > 1.2:
		b.att.judged = true
		var moved: bool = (p.d - b.att.d0) * b.att.side > 0.7
		mem.block = mem.block * 0.88 + (0.12 if moved else 0.0)

## Adjust a bot's lateral target (after traffic logic): cover the side you're likely to attack,
## or switch sides when you block its move.
func adjust(car: RaceCar, t: Dictionary, lim: float) -> Dictionary:
	var b := car.brain
	var p: RaceCar = race.player
	if b.mind == "defend" and car.overtake_t <= 0.0:
		var i := bin(car.s)
		var hist := 0.0
		var n := 0.0
		for j in 6:
			var q := (i + j) % nb
			hist += mem.aS[q]
			n += mem.aN[q]
		var now := signf(p.d - car.d)
		var inside := signf(tr.sample(tr.KC, car.s + 40.0))
		var pred := 0.6 * hist / n + 0.4 * now if n >= 2.0 else 0.5 * now + 0.3 * inside
		if absf(pred) > 0.25:
			var rl := tr.sample(tr.RLD, car.s)
			var want := clampf(rl + signf(pred) * 1.3, -lim, lim)
			t.dT = t.dT + (want - t.dT) * 0.8
			if not b.covering and n >= 2.0 and near(car, 1):
				b.covering = true
				say(car, "%s is covering the %s — it has learned where you like to pass" % [short(car), "right" if pred > 0.0 else "left"], "cover")
	else:
		b.covering = false
	# attacking you: remember the attempt, and switch back if you close the door
	if car.overtake_t > 0.0 and ahead_is(car, p):
		if not b.att or b.att.id != car.overtake_t0:
			var side := signf(car.overtake_d - p.d)
			b.att = {"id": car.overtake_t0, "t": race.clock, "d0": p.d, "side": side if side != 0.0 else 1.0,
				"judged": false, "switched": false}
		var a: Dictionary = b.att
		if not a.switched and (p.d - a.d0) * a.side > 0.9:
			a.switched = true
			if race.rng.next() < clampf(0.25 + mem.block, 0.0, 0.9):
				var other: float = p.d - a.side * 2.4
				if absf(other) <= lim:
					car.overtake_d = other
					car.overtake_t = 3.0
					t.dT = other
					if near(car, 1):
						say(car, "%s saw the block coming and switches to the %s" % [short(car), "right" if other > p.d else "left"], "switch")
	return t

func ahead_is(car: RaceCar, o: RaceCar) -> bool:
	var g := tr.rel(o.s - car.s)
	return g > 0.0 and g < 30.0 and o.mode == "race"

## Extra lateral room bots leave next to someone who keeps leaning on them.
func margin(o: RaceCar) -> float:
	return 0.9 * mem.rough if o.is_player else 0.0

# ---------------- watching the player ----------------
func observe() -> void:
	var p: RaceCar = race.player
	if race.phase != "racing":
		return
	if persist and race.race_time - last_commit > 120.0:
		commit()
	var driving := p.control == "free" and not p.autopilot and p.mode == "race" and not p.finished and not p.dnf
	if not driving:
		obs = null
		gaps.clear()
		return
	if player_lap != p.lap:
		if player_lap != null and p.lap > player_lap:
			mem.laps += 1
			mem.rough *= 0.9
		player_lap = p.lap
	var i := bin(p.s)
	var o = obs
	if o and o.bin != i:
		var m := mem
		if o.ok and o.max > 0.55 and absi(bin_dist(i, o.bin)) == 1:
			var a := 1.0 if m.pn[o.bin] < 1.0 else 0.4
			m.pr[o.bin] = m.pr[o.bin] * (1.0 - a) + minf(1.03, o.max) * a
			m.pn[o.bin] = minf(99.0, m.pn[o.bin] + 1.0)
		if o.n > 0:
			var a := 1.0 if m.pn[o.bin] <= 1.0 else 0.3
			m.pd[o.bin] = m.pd[o.bin] * (1.0 - a) + (o.dsum / o.n) * a
	if not o or o.bin != i:
		obs = {"bin": i, "max": 0.0, "ok": true, "dsum": 0.0, "n": 0}
	var ob: Dictionary = obs
	var v := sqrt(p.vx * p.vx + p.vy * p.vy)
	var mu: float = race.tyres.tyre_grip(p.tyre, race.weather.wet)
	var lim := tr.sample(tr.PROF, p.s) * sqrt(mu)
	if lim < 40.0:
		ob.max = maxf(ob.max, v / lim)
	ob.dsum += p.d - tr.sample(tr.RLD, p.s)
	ob.n += 1
	# only clean, unhindered driving teaches the field anything
	var ch := cos(p.heading)
	var sh := sin(p.heading)
	var slip_ang := absf(atan2(-sh * p.vx + ch * p.vy, ch * p.vx + sh * p.vy)) if v > 3.0 else 0.0
	if absf(p.d) > tr.half + 0.3 or p.rev or slip_ang > 0.14 or race.clock - last_contact < 2.0 or (race.rc and race.rc.slowed(p)):
		ob.ok = false
	else:
		for c in race.cars:
			if c != p and not c.dnf and c.mode == "race":
				var g := tr.rel(c.s - p.s)
				if g > 0.0 and g < 22.0 and absf(c.d - p.d) < 2.2:
					ob.ok = false
					break

	# overtakes between you and the bots
	var L := tr.L
	var pp := p.lap * L + p.s
	for c in bots:
		if c.dnf or c.finished or c.mode != "race":
			gaps.erase(c)
			continue
		var g := c.lap * L + c.s - pp
		var prev = gaps.get(c)
		if absf(g) > 15.0:
			gaps.erase(c)
			continue
		gaps[c] = g
		if prev == null:
			continue
		if prev > 0.0 and g <= 0.0:
			var side := signf(p.d - c.d)
			if side == 0.0:
				side = 1.0
			mem.aS[i] += side
			mem.aN[i] += 1.0
			c.brain.boost_t = 20.0
			say(c, "You passed %s on the %s at %s — it'll remember that" % [short(c), "right" if side > 0.0 else "left", where(i)], "passed")
		elif prev < 0.0 and g >= 0.0 and c.brain.mind == "attack" and c.brain.zone >= 0:
			say(c, "%s got you where it planned to, at %s" % [short(c), where(i)], "got")

## Car contact: work out who closed in on whom.
func contact(a: RaceCar, b: RaceCar, nx: float, ny: float) -> void:
	if not a.is_player and not b.is_player:
		return
	var p := a if a.is_player else b
	var o := b if a.is_player else a
	var sgn := 1.0 if a.is_player else -1.0 # (nx, ny) points from a to b
	var p_in := (p.vx * nx + p.vy * ny) * sgn
	var o_in := -(o.vx * nx + o.vy * ny) * sgn
	last_contact = race.clock
	if p_in > o_in + 0.5:
		var before := mem.rough
		mem.rough = minf(1.0, before + 0.2)
		if before < 0.5 and mem.rough >= 0.5:
			say(o, "The field has decided you are a bit rough — they will leave you extra room", "rough")

## A bot crossed the line: tell you what it picked up from you.
func lap(car: RaceCar) -> void:
	var b := car.brain
	if not b:
		return
	if b.copied >= 3 and b.copy_gain > 0.1 and near(car, 3):
		say(car, "%s copied your speed in %d places last lap (≈%.1f s)" % [short(car), b.copied, b.copy_gain], "copy")
	b.copied = 0
	b.copy_gain = 0.0

# ---------------- feed ----------------
func near(car: RaceCar, n: int) -> bool:
	var p: RaceCar = race.player
	return not p.dnf and absi(car.pos - p.pos) <= n

## Post a thought to the feed; each kind of remark only once per bot per race, and not too often.
func say(car: RaceCar, text: String, kind: String) -> void:
	var b := car.brain
	if race.clock - last_say < 10.0 or (b and (race.clock - b.last_said < 45.0 or b.said.has(kind))):
		return
	last_say = race.clock
	if b:
		b.last_said = race.clock
		b.said[kind] = true
	race.log_event("🧠 " + text, "ai")

func where(i: int) -> String:
	var s := i * BIN + BIN / 2.0
	var nm := tr.sector_name(s)
	return nm if nm else "the %.1f km mark" % (s / 1000.0)

## Time per lap each bot has gained by learning this race (s), fastest learner first: [{car, gain}].
func progress() -> Array:
	var out := []
	for c in bots:
		var b := c.brain
		var t := 0.0
		for i in nb:
			if not W[i]:
				continue
			var v := maxf(8.0, v_ref[i] * b.e[i])
			t += BIN / v * ((b.e[i] - b.e0[i]) / b.e[i])
		out.append({"car": c, "gain": t})
	out.sort_custom(func(x, y): return x.gain > y.gain)
	return out

## Write what was learned to user://brain.json.
func commit(final := false) -> void:
	if not persist:
		return
	last_commit = race.race_time
	var m := mem
	var st := load_store()
	var prev: Dictionary = st.tracks.get(key, {})
	var saved_bots: Dictionary = prev.get("bots", {}).duplicate() if prev.get("nb") == float(nb) or prev.get("nb") == nb else {}
	for c in bots:
		saved_bots[c.name] = enc(c.brain.e)
	st.tracks[key] = {
		"nb": nb, "pr": enc(m.pr), "pn": enc(m.pn, 1), "pd": enc(m.pd, 100), "aS": enc(m.aS, 100), "aN": enc(m.aN, 1),
		"laps": m.laps, "races": m.races + (1 if final else 0), "block": snappedf(m.block, 0.001),
		"rough": snappedf(m.rough, 0.001), "bots": saved_bots,
	}
	if final:
		m.races += 1
	save_store()

## For the menu: what the AI knows about you on a track, or {} if nothing yet.
static func summary(track_key: String) -> Dictionary:
	var t = load_store().tracks.get(track_key)
	if not t:
		return {}
	var n := 0
	var sum := 0.0
	var pr = t.get("pr")
	if pr is Array:
		for i in pr.size():
			if pr[i] and t.pn[i]:
				n += 1
				sum += pr[i] / 1e4
	return {"laps": t.get("laps", 0), "races": t.get("races", 0), "sections": n, "pace": sum / n if n else null,
		"block": t.get("block"), "rough": t.get("rough")}

static func forget(track_key := "") -> void:
	var st := load_store()
	if track_key:
		st.tracks.erase(track_key)
	else:
		st.tracks = {}
	save_store()

static func short(car: RaceCar) -> String:
	return car.name.split(" ")[-1]
