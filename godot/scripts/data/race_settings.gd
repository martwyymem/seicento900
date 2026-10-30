## Everything that defines a race (the race-related half of the JS settings object).
## Save a copy as a .tres to keep a quick-race setup around for testing.
class_name RaceSettings
extends Resource

@export var track := "gp"
@export_enum("laps", "time") var format := "laps"
@export var laps := 6
@export var hours := 1.0 ## race length when format = time
@export_range(0, 24, 0.25) var start_hour := 14.0

@export_group("Field")
@export_range(0, 15) var opponents := 15
@export_enum("easy", "medium", "hard", "alien") var difficulty := "medium"
@export_enum("pole", "middle", "back", "random") var grid := "middle" ## or "p<N>": start in slot N (campaign stages start where their target is)
@export var collisions := true
@export var draft := true ## slipstream: a car behind another one, close and in line, pulls less air and gains speed
@export var race_control := true ## flags, safety car, red flags, stewards' penalties and crash damage
@export var real_drivers := true ## the field is Drivers.ROSTER, each on their set-up and character; off: the JS reference's field (Race.BOTS)
@export_enum("on", "off") var ai_learning := "on"
@export_enum("on", "off", "near") var bot_physics := "on" ## near: only bots close to the player run the physics (saves battery)
@export var demo := false ## menu background race: bots on rails, nothing learned
@export var qualifying := false ## a single-car qualifying session instead of a race (see Qualifying.configure)
@export var quali_grid := {} ## {order: car ids fastest first, skills, quali} from a championship round's qualifying; empty = use `grid`

@export_group("Mode")
## race: the usual race (everything below at its default keeps it exactly as before).
## rally: one special stage of a RallyEvent, the player alone against the clock (Rally.configure_stage).
## time_trial: solo hot-lapping, no pit rules, wear or fuel use, laps until quit (TimeTrial.configure).
@export_enum("race", "rally", "time_trial") var mode := "race"
@export var stage_from := 0.0 ## rally: where the stage starts, metres after the start line
@export var stage_to := 0.0 ## rally: where it finishes, metres after the start line (0: back at the start line, a full lap)
@export_enum("tarmac", "gravel") var surface := "tarmac" ## the road itself (rally stages); tarmac changes nothing
@export var rolling_start := false ## time trial: start at speed, on an out-lap run-up to the line

@export_group("Conditions")
@export_enum("dry", "wet", "snow", "hail", "fog", "variable") var weather := "dry"
@export_enum("M", "S", "H", "W") var starting_tyre := "M"
@export var wear_mult := 2.0
@export var fuel_mult := 1.0
@export var dynamic_running := true ## wear and fuel follow the real load, and stops follow the live state instead of the starting plan

@export_group("Rules and pits")
@export var mandatory_stop := true
@export var two_compounds := false
@export var refuel := true
@export_enum("pro", "club", "amateur") var crew := "club"
@export var parallel := false ## fuel and tyres at the same time
@export var auto_strategist := false ## the strategist boxes the player on its own; off = it only advises, the player calls the stop

@export_group("Player")
@export var player_name := "Player"
@export var player_number := 9
@export var player_color := Color("#b3121d")
@export var stripes := true
@export_enum("stock", "hypercar") var car_class := "stock" ## "hypercar": the whole field drives the Hypercar Seicento (Hypercar), once the top fan level has unlocked it
@export var finish := 0 ## 0 gloss, 1 metallic, 2 Martini Racing, 3 Abarth, 4 Marlboro
@export_enum("auto", "manual") var gearbox := "auto"
@export_enum("full", "abs", "off") var assists := "full"
@export var brake_assist := true ## with full assists, brake for a corner the car is arriving at too fast
@export var auto_rejoin := true ## a beached player car is put back on the track, as the bots are (a car that merely faces the wrong way is not)
@export var car_setup := {} ## CarSetup notches for the player's car (empty = stock)
