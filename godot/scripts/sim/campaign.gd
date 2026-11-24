## Campaign mode ("The Seicento Odyssey"): a 16-stage racing career tracing a grassroots Polish racer's journey
## from Silesian village lanes through Monza, the Nürburgring, Le Mans and Tokyo, and home to Brzeszcze for the
## Goliath. The map missions beside the stages (Missions) award the cars. The story told round it is Story.
## The save (campaign.json) indexes stages by their place in STAGES; "arc" says which layout it was written for, and
## a save from an older arc (the first, ten-stage one, or the second, fourteen-stage one) is mapped onto this one by
## stage id when it loads (migrate). A stage is a lap race ("laps"), or with "format": "sprint" an A->B sprint against
## the whole field from point A to point B on the track's road ("from" / "to", m after the track's start line, or
## "baked": true for the span a point-to-point track carries, Rally.baked_span): no laps, results by finishing order.
class_name Campaign
extends RefCounted

const SAVE_FILE := "campaign.json"
static var save_file := SAVE_FILE ## tests point this at a file of their own (the dev sandbox is shared)

const STAGES := [
	{
		"id": "stage_1",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 1: Rookie Shakedown",
		"track": "wilamowice",
		"laps": 1,
		"format": "sprint",
		"from": 250.0,
		"to": 6000.0,
		"weather": "dry",
		"time_of_day": 14.0,
		"start_hour": 14.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 5,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p5",
		"trophy": "Wilamowice Bronze Piston",
		"class": "city",
		"rivals": {"stock": 5},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Wujek Mirek handed you the keys to Ciocia Basia's stock 1998 Fiat Seicento 900 (39 bhp). Prove your racecraft in a sprint across Wilamowice: from the Rynek past Holy Trinity church, down Kęcka and Krakowska into Hecznarowice, back through the fields to the flag by the pond on Sobieskiego.",
		"tip": "The lefts at Hecznarowice and Handlowa are sharp: brake early, then carry momentum along the open field lane."
	},
	{
		"id": "stage_2",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 2: Coal & Crossroads",
		"track": "brzeszcze",
		"laps": 1,
		"format": "sprint",
		"from": 150.0,
		"to": 5300.0,
		"weather": "fog",
		"time_of_day": 8.0,
		"start_hour": 8.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 7,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p7",
		"trophy": "Mining Headframe Cup",
		"class": "city",
		"rivals": {"stock": 6, "sandero": 1},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Dense morning fog blankets the mining town. A sprint from the Andrzej shafts on ul. Ofiar Oświęcimia, round Leśna, Kościuszki and Piastowska, back by Daszyńskiego to the flag on Przecieszyńska.",
		"tip": "The town's right-angle junctions loom out of the fog late: brake while the corner is still a guess, not when you see it."
	},
	{
		"id": "stage_wola",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 3: Sprint do Woli",
		"track": "wola_sprint",
		"laps": 1,
		"format": "sprint",
		"baked": true,
		"weather": "dry",
		"time_of_day": 17.5,
		"start_hour": 17.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 7,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p7",
		"trophy": "Wola Fishpond Pennant",
		"class": "city",
		"rivals": {"stock": 6, "sandero": 1},
		"pace": 0.75, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"note": "ul. Wojciecha Korfantego, Babudy: the start of the sprint to Wola",
		"desc": "Village roads, closed for an evening: from Babudy north up ul. Starorzeczna under the S1 and across the fields into Wola, east on Mokra, up Powstańców, then flat out down ul. Pszczyńska through the village past the school to the flag at the Kopalniana junction.",
		"tip": "Starorzeczna is a long straight: get in the tow early. The right onto Mokra comes at the end of it, and Pszczyńska through the village is faster than it looks."
	},
	{
		"id": "stage_3",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 4: The Forest of Bór",
		"track": "bor",
		"laps": 2,
		"weather": "variable",
		"time_of_day": 16.5,
		"start_hour": 16.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 8,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p7",
		"trophy": "Bór Forester Pine",
		"class": "city",
		"rivals": {"stock": 6, "sandero": 2},
		"pace": 0.5, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Blast through the pine woods of Brzeszcze Bór: past the OSP Bór fire station, over the railway twice at the Borska and Lachowicka level crossings, and past the fishponds back to ul. Bór.",
		"tip": "Guardrail lines the road and the verges are only grass: a mistake ends on the steel, so keep your throttle smooth between the trees."
	},
	{
		"id": "stage_4",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 5: Castle Park Trophy",
		"track": "pszczyna",
		"laps": 2,
		"weather": "dry",
		"time_of_day": 18.0,
		"start_hour": 18.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p8",
		"trophy": "Princess Daisy Crown",
		"class": "supermini",
		"rivals": {"sandero": 4, "i20": 4, "stock": 1},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Sunset battle over the setts of Piastowska and the Rynek, past the castle and the wisent enclosure on Żorska, then in through the park gate: the alley by the big pond, the hairpin under the castle, the bridges between the ponds and the gravel of the western lobe.",
		"tip": "Setts offer less bite than asphalt, and the park alleys are barely wider than the car: brake early for the hairpin and the narrow bridges."
	},
	{
		"id": "stage_5",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 6: Factory Homecoming",
		"track": "bielsko",
		"laps": 1,
		"format": "sprint",
		"from": 2500.0,
		"to": 1900.0,
		"weather": "variable",
		"time_of_day": 12.0,
		"start_hour": 12.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 2,
		"grid": "p8",
		"trophy": "Bielsko FSM Golden Gear",
		"class": "supermini",
		"rivals": {"i20": 4, "sandero": 4, "golf4": 1},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Back in the Seicento's home town, at the foot of Szyndzielnia. A sprint from ul. Gościnna by the Kamieniczanka: climb al. Armii Krajowej to the cable-car car park at Rondo Fieldorfa, then plunge 70 m down Karbowa past the Dębowiec ski slope to the flag on Karpacka.",
		"tip": "Use the draft up the long Armii Krajowej drag, then brake hard for Rondo Fieldorfa at the top: the descent to Karpacka comes at you fast."
	},
	{
		"id": "stage_gora",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 7: Sprint przez Górę",
		"track": "gora_sprint",
		"laps": 1,
		"format": "sprint",
		"baked": true,
		"weather": "variable",
		"time_of_day": 10.0,
		"start_hour": 10.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p8",
		"trophy": "Góra Church Bell",
		"class": "supermini",
		"rivals": {"i20": 4, "sandero": 4, "golf4": 1},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"note": "ul. Długa, Góra: the start of the sprint through the village",
		"desc": "The regional series comes to the Góra lads' own roads: from ul. Długa west and up ul. Krótka, north on Topolowa across the DW933 and past the church lane, then Zapadź and Dąbrowa between the Babudy fishponds to the flag at the Bażantów junction.",
		"tip": "Narrow village lanes with ditches either side: no room to pass in the bends, so make your move on Topolowa's straights and brake early for the kinks by the ponds."
	},
	{
		"id": "stage_rewanz",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 8: Kamil's Rematch",
		"track": "pszczyna",
		"laps": 2,
		"weather": "wet",
		"time_of_day": 21.5,
		"start_hour": 21.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 7,
		"difficulty": "medium",
		"target_pos": 2,
		"grid": "p7",
		"trophy": "Pszczyna Moonlight Cup",
		"class": "supermini",
		"rivals": {"golf4": 3, "i20": 2, "sandero": 2},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Kamil wants his town back. The castle park again, but on a Saturday night in the rain: wet setts on Piastowska and the Rynek, the park lamps off after ten, the narrow bridges between the ponds lit only by your headlights. A smaller field, all of them Kamil's friends.",
		"tip": "In the dark the bridges arrive before you see them: pick your braking points off the castle lights and the trees, and keep it straight on the wet setts."
	},
	{
		"id": "stage_6",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 9: Riverbank Grand Prix",
		"track": "oswiecim",
		"laps": 2,
		"weather": "wet",
		"time_of_day": 15.0,
		"start_hour": 15.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p9",
		"trophy": "Piast Shield",
		"class": "supermini",
		"rivals": {"golf4": 3, "logan": 2, "i20": 2, "sandero": 2},
		"pace": 1.0, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Torrential rain over the Soła. Two laps of the old town: up ul. Legionów, over Most Piastowski, up past the castle hill, along the setts of Plebańska and round the Rynek, down ul. Jagiełły, and back over Most Jagielloński.",
		"tip": "The setts of Plebańska and the Rynek are slick in the wet: brake in a straight line before you reach them, and keep it tidy through Rondo Płonki onto the bridge."
	},
	{
		"id": "stage_7",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 10: The Royal Crown",
		"track": "krakow",
		"laps": 2,
		"weather": "dry",
		"time_of_day": 19.5,
		"start_hour": 19.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p10",
		"trophy": "Wawel Dragon Sceptre",
		"class": "supermini",
		"rivals": {"i20": 3, "golf4": 3, "sandero": 2, "logan": 2, "zafira": 1},
		"pace": 0.5, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "Dusk falls over Kraków as the championship roars round the ring road outside the Planty: Basztowa past the Barbakan and Brama Floriańska, Podwale and Straszewskiego, then the setts of Podzamcze and św. Idziego under Wawel.",
		"tip": "Tram rails run along half the lap. Brake before the setts under Wawel, and tuck into the slipstream on the long run along św. Gertrudy over the line."
	},
	{
		"id": "stage_8",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 11: Proving Grounds Trial",
		"track": "fiat",
		"laps": 4,
		"weather": "dry",
		"time_of_day": 13.0,
		"start_hour": 13.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p10",
		"trophy": "Tor Fiata Test Cup",
		"class": "touring",
		"rivals": {"zafira": 5, "i20": 3, "golf4": 2, "v50": 1},
		"pace": 0.75, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"desc": "An exclusive invitation to the factory test track (Tor Fiata in Tychy) to battle factory test drivers in tuned machinery.",
		"tip": "The slipstream is strongest on the kilometre-long back straight: time your pass before the West Turn, a long, flat 185° right-hander."
	},
	{
		"id": "stage_monza",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 12: Temple of Speed",
		"track": "monza",
		"laps": 2,
		"weather": "dry",
		"time_of_day": 11.0,
		"start_hour": 11.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "medium",
		"target_pos": 2,
		"grid": "p10",
		"trophy": "Parabolica Laurel",
		"class": "touring",
		"rivals": {"zafira": 5, "v50": 4, "i20": 2},
		"pace": 0.75, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"note": "North on the S1 to Katowice airport: the flight to Milan",
		"desc": "Fiat's home crowd. The factory's people in Turin heard about the Polish Seicento and want it at the Autodromo in the royal park at Monza: the Rettifilo chicane, Curva Grande, the two Lesmos, Ascari and the long Parabolica onto the straight.",
		"tip": "Monza is all straights and chicanes: brake hard and straight for the Rettifilo, then be patient through the Parabolica: a late apex is a fast exit and a tow down the straight."
	},
	{
		"id": "stage_eifel",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 13: The Green Hell",
		"track": "nordschleife",
		"laps": 1,
		"weather": "fog",
		"time_of_day": 8.5,
		"start_hour": 8.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 3,
		"grid": "p11",
		"trophy": "Eifel Forest Medal",
		"class": "touring",
		"rivals": {"v50": 5, "focus": 4, "zafira": 2},
		"pace": 0.5, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"note": "Brzeszcze Jawiszowice station: the night train west to the Eifel",
		"desc": "One lap of the Nürburgring Nordschleife in the morning fog: twenty kilometres through the Eifel forests, from Hatzenbach and Flugplatz down the Fuchsröhre, through Adenauer Forst, the Karussell and Brünnchen, over Pflanzgarten and home up the Döttinger Höhe.",
		"tip": "Learn it as a string of short stages: the Karussell's concrete banking wants you in it and staying in it, and the Döttinger Höhe is the one place to use the tow."
	},
	{
		"id": "stage_lemans",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 14: Through the Night",
		"track": "lemans",
		"laps": 1,
		"weather": "dry",
		"time_of_day": 22.5,
		"start_hour": 22.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 2,
		"grid": "p11",
		"trophy": "Mulsanne Night Lantern",
		"class": "touring",
		"rivals": {"focus": 4, "v50": 4, "zafira": 3},
		"pace": 0.5, ## levels over its difficulty (tuned with tests/_campaign_ladder_probe.gd)
		"note": "Seicento Fest at the KS Górnik stadium: Pan Zbyszek's coach to Le Mans",
		"desc": "The Circuit de la Sarthe after dark: under the Dunlop bridge, through Tertre Rouge onto the Mulsanne straight and its two chicanes, Mulsanne corner, Indianapolis and Arnage, then the Porsche Curves and the Ford chicanes home. Thirteen kilometres by headlight.",
		"tip": "The Mulsanne is the longest you will ever hold it flat: take the tow, and brake by the boards for Mulsanne corner, not by feel. The Porsche Curves at night are where the lap is lost."
	},
	{
		"id": "stage_9",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 15: Midnight Showdown",
		"track": "tokyo",
		"laps": 1,
		"weather": "dry",
		"time_of_day": 0.0,
		"start_hour": 0.0,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 1,
		"grid": "pole",
		"trophy": "Tokyo Midnight Emperor",
		"class": "touring",
		"rivals": {"focus": 5, "v50": 4, "zafira": 2},
		"adaptive": false, ## reported unwinnable in the 2026-11-24 playtest: big wins do not tighten it further (its balance is a follow-up)
		"desc": "The international showdown, a long way from Brzeszcze. One midnight lap of the Shuto C1 inner loop: the viaducts over the Nihonbashi river, the tunnels under the Imperial Palace moats, Hamazakibashi JCT and the Ginza trench.",
		"tip": "Two lanes between concrete walls. Lift for the blind left at Miyakezaka in the tunnel, and carry speed round the Hamarikyu Spiral: it drops two full turns into the Ginza trench."
	},
	{
		"id": "stage_10",
		"act": 4,
		"act_name": "Finale: Seicento Legend",
		"title": "Stage 16: The Goliath",
		"track": "goliath",
		"laps": 1,
		"weather": "dry",
		"time_of_day": 18.5,
		"start_hour": 18.5,
		"wear_mult": 0.0,
		"fuel_mult": 0.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 1,
		"grid": "pole",
		"trophy": "The Goliath Crown",
		"class": "hypercar",
		"rivals": {"hypercar": 11},
		"car_class": "hypercar",
		"fan_lock": true,
		"adaptive": false, ## authored for the Hypercar: big wins earlier in the campaign do not tighten it
		"note": "Seicento Fest at the KS Górnik stadium: the Goliath's grid",
		"desc": "The homecoming, and Pan Zbyszek's dream come true. One lap, 27 km, the whole of Brzeszcze closed for the night: the town, the S1 flat out, the villages and the Bór ponds, and back down the east side. Twelve Hypercar Seicentos in AF Corse yellow, and you on pole with eleven Legends behind you for 27 km.",
		"tip": "The S1 is where races are won: 340 km/h, then the hardest stop of the lap into the junction. Save the tyres in town."
	}
]

## The car classes the stages' fields are built from (CarCatalog keys), slowest first. A stage names the class
## it expects ("class", shown on its briefing) and its field ("rivals": CarCatalog key -> how many): the expected
## class, with a few cars of the class above in the later stages. Nothing is locked: the player enters any car
## they have (cars are still won only by the map missions, which open them after stages 1, 3, 5, 6, 8, 9 and 11).
const CAR_CLASSES := {
	"city": {"name": "City car", "cars": ["stock"]},
	"supermini": {"name": "Supermini", "cars": ["sandero", "i20", "golf4", "logan"]},
	"touring": {"name": "Touring", "cars": ["zafira", "v50", "focus"]},
	"hypercar": {"name": "Hypercar", "cars": ["hypercar"]},
}
const CLASS_ORDER := ["city", "supermini", "touring", "hypercar"]

## Adaptive field (the "heat", in difficulty levels, campaign-wide): a dominant win tightens every later stage,
## a failed try gives some of it back, and failed tries on a stage still ease it down to Easy (get_stage).
const BIG_WIN := 6.0 ## s: a win by this much over P2 is a big win
const RUNAWAY_WIN := 15.0 ## s: and by this much counts twice
const HEAT_STEP := 0.25 ## levels a big win adds (the second big win in a row adds twice this)
const HEAT_MAX := 1.0 ## at most one full level (Medium -> Hard)
const HEAT_FAIL := 0.5 ## levels a failed try takes off

## The stage layout a save was written for: 1 (no "arc" key) is the first, ten-stage arc; 2 the fourteen-stage one
## (before the Wola and Góra sprints); 3 is this one.
const ARC := 3
## The first arc's stages in their old order: a save without "arc" keys unlocked, best_pos and fails by these places.
const ARC1_ORDER := ["stage_1", "stage_2", "stage_3", "stage_4", "stage_5", "stage_6", "stage_7", "stage_8", "stage_9", "stage_10"]
## The second arc's stages in their order: an arc-2 save's unlocked, best_pos and fails are by these places.
const ARC2_ORDER := ["stage_1", "stage_2", "stage_3", "stage_4", "stage_5", "stage_rewanz", "stage_6", "stage_7", "stage_8",
	"stage_monza", "stage_eifel", "stage_lemans", "stage_9", "stage_10"]
## The stage (its place in ARC1_ORDER) each first-arc mission waited for: a mission an old save had open stays open.
const ARC1_MISSION_AFTER := {"drag_quarter": 0, "sprint_s1": 1, "drift_babudy": 2, "offroad_kolonia": 3, "knockout_bor": 4,
	"rally_bor": 5, "drag_kilometre": 7}

static func empty_progress() -> Dictionary:
	return {"unlocked": 0, "best_pos": {}, "trophies": [], "arc": ARC, "heat": 0.0, "streak": 0, "gate": GATE}

static func load_progress() -> Dictionary:
	var path := SaveData.read_path(save_file)
	if not FileAccess.file_exists(path):
		return empty_progress()
	var json = SaveData.read_json(path)
	if json is Dictionary:
		return migrate_gate(migrate(clean_progress(json)))
	return empty_progress()

## A loaded save with every field the game reads as the type it expects (a damaged or hand-edited file may hold
## anything under a key): a field of the wrong kind is dropped (or reset for the stage counters) so its default applies.
static func clean_progress(json: Dictionary) -> Dictionary:
	var out := json.duplicate()
	for k: String in ["unlocked", "arc", "gate"]:
		if out.has(k):
			out[k] = SaveData.to_int(out[k], 1 if k == "arc" else 0)
	for k: String in ["best_pos", "fails", "missions", "car", "story"]:
		if out.has(k) and not (out[k] is Dictionary):
			out.erase(k)
	for k: String in ["trophies", "cars"]:
		if out.has(k):
			if out[k] is Array:
				out[k] = (out[k] as Array).filter(func(x: Variant) -> bool: return x is String)
			else:
				out.erase(k)
	# the adaptive field (saves before it have neither: no heat, no streak)
	if out.has("heat"):
		var h := SaveData.to_float(out.heat, 0.0)
		out["heat"] = clampf(h, 0.0, HEAT_MAX) if is_finite(h) else 0.0
	if out.has("streak"):
		out["streak"] = maxi(SaveData.to_int(out.streak, 0), 0)
	return out

static func save_progress(data: Dictionary) -> void:
	var path := SaveData.path(save_file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))

## Wipes the campaign: unlocked stages, results, trophies, failed tries and the carried car.
static func reset_progress() -> void:
	save_progress(empty_progress())

## A stage's place in STAGES by its id, -1 when there is none.
static func index_of(id: String) -> int:
	for i in STAGES.size():
		if String(STAGES[i].id) == id:
			return i
	return -1

## A save from an older arc, in this arc's terms (a save already on it comes back as it is). The older arcs'
## stages keep their ids, so the stage indices (unlocked, best_pos, fails) are mapped through them: the furthest
## stage it had open stays the furthest open, and the stages new to this arc before it are open to race. Trophies,
## missions, cars, the story and the carried car are keyed by name and carry over untouched; a first-arc mission that
## was open stays open (its "open" flag) even where this arc opens it later. Saved back with "arc" the next time the
## campaign writes the file.
static func migrate(prog: Dictionary) -> Dictionary:
	var arc := int(prog.get("arc", 1))
	if arc >= ARC:
		return prog
	var order: Array = ARC1_ORDER if arc <= 1 else ARC2_ORDER
	var out := prog.duplicate(true)
	var old_unlocked := clampi(int(prog.get("unlocked", 0)), 0, order.size() - 1)
	out["unlocked"] = maxi(_old_index(order, old_unlocked), 0)
	for field: String in ["best_pos", "fails"]:
		var src = prog.get(field, {})
		if not src is Dictionary:
			continue
		var dst := {}
		for k in (src as Dictionary):
			var at: int = _old_index(order, int(String(k))) if String(k).is_valid_int() else -1
			if at >= 0:
				dst[str(at)] = src[k]
		out[field] = dst
	out["arc"] = ARC
	if arc >= 2:
		return out # (the second arc's missions already wait for stage ids: nothing to open by hand)
	var trophies: Array = prog.get("trophies", []) if prog.get("trophies", []) is Array else []
	var all = out.get("missions", {})
	if not all is Dictionary:
		all = {}
	for id: String in ARC1_MISSION_AFTER:
		var after: int = ARC1_MISSION_AFTER[id]
		var was_open := int(prog.get("unlocked", 0)) > after or String(STAGES[_arc1_index(after)].trophy) in trophies
		if was_open:
			var p: Dictionary = (all.get(id, {}) as Dictionary).duplicate() if all.get(id, {}) is Dictionary else {}
			p["open"] = true
			all[id] = p
	if not (all as Dictionary).is_empty():
		out["missions"] = all
	return out

## The live-event medal gate on the missions (Missions.MEDALS_NEEDED): 1 in every save written since it came in.
const GATE := 1

## A save from before the medal gate (no "gate" key): every mission its stages had already opened is kept open (its
## "open" flag, as migrate does for an older arc), so nobody is locked out of a mission they had reached; from then on
## the save carries "gate" and the missions after those wait for their medals. Saved back the next time the campaign
## writes the file. A save that has the key comes back as it is.
static func migrate_gate(prog: Dictionary) -> Dictionary:
	if prog.has("gate"):
		return prog
	var out := prog.duplicate(true)
	var all = out.get("missions", {})
	if not all is Dictionary:
		all = {}
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		if Missions.stage_reached(idx, out):
			var id := String(Missions.MISSIONS[k].id)
			var p: Dictionary = (all.get(id, {}) as Dictionary).duplicate() if all.get(id, {}) is Dictionary else {}
			p["open"] = true
			all[id] = p
	if not (all as Dictionary).is_empty():
		out["missions"] = all
	out["gate"] = GATE
	return out

## Where a first-arc stage index is in STAGES now (-1 for none).
static func _arc1_index(old: int) -> int:
	return _old_index(ARC1_ORDER, old)

## Where stage `old` of an older arc's order is in STAGES now (-1 for none).
static func _old_index(order: Array, old: int) -> int:
	if old < 0 or old >= order.size():
		return -1
	return index_of(String(order[old]))

## Whether a stage is an A->B sprint ("format": "sprint") rather than a lap race.
static func is_sprint(stage: Dictionary) -> bool:
	return String(stage.get("format", "laps")) == "sprint"

## A sprint's start A and finish B as Vector2(from, to), m after its track's start line (to <= from runs on over the
## line): its own "from" / "to", or with "baked" the span its point-to-point track carries (Rally.baked_span).
static func sprint_span(stage: Dictionary) -> Vector2:
	if stage.get("baked", false):
		var b := Rally.baked_span(String(stage.track))
		if b.size() == 2:
			return Vector2(float(b[0]), float(b[1]))
	return Vector2(float(stage.get("from", 0.0)), float(stage.get("to", 0.0)))

## A sprint's length from A to B, m (0 for a lap race).
static func sprint_length(stage: Dictionary) -> float:
	if not is_sprint(stage):
		return 0.0
	var sp := sprint_span(stage)
	return (sp.y if sp.y > sp.x else sp.y + Race.get_track(String(stage.track)).L) - sp.x

## How a stage's distance reads in the menus: "2 laps", "1 lap" or "5.2 km sprint".
static func length_label(stage: Dictionary) -> String:
	if is_sprint(stage):
		return "%.1f km sprint" % (sprint_length(stage) / 1000.0)
	var laps := int(stage.get("laps", 1))
	return "%d lap%s" % [laps, "" if laps == 1 else "s"]

## Puts a stage's format on the race settings the game built for it (after the stage's own fields, so a sprint's
## rules win): an A->B sprint grids the field behind A, finishes at B and counts no laps (RaceSettings.sprint), with
## the HUD's progress panel; a lap race is left as it is. No pit rules either way in a sprint: it never sees the pits.
static func apply_format(st: RaceSettings, stage: Dictionary) -> void:
	st.sprint = is_sprint(stage)
	if not st.sprint:
		return
	var sp := sprint_span(stage)
	st.stage_from = sp.x
	st.stage_to = sp.y
	st.laps = 1
	st.format = "laps"
	st.mission = "sprint"
	st.mandatory_stop = false
	st.two_compounds = false
	st.refuel = false

const LEVELS := ["easy", "medium", "hard", "alien"]
const FAILS_PER_EASE := 1 ## failed tries on a stage before its field drops one difficulty level

## A stage as it will be raced. Its field's level is the stage's difficulty moved by its own "pace" (levels) and
## the campaign's heat (big wins, see record_result); after every FAILS_PER_EASE failed tries it drops a level
## (down to Easy), so a stage that keeps beating the player gets kinder instead of blocking the campaign.
## base_difficulty is the stage's own level name, level the field's (0 easy .. 3 alien), difficulty the level's
## row below it and level_shift the rest (configure_stage), eased how many steps failures took off, heat the
## tightening it carries.
static func get_stage(index: int) -> Dictionary:
	if Missions.is_mission(index):
		return Missions.as_stage(index) # a mission (Missions.BASE + k) reads like a stage
	var st: Dictionary = (STAGES[index] if index >= 0 and index < STAGES.size() else STAGES[0]).duplicate()
	var prog := load_progress()
	var base: String = st.get("difficulty", "medium")
	var fails := int(prog.get("fails", {}).get(str(index), 0))
	var heat := float(prog.get("heat", 0.0)) if st.get("adaptive", true) else 0.0
	var lv := minf(float(maxi(LEVELS.find(base), 0)) + float(st.get("pace", 0.0)) + heat, float(LEVELS.size() - 1)) # Alien at most
	var steps := fails / FAILS_PER_EASE
	var eased := mini(steps, ceili(lv - 0.001)) if lv > 0.0 else 0
	lv = maxf(0.0, lv - steps) if steps > 0 else lv
	var at := clampi(floori(lv + 0.0001), 0, LEVELS.size() - 1)
	st["base_difficulty"] = base
	st["difficulty"] = LEVELS[at]
	st["level"] = lv
	st["level_shift"] = lv - float(at)
	st["heat"] = heat
	st["eased"] = eased
	st["fails"] = fails
	if not st.has("start_hour"):
		st["start_hour"] = st.get("time_of_day", 14.0)
	if not st.has("wear_mult"):
		st["wear_mult"] = 0.0
	if not st.has("fuel_mult"):
		st["fuel_mult"] = 0.0
	return st

## Configures RaceSettings for a campaign stage (arcade rules): the stage owns its track, laps, weather,
## opponents, difficulty (shifted by rival_step), start hour and grid; no pit stops, no tyre wear, no fuel
## use, and no circuit safety car or red flags (local yellows, stewards' penalties and damage stay).
## Call after Quick Race defaults and before DifficultyProfile.apply_sim so the player's damage mode and
## auto-recover still apply.
static func configure_stage(st: RaceSettings, stage: Dictionary, rival_step := DifficultyProfile.AVERAGE) -> void:
	st.mode = "race"
	st.track = String(stage.track)
	st.laps = int(stage.laps)
	st.format = "laps"
	st.weather = String(stage.weather)
	st.opponents = int(stage.opponents)
	st.field_classes = field_classes(stage)
	var rivals := resolve_level(String(stage.difficulty), float(stage.get("level_shift", 0.0)), rival_step)
	st.difficulty = String(rivals.difficulty)
	st.difficulty_shift = float(rivals.shift)
	st.start_hour = float(stage.get("start_hour", stage.get("time_of_day", 14.0)))
	st.grid = String(stage.get("grid", "middle"))
	st.qualifying = false
	st.quali_grid = {}
	st.mandatory_stop = false
	st.two_compounds = false
	st.refuel = false
	st.pits_enabled = false
	st.auto_strategist = false
	st.dynamic_running = false
	st.collisions = true
	st.draft = true
	st.race_control = true
	st.safety_car = false
	st.mechanical_damage = false # DifficultyProfile.apply_sim may still turn it on if the player picked Full mechanical
	st.starting_tyre = "W" if st.weather in ["wet", "snow", "hail"] else "S"
	# Reuse DifficultyProfile's accessibility switches for fuel use off and tyre wear off.
	var arcade := DifficultyProfile.defaults()
	arcade.fuel = false
	arcade.wear = false
	DifficultyProfile.apply_sim(st, arcade)
	apply_format(st, stage) # an A->B sprint: grid behind A, finish at B, no laps

## The rivals' level: DifficultyProfile.resolve for the stage's level name, moved by `extra` levels (the stage's
## level_shift); with no extra it is resolve's own answer.
static func resolve_level(name: String, extra: float, step: int) -> Dictionary:
	if extra == 0.0:
		return DifficultyProfile.resolve(name, step)
	var lv := clampf(DifficultyProfile.level_of(name) + extra + DifficultyProfile.shift_of(step), DifficultyProfile.LEVEL_MIN, DifficultyProfile.LEVEL_MAX)
	var at := clampi(int(round(lv)), 0, LEVELS.size() - 1)
	return {"difficulty": LEVELS[at], "shift": lv - float(at), "level": lv}

## The level a stage's field is raced at, as a name for the briefing: "Medium", "Medium+" past the half-way to Hard.
static func level_name(stage: Dictionary) -> String:
	var name := String(stage.get("difficulty", "medium")).capitalize()
	return name + ("+" if float(stage.get("level_shift", 0.0)) >= 0.5 else "")

## The class a stage expects ("city" when it names none) and its display name.
static func stage_class(stage: Dictionary) -> String:
	var c := String(stage.get("class", ""))
	return c if CAR_CLASSES.has(c) else "city"

static func class_name_of(cls: String) -> String:
	return String(CAR_CLASSES.get(cls, CAR_CLASSES.city).name)

## The class a car belongs to (CAR_CLASSES), "city" for an unknown key.
static func class_of(car_key: String) -> String:
	for c in CLASS_ORDER:
		if car_key in CAR_CLASSES[c].cars:
			return c
	return "city"

## Where a car stands against the class a stage expects: -1 below it, 0 in it, 1 above.
static func class_cmp(car_key: String, stage: Dictionary) -> int:
	return signi(CLASS_ORDER.find(class_of(car_key)) - CLASS_ORDER.find(stage_class(stage)))

## The briefing's car line: the expected class and the cars in it, and how the field is made up.
static func class_line(stage: Dictionary) -> String:
	var cls := stage_class(stage)
	var names: Array = []
	for k in CAR_CLASSES[cls].cars:
		names.append(CarCatalog.display_name(k))
	var mix: Array = []
	var riv = stage.get("rivals", {})
	if riv is Dictionary:
		for k in riv:
			mix.append("%d× %s" % [int(riv[k]), CarCatalog.display_name(String(k))])
	return "Expected class: %s (%s) · Field: %s" % [class_name_of(cls), ", ".join(names), ", ".join(mix) if mix.size() else "as your car"]

## What the briefing says about the player's car against the class: "" when it fits.
static func class_advice(car_key: String, stage: Dictionary) -> String:
	match class_cmp(car_key, stage):
		-1:
			return "Your %s is below the %s class: the field will be quicker on the straights." % [CarCatalog.display_name(car_key), class_name_of(stage_class(stage))]
		1:
			return "Your %s is above the %s class." % [CarCatalog.display_name(car_key), class_name_of(stage_class(stage))]
	return ""

## The car each opponent drives (RaceSettings.field_classes, by opponent index): the stage's "rivals" dealt
## through the roster, the rarer cars spread evenly among the rest (so the quicker class is not bunched with
## the strongest drivers), padded with the expected class's first car. Empty for a stage with no "rivals".
static func field_classes(stage: Dictionary) -> PackedStringArray:
	var n := int(stage.get("opponents", 0))
	var out := PackedStringArray()
	var riv = stage.get("rivals", {})
	if not riv is Dictionary or (riv as Dictionary).is_empty() or n <= 0:
		return out
	var fill: String = CAR_CLASSES[stage_class(stage)].cars[0]
	out.resize(n)
	for i in n:
		out[i] = ""
	var keys: Array = (riv as Dictionary).keys().filter(func(k: Variant) -> bool: return CarCatalog.is_key(String(k)))
	# rarest first (ties in the order the stage lists them), each into evenly spaced free slots
	var order := keys.duplicate()
	order.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(riv[a]) < int(riv[b]) or (int(riv[a]) == int(riv[b]) and keys.find(a) < keys.find(b)))
	for k in order:
		var count := mini(int(riv[k]), n)
		var free: Array[int] = []
		for i in n:
			if out[i] == "":
				free.append(i)
		for j in mini(count, free.size()):
			out[free[int(floor((j + 0.5) * free.size() / float(count)))]] = String(k)
	for i in n:
		if out[i] == "":
			out[i] = fill
	return out

## The gap (s) the player won by: P2's total minus P1's, from Race.results() rows; 0 when the player did not win,
## RUNAWAY_WIN when nobody else was classified on the same lap (lapped or still out on the projection).
static func win_margin(rows: Array) -> float:
	if rows.is_empty() or not (rows[0].car as RaceCar).is_player:
		return 0.0
	if rows.size() < 2:
		return 0.0
	var a = rows[0].get("total")
	var b = rows[1].get("total")
	if int(rows[1].get("laps", 0)) < int(rows[0].get("laps", 0)) or (a != null and b == null):
		return RUNAWAY_WIN
	if a == null or b == null:
		return 0.0
	return maxf(0.0, float(b) - float(a))

## The campaign's heat after a stage result: a big win (P1 by BIG_WIN s or more) adds HEAT_STEP, twice that for
## the second big win in a row and again twice for a runaway; another clear keeps it and ends the streak; a failed
## try takes HEAT_FAIL off. Returns [heat, streak].
static func next_heat(heat: float, streak: int, success: bool, pos: int, margin: float) -> Array:
	if not success:
		return [maxf(0.0, heat - HEAT_FAIL), 0]
	if pos == 1 and margin >= BIG_WIN:
		var s := streak + 1
		var add := HEAT_STEP * float(mini(s, 2)) * (2.0 if margin >= RUNAWAY_WIN else 1.0)
		return [minf(HEAT_MAX, heat + add), s]
	return [heat, 0]

## fans: the player's fan total (read from the open-world save when not given). A "fan_lock" stage (the Goliath)
## opens at the top fan level instead of after the stage before it.
static func is_unlocked(stage_idx: int, fans := -1) -> bool:
	if Missions.is_mission(stage_idx):
		return Missions.is_unlocked(stage_idx)
	if stage_idx >= 0 and stage_idx < STAGES.size() and STAGES[stage_idx].get("fan_lock", false):
		return FanLevels.hypercar_unlocked(fans if fans >= 0 else WorldProgress.load_progress().fans)
	var prog := load_progress()
	return stage_idx <= int(prog.get("unlocked", 0))

## margin: s the player won by (win_margin), for the adaptive field; 0 (a place only) never tightens it.
static func record_result(stage_idx: int, pos: int, margin := 0.0) -> Dictionary:
	if Missions.is_mission(stage_idx): # a place-only result (the map judges missions with MapMissions.outcome)
		var st := get_stage(stage_idx)
		return Missions.record(stage_idx, {"pos": pos, "success": pos <= int(st.target_pos), "tier": 0, "score": 0})
	var stage := get_stage(stage_idx)
	var prog := load_progress()
	var unlocked: int = int(prog.get("unlocked", 0))
	var best_pos: Dictionary = prog.get("best_pos", {})
	var trophies: Array = prog.get("trophies", [])
	
	var sid := str(stage_idx)
	var prev_best: int = int(best_pos.get(sid, 999))
	if pos < prev_best:
		best_pos[sid] = pos
		
	var target_pos: int = stage.target_pos
	var success: bool = pos <= target_pos
	var newly_unlocked := false
	
	var first_clear := false
	if success:
		var t_name: String = stage.trophy
		if t_name not in trophies:
			trophies.append(t_name)
			first_clear = true
		if stage_idx == unlocked and unlocked < STAGES.size() - 1 and not STAGES[unlocked + 1].get("fan_lock", false):
			unlocked += 1
			newly_unlocked = true
			
	var fails: Dictionary = prog.get("fails", {})
	if success:
		fails.erase(sid)
	else:
		fails[sid] = int(fails.get(sid, 0)) + 1
	prog["fails"] = fails
	var heat_before := float(prog.get("heat", 0.0))
	var hs := next_heat(heat_before, int(prog.get("streak", 0)), success, pos, margin)
	prog["heat"] = hs[0]
	prog["streak"] = hs[1]
	prog["unlocked"] = unlocked
	prog["best_pos"] = best_pos
	prog["trophies"] = trophies
	save_progress(prog)
	
	return {
		"success": success,
		"newly_unlocked": newly_unlocked,
		"unlocked_stage": unlocked,
		"trophy": stage.trophy if success else "",
		"first_clear": first_clear,
		"fans": FanLevels.stage_reward(stage_idx, pos, target_pos, first_clear),
		"margin": margin,
		"heat": float(hs[0]),
		"tightened": float(hs[0]) > heat_before,
		"streak": int(hs[1]),
	}

## The car carried from one stage to the next ({parts, pull, used, serviced}, see Service): what the crew
## doesn't repair in the service area between stages is still broken at the next one.
static func load_car() -> Dictionary:
	var car = load_progress().get("car", {})
	return car if car is Dictionary else {}

static func save_car(car: Dictionary) -> void:
	var prog := load_progress()
	prog["car"] = car
	save_progress(prog)
