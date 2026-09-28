## Procedural rally audio for the 899 cc four-cylinder Seicento (port of js/audio.js).
## Uses AudioStreamGenerator for real-time waveform synthesis without external sound files.
class_name RaceAudio
extends Node

const SAMPLE_RATE := 22050.0
const TWO_PI := TAU

var player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback

var muted := false
var master_volume := 0.45
var current_master := 0.45

# Engine state
var active := false
var rpm := 850.0
var throttle := 0.0
var slip := 0.0
var understeer := 0.0
var last_gear := -1

# Oscillator phases
var osc_phase := [0.0, 0.0, 0.0, 0.0] # multiples 1, 2, 3, 4
var osc_weights := [0.62, 0.22, 0.075, 0.035]

# Filter states (1-pole and 2-pole approximations)
var lp_engine := 0.0
var bp_exhaust_p1 := 0.0
var bp_exhaust_p2 := 0.0
var bp_squeal_p1 := 0.0
var bp_squeal_p2 := 0.0
var hp_limiter := 0.0
var hp_limiter_in := 0.0

# PRNG for noise
var noise_seed := 1234567

# Shift transient sound effect
var shift_active := false
var shift_time := 0.0
var shift_duration := 0.08
var shift_is_up := true
var shift_load := 0.0

# Pit beep sound effect
var beep_timer := 0.0
var beep_count := 0
var beep_freq := 880.0
var beep_phase := 0.0

# reused every _process call instead of allocating a fresh PackedVector2Array each time
var _mix_buffer := PackedVector2Array()

func _ready() -> void:
	player = AudioStreamPlayer.new()
	generator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.1
	player.stream = generator
	add_child(player)
	player.play()
	playback = player.get_stream_playback()

func update_car(car, is_active: bool) -> void:
	active = is_active and car != null
	if not active:
		rpm = 0.0
		throttle = 0.0
		slip = 0.0
		understeer = 0.0
		last_gear = -1
		return

	var target_rpm: float = maxf(750.0, float(car.rpm))
	rpm = target_rpm
	throttle = clampf(float(car.throttle), 0.0, 1.0)
	slip = maxf(0.0, float(car.slip) - 0.45)
	understeer = maxf(0.0, float(car.understeer) - 1.0)

	var cur_gear: int = int(car.gear)
	if last_gear != -1 and cur_gear != last_gear:
		trigger_shift(cur_gear > last_gear, throttle)
	last_gear = cur_gear

func trigger_shift(up: bool, load: float) -> void:
	shift_active = true
	shift_time = 0.0
	shift_duration = 0.085
	shift_is_up = up
	shift_load = load

func beep(freq := 880.0, count := 2) -> void:
	beep_freq = freq
	beep_count = count
	beep_timer = 0.0

func toggle_mute() -> bool:
	muted = not muted
	return muted

func _process(_delta: float) -> void:
	if not playback:
		if player and player.playing:
			playback = player.get_stream_playback()
		return

	var frames_avail: int = playback.get_frames_available()
	if frames_avail <= 0:
		return

	var dt := 1.0 / SAMPLE_RATE
	if _mix_buffer.size() != frames_avail:
		_mix_buffer.resize(frames_avail)

	var target_master := 0.0 if muted else master_volume
	current_master = lerpf(current_master, target_master, 0.05)

	# Frequencies and filter targets
	var firing_hz: float = maxf(25.0, (rpm / 60.0) * 2.0)
	var rev: float = clampf((rpm - 900.0) / 5700.0, 0.0, 1.0)
	var lp_cutoff: float = 520.0 + rev * 1450.0 + throttle * 650.0
	var alpha_lp: float = clampf(TWO_PI * lp_cutoff * dt, 0.01, 0.95)

	var engine_vol: float = (0.105 + rev * 0.065 + throttle * 0.055) if active else 0.0
	var exhaust_vol: float = (0.018 + rev * (0.035 + throttle * 0.035)) if active else 0.0
	var squeal_vol: float = minf(0.085, slip * 0.055 + understeer * 0.035) if active else 0.0
	var limiter_vol: float = minf(0.11, (rpm - 6500.0) / 900.0 * 0.11) if (active and rpm > 6500.0) else 0.0

	# Precalculate bandpass coefficients
	# Exhaust BP center ~ 420 + rev * 800
	var f_ex: float = 420.0 + rev * 800.0
	var ex_c := clampf(TWO_PI * f_ex * dt, 0.01, 0.8)
	# Squeal BP center ~ 1550 Hz
	var sq_c := clampf(TWO_PI * 1550.0 * dt, 0.01, 0.8)

	for i in frames_avail:
		var frame_out := 0.0

		if active and current_master > 0.001:
			# 1. Engine harmonics
			var raw_harmonics := 0.0
			for h in 4:
				var m := float(h + 1)
				var phase: float = osc_phase[h]
				osc_phase[h] = fmod(phase + (firing_hz * m) * dt, 1.0)

				var wave := 0.0
				if h == 0:
					# Sawtooth
					wave = 2.0 * phase - 1.0
				elif h == 1:
					# Triangle
					wave = 2.0 * absf(2.0 * phase - 1.0) - 1.0
				else:
					# Square
					wave = 0.7 if phase < 0.5 else -0.7
				raw_harmonics += wave * osc_weights[h]

			# Lowpass filter for engine
			lp_engine += alpha_lp * (raw_harmonics - lp_engine)
			frame_out += lp_engine * engine_vol

			# Fast LCG PRNG for noise
			noise_seed = (noise_seed * 1103515245 + 12345) & 0x7FFFFFFF
			var white_noise: float = (float(noise_seed) / 1073741824.0) - 1.0

			# Exhaust rasp bandpass
			bp_exhaust_p1 += ex_c * (white_noise - bp_exhaust_p1)
			bp_exhaust_p2 += ex_c * (bp_exhaust_p1 - bp_exhaust_p2)
			var exhaust_band: float = (bp_exhaust_p1 - bp_exhaust_p2) * 2.5
			frame_out += exhaust_band * exhaust_vol

			# Tyre squeal bandpass
			if squeal_vol > 0.001:
				bp_squeal_p1 += sq_c * (white_noise - bp_squeal_p1)
				bp_squeal_p2 += sq_c * (bp_squeal_p1 - bp_squeal_p2)
				var squeal_band: float = (bp_squeal_p1 - bp_squeal_p2) * 5.0
				frame_out += squeal_band * squeal_vol

			# Limiter stutter (highpass)
			if limiter_vol > 0.001:
				hp_limiter = 0.88 * (hp_limiter + white_noise - hp_limiter_in)
				hp_limiter_in = white_noise
				frame_out += hp_limiter * limiter_vol

		# 2. Shift clack / thump transient
		if shift_active:
			shift_time += dt
			var progress := shift_time / shift_duration
			if progress >= 1.0:
				shift_active = false
			else:
				var env := sin(progress * PI)
				var f1 := lerpf(150.0 if shift_is_up else 105.0, 48.0, progress)
				var f2 := lerpf(1250.0 if shift_is_up else 760.0, 240.0, progress)
				var s1 := sin(shift_time * f1 * TWO_PI) * 0.12 * env
				var s2 := (1.0 if fmod(shift_time * f2, 1.0) < 0.5 else -1.0) * 0.04 * env
				var s3 := 0.0
				if shift_is_up and shift_load > 0.35:
					var f3 := lerpf(680.0, 90.0, progress)
					s3 = (2.0 * fmod(shift_time * f3, 1.0) - 1.0) * 0.04 * env
				frame_out += s1 + s2 + s3

		# 3. Pit radio beeps
		if beep_count > 0:
			beep_timer += dt
			var cycle_t := fmod(beep_timer, 0.2)
			var current_beep_idx := int(beep_timer / 0.2)
			if current_beep_idx >= beep_count:
				beep_count = 0
			elif cycle_t < 0.12:
				beep_phase = fmod(beep_phase + beep_freq * dt, 1.0)
				var beep_wave := 0.14 if beep_phase < 0.5 else -0.14
				frame_out += beep_wave

		var final_sample := clampf(frame_out * current_master, -0.95, 0.95)
		_mix_buffer[i] = Vector2(final_sample, final_sample)

	playback.push_buffer(_mix_buffer)
