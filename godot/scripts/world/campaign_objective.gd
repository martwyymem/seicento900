## What the campaign asks of the player next, for the open world's objective panel (OpenWorldHud.set_objective) and its
## GPS: the next stage to drive to (at its beacon, or at the Away Races gate for a stage abroad), else the next open
## mission, else the live-event medals the next mission waits for (Missions.MEDALS_NEEDED), else the fans the Goliath
## waits for. A pure function of the campaign save, the fans and the medal points held, so tests can drive it.
## Stages abroad (AWAY) do not get a beacon each: they all start from one Away Races gate beside the Fest, where a
## short trip (AwayCutscene: onto the train or into the plane) plays before the stage loads.
class_name CampaignObjective
extends RefCounted

## Campaign tracks that are raced abroad: how the car travels there (AwayCutscene's "train" or "plane") and where to.
const AWAY := {
	"monza": {"by": "plane", "to": "Milan", "line": "Pan Zbyszek's charter from Katowice to Milan"},
	"nordschleife": {"by": "train", "to": "the Eifel", "line": "the night car-train west to the Eifel"},
	"lemans": {"by": "train", "to": "Le Mans", "line": "the car-train west to France"},
	"tokyo": {"by": "plane", "to": "Tokyo", "line": "the charter flight to Tokyo"},
}
const AWAY_SPOT := "festival" ## the Away Races gate stands on the Fest's road (map.spots), AWAY_ALONG metres on
const AWAY_ALONG := 46.0
const AWAY_TITLE := "Away Races"
const AWAY_NOTE := "the Away Races gate at the KS Górnik stadium"

## text with its first letter in upper case (String.capitalize would title-case every word and lose "KS").
static func upper_first(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)

static func is_away(track: String) -> bool:
	return AWAY.has(track)

static func stage_is_away(index: int) -> bool:
	return index >= 0 and index < Campaign.STAGES.size() and is_away(String(Campaign.STAGES[index].track))

## The away stage the gate holds: the objective's when it is abroad, else the first open one not won yet, else the
## last open one (to race again); -1 while none is open.
static func away_stage(prog: Dictionary, fans: int) -> int:
	var last := -1
	for i in Campaign.STAGES.size():
		if not stage_is_away(i) or not Story._stage_open(prog, i, fans):
			continue
		if not Story._won(prog, i):
			return i
		last = i
	return last

## The first away stage of all (the gate's stage while none is open: it shows locked).
static func first_away() -> int:
	for i in Campaign.STAGES.size():
		if stage_is_away(i):
			return i
	return -1

## How the stage travels ({by, to, line}); {} for a stage at home.
static func travel(index: int) -> Dictionary:
	if not stage_is_away(index):
		return {}
	return AWAY[String(Campaign.STAGES[index].track)]

## Each stage spot (OpenWorld.STAGE_SPOTS) as the objective names it, short: "drive to the Bór start".
const SPOT_SHORT := {"exit_wilamowice": "the S1 exit south to Wilamowice", "industrial_sprint": "the start on ul. Dworcowa",
	"bor_stage": "the Bór start on ul. Bór", "exit_pszczyna": "the DW933 exit west to Pszczyna",
	"exit_bielsko": "ul. Bielska, south to Bielsko-Biała", "exit_oswiecim": "the DW933 exit east to Oświęcim",
	"station": "Brzeszcze Jawiszowice station", "exit_tychy": "the S1 exit north to Tychy", "festival": "the Fest at the KS Górnik stadium"}

## Where a stage starts, for "drive to ...": the Away Races gate for a stage abroad, else its beacon's spot.
static func where(index: int) -> String:
	if stage_is_away(index):
		return "the Away Races gate at the Fest"
	if OpenWorld.is_sprint_spot(Campaign.STAGES[index]): # a sprint on the map's roads: its start line, by its note
		return "the start on " + String(Campaign.STAGES[index].get("note", "its beacon")).split(":")[0]
	var spot := String(OpenWorld.STAGE_SPOTS.get(String(Campaign.STAGES[index].track), "festival"))
	return String(SPOT_SHORT.get(spot, String(OpenWorld.SPOT_NOTE.get(spot, "its beacon")).split(":")[0]))

## The objective: {kind, index, head, line, side}.
##   kind "stage" (index: the stage), "mission" (index: Missions.BASE + k), "medals" (index: the mission waiting for
##   them), "fans" (the Goliath), "done", or "" when there is nothing (never: a finished campaign is "done").
##   head: the small caption over it, line: what to do (the title and where), side: a second, smaller line (the next
##   mission or the medals it waits for while a stage is the objective; "" for none).
static func current(prog: Dictionary, fans: int, points: int) -> Dictionary:
	var out := {"kind": "", "index": -1, "head": "", "line": "", "side": ""}
	var last := Campaign.STAGES.size() - 1
	var mission := _open_mission(prog, points)
	var waiting := _medal_mission(prog, points)
	for i in Campaign.STAGES.size():
		if Story._stage_open(prog, i, fans) and not Story._won(prog, i):
			out.kind = "stage"
			out.index = i
			out.head = "CAMPAIGN · %s" % String(Campaign.STAGES[i].act_name).to_upper()
			out.line = "%s — drive to %s" % [String(Campaign.STAGES[i].title), where(i)]
			if mission >= 0:
				out.side = "Mission open: %s" % _mission_title(mission)
			elif waiting >= 0:
				out.side = "%s to open %s" % [_medals_short(waiting, points), String(Missions.get_def(waiting).title)]
			return out
	if mission >= 0:
		out.kind = "mission"
		out.index = mission
		out.head = "CAMPAIGN · MISSION"
		out.line = "%s — drive to its beacon" % _mission_title(mission)
		return out
	if waiting >= 0:
		out.kind = "medals"
		out.index = waiting
		out.head = "CAMPAIGN · LIVE EVENTS"
		out.line = "%s to open the next mission (%d/%d)" % [_medals_short(waiting, points), mini(points, Missions.medals_needed(waiting)),
			Missions.medals_needed(waiting)]
		out.side = "Next mission: %s · bronze 1, silver 2, gold 3" % String(Missions.get_def(waiting).title)
		return out
	if not Story._won(prog, last) and not Story._stage_open(prog, last, fans):
		out.kind = "fans"
		out.index = last
		out.head = "CAMPAIGN · THE GOLIATH"
		var need := int(FanLevels.THRESHOLDS[FanLevels.THRESHOLDS.size() - 1])
		out.line = "Win fans to open the Goliath: fan level %d (%s / %s)" % [FanLevels.THRESHOLDS.size(),
			OpenWorldHud._thousands(mini(fans, need)), OpenWorldHud._thousands(need)]
		out.side = "Skills, live events and missions all bring fans"
		return out
	out.kind = "done"
	out.head = "CAMPAIGN · EPILOGUE"
	out.line = "The story is told: drive, race the live events, chase the medals"
	return out

## The first open mission not cleared yet, in the order of play; -1 for none.
static func _open_mission(prog: Dictionary, points: int) -> int:
	for idx in Missions.play_order():
		if Missions.is_unlocked(idx, prog, points) and not Missions.is_cleared(idx, prog):
			return idx
	return -1

## The first mission whose stage is cleared but whose medals are missing; -1 for none.
static func _medal_mission(prog: Dictionary, points: int) -> int:
	for idx in Missions.play_order():
		if Missions.medal_locked(idx, prog, points):
			return idx
	return -1

static func _mission_title(idx: int) -> String:
	var m: Dictionary = Missions.get_def(idx)
	return "%s: %s" % [String(Missions.KIND_NAMES[m.kind]).capitalize(), String(m.title)]

## "Earn 1 more live-event medal point" / "Earn 3 more live-event medal points".
static func _medals_short(idx: int, points: int) -> String:
	var left := maxi(Missions.medals_needed(idx) - points, 0)
	return "Earn %d more live-event medal point%s" % [left, "" if left == 1 else "s"]
