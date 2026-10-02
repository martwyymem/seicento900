## One car in the race: position, motion, drivetrain, tyres, fuel, strategy and timing (the JS car object).
## Positions use the JS/2D frame: x east, y south, heading in radians from +x.
class_name RaceCar
extends RefCounted

var id := 0
var name := ""
var color := Color.WHITE
var number := 0
var is_player := false
var stripes := false

# ---- driver
var skill := 1.0
var agg := 1.0
var pace := 1.0
var pace_scale := 1.0
var reaction := 0.0
var mistake_rate := 0.0
var wet_threshold := 0.4
var quali := 0.0
var brain: BotBrain = null ## learning-AI state (bots only, when learning is on)

# ---- track position and motion
var s := 0.0 ## distance along the centreline
var lap := 0
var d := 0.0 ## lateral offset from the centreline (+ = right in the direction of travel)
var v := 0.0 ## rail speed
var speed := 0.0 ## signed forward speed
var x := 0.0
var y := 0.0
var heading := 0.0
var vx := 0.0
var vy := 0.0
var yaw_rate := 0.0
var steer := 0.0
var d_kick := 0.0
var lat_v := 0.0
# previous tick, for render interpolation
var px := 0.0
var py := 0.0
var ph := 0.0
var ps := 0.0
var has_prev := false

# ---- control
var mode := "race" ## race | pit
var control := "rail" ## rail | free
var autopilot := false
var phys: PhysState = null
var rev := false

# ---- drivetrain and feedback
var gear := 0
var rpm := 850.0
var throttle := 0.0
var brake_on := false
var shift_t := 0.0
var slip := 0.0
var understeer := 0.0
var body_roll := 0.0
var body_pitch := 0.0

# ---- tyres, fuel, strategy
var tyre := {"c": "M", "wear": 1.0, "temp": 0.6}
var fuel := 10.0
var used_mask := 0
var plan: Array = [] ## [{c, laps}]
var stint_idx := 0
var stint_start_lap := 0
var stops := 0
var history: Array = []
var strategy_label := ""
var pit_request := false
var service = null ## {c, fuel_target, litres, time} or null
var service_edited := false
var pit = null ## {phase: in|service|out, entered_at, left, total, hold, wait} or null
var plan_wet := 0.0
var plan_stale := false
var rate_mark = null ## {lap, stops, wear, fuel} at the last strategy check, to measure a lap's real use
var obs_wear := 0.0 ## tread fraction the current tyres really lose per lap (0 = not measured yet)
var fuel_lap := 0.0 ## litres a lap really costs this car (0 = not measured yet)
var plan_wear_ratio := 1.0 ## real / nominal tyre wear the plan was made with
var plan_fuel_ratio := 1.0
var pit_bias := 0 ## laps a bot will stretch a stint past its plan when the tyres and tank allow
var grid := 0
var box := 0

# ---- timing and result
var lap_start := 0.0
var last_lap = null
var best_lap = null
var lap_times: Array = []
var invalid_lap := false
var finished := false
var finish_order := 0
var finish_time = null
var finish_lap := 0
var running := false
var penalty := 0.0
var penalties: Array = []
var dnf := false
var dnf_reason := ""
var out_of_fuel := false
var gap := 0.0
var cp_idx := -1
var pos := 0

# ---- racecraft
var overtake_d := 0.0
var overtake_t := 0.0
var overtake_t0 := 0
var slow_t := 0.0
var mistake_p = null ## track distance of the next driving error, or null
var err = null ## {kind: late|wide, d, t} or null
var slip_drag := 1.0
var tow := 0.0 ## 0..1: how much of a leading car's wake this car is sitting in (it fills and fades over about a second)
var recover_t := 0.0
var stuck_t := 0.0
var last_hit := 0.0
var off_target := 0.0

# ---- race control (see RaceControl)
var damage := 0.0 ## 0 = straight, 1 = wrecked; costs power, drag and pace until repaired in the pits
var dmg_pull := 0.0 ## steering pull from bent suspension (steer units, + = right)
var wrecked := false ## crashed out: the car stays where it stopped until the marshals recover it
var stranded := false ## a retired car still sitting on the circuit (an obstacle, flagged yellow)
var recovered := false ## cleared away by the marshals
var recover_left := 0.0
var is_safety_car := false
var sc_lights := false
var sc_waved := false ## lapped car between the safety car and the leader, waved past to the tail
var spin_t := -100.0 ## race clock of the last moment this car was out of control (spun, off, wrecked)
var offences := 0 ## penalties and warnings for causing collisions, so repeat offenders pay more
var repair_asked := false
var uturn := false ## a bot facing the wrong way is driving itself round to face the right way again
