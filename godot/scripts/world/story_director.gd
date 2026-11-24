## Tells the campaign's story (Story) in the open world: it owns the StoryCard and decides when a beat plays.
##  - free roam: about once a second it asks Story.pending what the save has earned (the intro on a new campaign,
##    the first visit to the Fest, results, cars won, act changes, the epilogue) and plays those beats on the card
##    once the car is below CARD_KMH and no event or results card is up; phone messages (a stage or mission opening)
##    go on the HUD banner. Every beat is marked seen as it starts, so nothing auto-plays twice.
##  - entering a stage or mission: before_event plays its "_before" beat first, then starts the event.
##  - the pause menu's STORY: open_journal replays the seen beats under the act and what comes next.
## OpenWorld makes it in _ready (attach) and calls brief_text, before_event and open_journal: nothing else.
class_name StoryDirector
extends Node

const CARD_KMH := 30.0 ## a beat waits until the car is this slow
const FEST_REACH := 140.0 ## m from the Fest spot that counts as a visit
const TICK := 1.0

var ow: OpenWorld
var card: StoryCard
var _t := 0.5

static func attach(world: OpenWorld) -> StoryDirector:
	var d := StoryDirector.new()
	d.name = "Story"
	d.ow = world
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(d)
	d.card = StoryCard.new()
	d.card.name = "StoryCard"
	world.add_child(d.card) # after the HUD: drawn over it, and its _input runs before the open world's
	return d

## A beacon's briefing body with the event's story line above it (stages and missions).
static func brief_text(index: int, body: String) -> String:
	return Story.brief_text(index, body)

func _fans() -> int:
	return int(ow.progress.fans) if ow and ow.progress else 0

## The live-event medal points held (this world's copy of WorldProgress.live: newer than the save between writes).
func _points() -> int:
	return Missions.medal_points(ow.progress.live) if ow and ow.progress else -1

func _process(delta: float) -> void:
	if ow == null:
		return
	if not ow.active:
		if card.is_open():
			card.play([]) # dropped quietly: the race or menu took over
		return
	if not ow.built or ow.paused or ow.hud.map_open or ow._setup_open() or card.is_open() or ow.drive == null or ow.cutscene != null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var lv = ow.get("live")
	if lv is LiveEvents and (lv as LiveEvents).is_running():
		return
	var res = ow.get("_result")
	if res is Dictionary and not (res as Dictionary).is_empty():
		return
	var prog := Campaign.load_progress()
	var fans := _fans()
	var near := false
	var fest = ow.map.spots.get("festival", []) if ow.map else []
	if fest is Array and (fest as Array).size() >= 2:
		near = Vector2(float(fest[0]), float(fest[1])).distance_to(Vector2(ow.drive.car.x, ow.drive.car.y)) < FEST_REACH
	var keys := Story.pending(prog, fans, near, _points())
	if Story.needs_catch_up(prog):
		Story.mark_seen(keys)
		ow.hud.notify("STORY", "Catch up on the story so far: pause ▸ STORY", Color(Story.NARRATOR_COLOR))
		return
	if keys.is_empty():
		return
	var radios: Array[String] = []
	var beats: Array[String] = []
	for k in keys:
		if Story.is_radio(k):
			radios.append(k)
		else:
			beats.append(k)
	if not beats.is_empty():
		if absf(ow.drive.speed_kmh()) > CARD_KMH:
			return # the phone waits with them: one thing at a time
		Story.mark_seen(beats)
		card.play(Story.cards(beats))
		return
	var shown: Array[String] = []
	for k in radios.slice(0, 2):
		var ln: Array = Story.lines(k)[0]
		var who := Story.character(String(ln[0]))
		ow.hud.notify("PHONE · %s" % String(who.name).to_upper(), String(ln[1]), Story.color_of(String(ln[0])))
		shown.append(k)
	Story.mark_seen(shown)

## Plays an event's "_before" beat when the player enters it, then calls start (the open world's
## _start_active_event) if the car is still at that beacon. False when there is nothing to play: start now.
func before_event(index: int, start: Callable) -> bool:
	if card.is_open():
		return true
	var key := Story.before_key(index)
	if key == "":
		return false
	Story.mark_seen([key])
	var at := ow.active_event
	card.play(Story.cards([key]), func():
		if ow.active and ow.active_event == at:
			start.call())
	return true

## The pause menu's STORY page: the act, what comes next, and every beat seen so far.
func open_journal() -> void:
	card.play(Story.journal(Campaign.load_progress(), _fans()), Callable(), true)
