## The campaign's story: the cast, and every beat they speak, keyed by what triggers it. A beat is a list of
## [speaker, text] lines ("" speaks as the narrator). Keys:
##   intro, festival (first visit to the Fest at the KS Górnik stadium), act_2, act_3, epilogue
##   <event id>_brief (one line on the beacon's briefing card), <id>_before (when the event is entered),
##   <id>_won / <id>_miss (after its result), where <id> is a Campaign stage id (stage_1..) or a Missions id
##   car_<key> (a car won), open_<id> (a one-line phone message on the HUD banner when a stage or mission opens)
## What was seen is saved in campaign.json under "story": {"seen": [keys in the order they were shown]}; RESET
## CAMPAIGN rewrites the file, which clears it. A save from before the story has no "story" key: it loads as
## nothing seen, and a save with progress in it is caught up silently (Story.needs_catch_up) instead of replaying.
class_name Story
extends RefCounted

const CHARACTERS := {
	"mirek": {"name": "Wujek Mirek", "role": "Your uncle, mechanic", "color": "#ff8a1e", "initial": "M"},
	"ola": {"name": "Ola Mazur", "role": "Best friend, co-driver", "color": "#3fd6e6", "initial": "O"},
	"kamil": {"name": "Kamil Wrona", "role": "Rival from Pszczyna", "color": "#ff4f5e", "initial": "K"},
	"zbyszek": {"name": "Pan Zbyszek", "role": "Seicento Fest organiser", "color": "#ffd34a", "initial": "Z"},
	"halina": {"name": "Halina Rak", "role": "Test driver, Tychy", "color": "#b98cff", "initial": "H"},
	"basia": {"name": "Ciocia Basia", "role": "The car's first owner", "color": "#9fe06a", "initial": "B"},
}
const NARRATOR_COLOR := "#d9cce9"
const MAX_LINES := 6 ## lines in one beat (the epilogue is the longest)
const MAX_CHARS := 170 ## characters in one line (StoryCard fits three lines of this at 4:3)
const BRIEF_CHARS := 110 ## a briefing card's quote is kept short: the card trims its description from the end

const BEATS := {
	"intro": [
		["", "Brzeszcze, summer 2004. The shift siren at KWK Brzeszcze, coal dust on the windowsills, cut grass on the verges."],
		["mirek", "Ciocia Basia's Seicento. 1998, 900 cc, 39 horses, and every one of them is tired. The keys are yours, młody."],
		["mirek", "I changed the oil, the plugs and the left front bearing. The tape deck you can fix yourself."],
		["ola", "Pan Zbyszek has put posters all over the Rynek: a Seicento series, starting in Wilamowice. I've signed us up. You're welcome."],
		["mirek", "Drive to the beacons. Bring the car back in one piece. In that order."],
	],
	"festival": [
		["zbyszek", "WELCOME TO SEICENTO FEST! The KS Górnik stadium, a sausage stand and the finest small cars in Małopolska!"],
		["zbyszek", "Win my series and one night I'll close the whole town for a single lap. Twenty-seven kilometres. I call it the Goliath."],
		["ola", "He's been saying that since 1999. The council laughs at him."],
		["zbyszek", "Let them laugh. Bring me fans, young driver, thousands of them. Then we'll see who's laughing."],
	],
	"act_2": [
		["", "ACT II · REGIONAL CHAMPIONSHIP. September 2004."],
		["ola", "We're out of the county now: Bielsko, Oświęcim, Kraków. Real crowds, real money, real crashes."],
		["mirek", "And real rivals. Kamil's father has bought him a mechanic. A proper one, with overalls that match."],
		["mirek", "Matching overalls never won a race. Go on."],
	],
	"act_3": [
		["", "ACT III · GLOBAL LEGENDS. Late autumn 2004."],
		["halina", "The factory track first. Then Monza, the Nürburgring and Le Mans, and a charter to Tokyo that Pan Zbyszek swears is real. I checked. It is real."],
		["mirek", "Tokyo. I've never been further than Zakopane. Pack the spare plugs."],
	],
	"epilogue": [
		["", "EPILOGUE · Spring 2005."],
		["mirek", "The crown is on the shelf next to my old pit helmet. Kamil comes round on Saturdays now. He sweeps. He's good at sweeping."],
		["kamil", "Mirek says I drive angry. I'm learning to drive like it's Tuesday."],
		["ola", "Zbyszek wants a bigger series next year: all of Silesia, maybe the Tatras. I've already bought a thicker notebook."],
		["basia", "Lovely, all of it. But I need my Seicento back for the market on Saturdays."],
		["mirek", "And there's a barn in Jawiszowice with something under a tarp. Come round on Monday, młody."],
	],
	"car_golf4": [
		["mirek", "VW Golf IV, 1.4 16V. Seventy-five horses, nearly double. Heavier and softer: it'll push on like a bus if you rush it."],
		["ola", "It's under CAR on the pause menu. Or stay loyal to the Seicento. Ciocia Basia would want you to be loyal."],
	],
	"car_logan": [
		["ola", "A Dacia Logan. It's beige. It's enormous. It has a boot you could live in."],
		["mirek", "Simple, strong, easy to fix. My kind of car. I might borrow it for fishing."],
	],
	"car_v50": [
		["halina", "Volvo V50, the 2.4 five-cylinder. A hundred and seventy horses: our chase car, because nothing else kept up."],
		["mirek", "Five cylinders. Listen to it. Heavy, though: brake before you think you need to."],
	],
	"car_i20": [
		["zbyszek", "A Hyundai i20 1.4, fresh off the Bielsko forecourt! A hundred horses, five doors, and air conditioning that actually blows cold!"],
		["mirek", "Light, tidy and revvy. Keeps its feet on the tarmac better than Basia's car, too."],
	],
	"car_sandero": [
		["ola", "A Dacia Sandero 1.6! Like the Logan, only without the spare bedroom stuck on the back."],
		["mirek", "Sturdy, simple, eighty-seven horses. Doesn't care about potholes or kerbs. Good honest Silesian transport."],
	],
	"car_focus": [
		["halina", "2015 Ford Focus 1.5 EcoBoost. A hundred and fifty horses, six gears, and a chassis that actually talks to you."],
		["mirek", "Turbocharged, grips like a leech, stops on a coin. Just mind the speed limit past the school."],
	],
	"car_zafira": [
		["zbyszek", "An Opel Zafira B! Seven seats! You can fit the whole pit crew, the spare tyres, and half a bakery in the back!"],
		["mirek", "A hundred and forty horses in a family bus. Tall in the corners, mind — don't tip it on its ear."],
	],

	# ---------------------------------------------------------------- Act I
	"stage_1_brief": [["mirek", "Top three in Wilamowice and Zbyszek lets you into the series. Don't bend my car."]],
	"stage_1_before": [
		["ola", "Wilamowice: the Rynek, Kęcka, out to Hecznarowice and back through the fields. I've read the map three times."],
		["kamil", "Nice car. Did your grandma leave the shopping in the back? Kamil Wrona, Pszczyna. You'll be reading that name on my bumper."],
		["mirek", "Ignore him. Brake early for the lefts. Momentum is the only horsepower you've got."],
	],
	"stage_1_won": [
		["zbyszek", "A PODIUM FOR BRZESZCZE! Ladies and gentlemen, the shopping car has teeth!"],
		["kamil", "Beginner's luck. The fields were dry."],
		["mirek", "Hm. Not bad. The bearing held, too."],
	],
	"stage_1_miss": [
		["mirek", "Stock car, stock driver. Both get better with miles. Go again."],
		["ola", "Kamil waved at us from the podium. With both hands. Let's ruin his week."],
	],
	"stage_2_brief": [["mirek", "Home roads in the morning fog. I'll be coming off the night shift: listen for the siren."]],
	"stage_2_before": [
		["mirek", "Fog off the ponds by the Andrzej shaft. You know these corners from the bus window. Now learn them for real."],
		["ola", "My mum's watching from the bakery on Kościuszki. No pressure. Well, some pressure."],
	],
	"stage_2_won": [
		["mirek", "The whole shift was at the fence in their helmets. Thirty grown miners cheering a Seicento. I'll never live it down."],
		["ola", "The bakery sent rolls. Free rolls for life, Mum says. Or until you lose."],
	],
	"stage_2_miss": [
		["mirek", "You braked when you saw the corner. Brake when you know it's there. Fog only hides what you haven't learned."],
		["ola", "Next time I'll stand at every junction with a torch."],
	],
	"stage_3_brief": [["ola", "Bór: pines, guardrail, two level crossings. I'll count the trains for you."]],
	"stage_3_before": [
		["mirek", "I grew up on ul. Bór. My dad drove the bus through these woods; I wanted his job more than anything."],
		["mirek", "That guardrail was there before you were born and it'll be there after. Be smooth."],
		["kamil", "Forest roads. Great. If I scratch this paint my father sells me to the circus."],
	],
	"stage_3_won": [
		["mirek", "Clean. Not one mark on the doors. I checked twice."],
		["kamil", "Okay. Okay. You can drive a bit. Don't tell anyone I said so."],
	],
	"stage_3_miss": [
		["mirek", "The trees don't care how fast you were for the first three laps."],
		["ola", "Mirek pulled the dent out with a sink plunger. It's fine. It's mostly fine."],
	],
	"stage_4_brief": [["kamil", "My town, my park, my setts. Come and lose politely."]],
	"stage_4_before": [
		["kamil", "Pszczyna at sunset: the castle, the wisents, the park alleys. I've ridden my bike over these bridges since I was six."],
		["ola", "The bridges between the ponds are one car wide. One. I measured with my scarf."],
		["mirek", "He knows the place. You know how to keep a car alive when it slides. That's worth more."],
	],
	"stage_4_won": [
		["kamil", "In front of my father. In front of the wisents. You realise the wisents will remember this."],
		["zbyszek", "And that ends the county season! The regional championship awaits the kid from Brzeszcze!"],
		["mirek", "Car's not coming home on a hook? Then it was a good day."],
	],
	"stage_4_miss": [
		["kamil", "Told you. Setts. You have to grow up on them."],
		["mirek", "He takes the hairpin under the castle a car's length later than you, every lap. Watch him, then go one further."],
	],

	# ---------------------------------------------------------------- Act II
	"stage_5_brief": [["mirek", "Bielsko built your car. Take it home and show it Armii Krajowej."]],
	"stage_5_before": [
		["mirek", "Your Seicento came off the line in this town. Bring it home and show it what it can do."],
		["ola", "Up Armii Krajowej to the cable car, then seventy metres down Karbowa. I've marked the brakes in red. Everything is red."],
		["kamil", "New mechanic, new springs, matching overalls. Try to keep up, Brzeszcze."],
	],
	"stage_5_won": [
		["halina", "Halina Rak, test driver at the Tychy factory. I timed your descent from Rondo Fieldorfa. Nobody brakes that late in a 900."],
		["halina", "Nobody sensible, anyway. Keep winning and I'll be in touch."],
		["mirek", "She rallied in the eighties, they say. Be polite. Be very polite."],
	],
	"stage_5_miss": [
		["mirek", "Too much brake on Karbowa, too little time in the draft. Stay in the tow until it hurts."],
		["kamil", "Not bad for a shopping car. That's not a compliment. Mostly."],
	],
	"stage_rewanz_brief": [["kamil", "Pszczyna again. At night, in the rain. My park, my rules, my rematch."]],
	"stage_rewanz_before": [
		["kamil", "You beat me here in the sunshine. Let's see you find the bridges in the dark with water on the setts."],
		["ola", "The park lamps go off at ten. The castle's lit, though. Aim for the castle. Then don't hit it."],
		["mirek", "New headlight bulbs, both sides. Wet setts at night: look further ahead than you think you can."],
	],
	"stage_rewanz_won": [
		["kamil", "Twice. In my town. My father has gone home to tell the wisents himself."],
		["ola", "Kamil just shook your hand. Properly, with eye contact. I've written down the time."],
		["mirek", "Rain, dark, a bridge one car wide, and the car's still straight. Now I'm impressed."],
	],
	"stage_rewanz_miss": [
		["kamil", "See? The park knows its own. Come back when you can drive by moonlight."],
		["mirek", "You braked for the bridges by the lamps. There are no lamps. Count the trees instead."],
	],
	"stage_6_brief": [["ola", "Rain on the Soła and setts on Plebańska. My grandad's town. Drive nicely."]],
	"stage_6_before": [
		["ola", "Grandad Tadek used to fish under Most Piastowski. He says the river's in a mood today."],
		["mirek", "Wet setts round the Rynek are wet soap. Straight lines, gentle hands."],
		["kamil", "Rain is the great equaliser. Lucky for you."],
	],
	"stage_6_won": [
		["ola", "Grandad watched from the bridge under his fishing umbrella. He says you drive like the river: no hurry, never stops."],
		["kamil", "I spun at Rondo Płonki in front of four hundred people and a swan. Go on, laugh."],
		["mirek", "Don't laugh. Help him push. That's how it's done round here."],
	],
	"stage_6_miss": [
		["ola", "The Rynek ate us. Grandad says even the river takes two goes at that corner."],
		["mirek", "Dry the car out, dry yourself out, and come back."],
	],
	"stage_7_brief": [["zbyszek", "Kraków! The royal city! I've sold the TV rights to a man with a camera!"]],
	"stage_7_before": [
		["ola", "Basztowa, the Barbakan, then setts and tram rails under Wawel. Eleven of them out there, and they're all good."],
		["kamil", "My mechanic quit. Said I drive angry. Whatever. I'll be in front of you on Straszewskiego."],
		["mirek", "He's driving angry. You drive like it's a Tuesday. Tuesday always wins."],
	],
	"stage_7_won": [
		["zbyszek", "THE CROWN OF THE REGION goes to Brzeszcze! The man with the camera cried. I cried."],
		["kamil", "Fine. You're good. I mean it. Don't make it weird."],
		["halina", "Tor Fiata in Tychy, Monday at nine. Bring the car. The engineers want to look at your gearbox, and at you."],
	],
	"stage_7_miss": [
		["kamil", "Ha. Not tonight, Brzeszcze."],
		["mirek", "Tram rails, setts and eleven cars. Third is a lot to ask. Ask again."],
	],

	# ---------------------------------------------------------------- Act III and the finale
	"stage_8_brief": [["halina", "My track, my test drivers. Don't lift on the kilometre straight."]],
	"stage_8_before": [
		["halina", "Our test drivers do three hundred laps a week here. They don't race, they measure. Show them racing."],
		["mirek", "I always wanted to work somewhere with clean floors. Now my nephew races on the factory's test track."],
	],
	"stage_8_won": [
		["halina", "The engineers asked who tunes your car. I said a miner from Brzeszcze with a sink plunger. They wrote it down."],
		["halina", "Next is Monza. The factory's people in Turin want to see the Polish Seicento in their park. Then the Ring, Le Mans, and Tokyo if Zbyszek has his way."],
	],
	"stage_8_miss": [
		["halina", "Quick on the straight, slow through the West Turn. The car is not the problem. Again."],
	],
	"stage_monza_brief": [["halina", "Fiat's home crowd: the royal park, the Parabolica, and the men from Turin watching."]],
	"stage_monza_before": [
		["halina", "Turin heard about a Polish Seicento that beats its test drivers. They want it at Monza, among the Italians."],
		["ola", "Rettifilo, Curva Grande, the Lesmos, Ascari, Parabolica. I practised saying them on the plane. Ola, the Italian."],
		["kamil", "Cheap flight via Bergamo. Somebody has to keep you honest. And the pizza's good."],
	],
	"stage_monza_won": [
		["halina", "A Polish Seicento on the Monza podium, in front of Turin. The man from Turin asked for your number. I gave him Mirek's."],
		["mirek", "He rang. He speaks no Polish and I speak no Italian. We talked gearboxes for an hour."],
	],
	"stage_monza_miss": [
		["halina", "Too early on the brakes into the Parabolica. It's a long corner: be patient and the exit pays you back."],
		["ola", "The Italians waved at us as they went by. Nicely. That was the worst part."],
	],
	"stage_eifel_brief": [["ola", "Twenty kilometres, seventy-odd corners, one lap, fog in the forest. I've brought two notebooks."]],
	"stage_eifel_before": [
		["ola", "The Nordschleife: Flugplatz, Fuchsröhre, Adenauer Forst, the Karussell, Brünnchen, Pflanzgarten. One lap, no second go."],
		["mirek", "Fog in the hills at half eight. Like the Andrzej shaft in October, only the hills are bigger."],
		["halina", "I tested here in eighty-seven. The Karussell is concrete and it bites: drop into the banking and stay in it."],
	],
	"stage_eifel_won": [
		["halina", "A podium on the Nordschleife, in fog, at the first try. My old team manager would have hired you on the spot."],
		["ola", "My notebook got soaked in the Fuchsröhre. I read the last six kilometres from memory. Don't tell anyone."],
	],
	"stage_eifel_miss": [
		["mirek", "Twenty kilometres is a long way to keep your head. It's never the fast corners. It's the one you forget."],
		["ola", "We'll go again. I'll write bigger."],
	],
	"stage_lemans_brief": [["zbyszek", "LE MANS! At NIGHT! I've hired a coach, a flag and a man who can say Hunaudières!"]],
	"stage_lemans_before": [
		["zbyszek", "The Circuit de la Sarthe after dark! I promised the coach driver we'd be home by Tuesday!"],
		["ola", "Dunlop bridge, Tertre Rouge, then the Mulsanne with its two chicanes, flat out in the dark. Then Arnage and the Porsche Curves."],
		["mirek", "The longest you'll ever hold it flat. Watch the temperature, and brake when the board says, not when you feel it."],
	],
	"stage_lemans_won": [
		["zbyszek", "BRZESZCZE AT LE MANS! The coach driver cried! He says he'll drive us to Tokyo next! He is NOT driving us to Tokyo!"],
		["kamil", "I watched from the Dunlop bridge with a baguette. You passed three of them on the Mulsanne. I've lost my voice."],
	],
	"stage_lemans_miss": [
		["ola", "The Porsche Curves at night are a different track. We'll learn them."],
		["mirek", "You lost it in the dark, not on the straight. Pick out the braking boards early."],
	],
	"stage_9_brief": [["zbyszek", "TOKYO! Forty fans on the plane and a flag the size of a bedsheet!"]],
	"stage_9_before": [
		["ola", "The C1 at midnight: concrete walls, tunnels, the spiral at Hamarikyu. I can't read the signs, but I can read the notes."],
		["mirek", "Twelve hours on a plane with Zbyszek's flag. Survive that and one lap is nothing."],
		["kamil", "I came. Paid my own ticket. Somebody from Silesia has to finish second."],
	],
	"stage_9_won": [
		["zbyszek", "THE SEICENTO IS EMPEROR OF THE MIDNIGHT! I am phoning the mayor! I am phoning him NOW!"],
		["kamil", "Pole to flag on the Shuto at midnight. I'm proud I lost to that. Weird feeling."],
		["mirek", "Come home. The town's waiting, and Zbyszek has something mad to tell you."],
	],
	"stage_9_miss": [
		["ola", "The spiral bit us. We're still here and so is the car. Again."],
		["kamil", "Don't look at me like that. I'm not gloating. I'm just glad it wasn't me."],
	],
	"stage_10_brief": [["zbyszek", "One lap. All of Brzeszcze, closed for a night. I told the council. I TOLD them."]],
	"stage_10_before": [
		["zbyszek", "Ladies and gentlemen: the Goliath! The town, the S1, Bór and the ponds. Twelve hypercar Seicentos, one hometown kid on pole!"],
		["mirek", "These things are madness. Three hundred and forty on the S1. Basia's little Seicento is in the paddock, watching."],
		["kamil", "I'm on the grid behind you. Fast on the S1 and I'll give you a tow. Slow and I'll take yours. Fair?"],
		["ola", "Last notes, partner. Flat, flat, flat, brake like the world's ending, then home."],
	],
	"stage_10_won": [
		["", "Past midnight the siren at the Andrzej shaft goes off, out of turn. Somebody up the headframe has a hand on the switch."],
		["zbyszek", "THE GOLIATH CROWN! For the kid from the bakery street! Brzeszcze, MAKE SOME NOISE!"],
		["kamil", "Your tow was rubbish. You won anyway. I'm buying."],
		["mirek", "Your grandad would have stood at the pit gate in his helmet tonight. I stood there for him."],
	],
	"stage_10_miss": [
		["zbyszek", "The Goliath is still standing! But the town stays closed until dawn, so: AGAIN!"],
		["mirek", "Twenty-seven kilometres is a long way to be perfect. Have a tea. Then go and be perfect."],
	],

	# ---------------------------------------------------------------- missions
	"drag_quarter_brief": [["ola", "The night shift drags on the S1 once the lorries have gone. Mirek doesn't know. Yet."]],
	"drag_quarter_before": [
		["ola", "A quarter mile north from the Wola lights to the gantry. Four Seicentos. Nobody official. Very exciting."],
		["kamil", "Fancy seeing you here. A quarter mile, Brzeszcze. Can grandma's car count that far?"],
	],
	"drag_quarter_won": [
		["ola", "Kamil says his clutch slipped. Kamil's clutch slips a lot. And the night shift tossed you the keys to their Sandero!"],
		["mirek", "I know where you were last night. ...So what did you run?"],
	],
	"drag_quarter_miss": [
		["kamil", "See you at the gantry! Oh wait, I was already there."],
		["ola", "We lost it at the lights. Change up a bit sooner and don't look at him."],
	],
	"sprint_s1_brief": [["zbyszek", "The S1, closed for a whole morning! The first Seicento Fest expressway sprint!"]],
	"sprint_s1_before": [
		["zbyszek", "I promised the road people a crate of krówki and a speech. Do not crash on the dumbbell bridge."],
		["ola", "Up one carriageway, round, back down the other. The slipstream is free speed: steal it."],
	],
	"sprint_s1_won": [
		["zbyszek", "A FLYING SEICENTO! The Bielsko dealer loved it so much they handed over the keys to their Hyundai i20!"],
		["mirek", "Flat out for nine kilometres and the temperature needle never moved. Good car. Good driver."],
	],
	"sprint_s1_miss": [
		["ola", "The turn-rounds are the race. Everything else is waiting in a queue."],
		["mirek", "Tuck in behind someone and stay there. Let them do the work."],
	],
	"drift_babudy_brief": [["ola", "The lads from Góra want it sideways. Mirek wants it straight. Choose."]],
	"drift_babudy_before": [
		["ola", "Babudy to Góra, gravel and tarmac. The judges are three lads on a bench with a notepad. Strict lads."],
		["mirek", "Put my car in a fence at Babudy and you walk home. It's a long walk."],
	],
	"drift_babudy_won": [
		["ola", "The bench gave you a standing ovation — and the keys to their Opel Zafira! Well, two of them stood. One was asleep."],
		["mirek", "...I saw it. It was beautiful. Don't do it again."],
	],
	"drift_babudy_miss": [
		["ola", "Too straight, says the bench. Too tidy. They want chaos, but neat chaos."],
		["mirek", "Handbrake, then throttle. Not the other way round."],
	],
	"offroad_kolonia_brief": [["mirek", "Fishpond dykes, mud to the axles. Ciocia Basia must never hear about this."]],
	"offroad_kolonia_before": [
		["ola", "Kolonia Stawowa: dykes, forest tracks and the Bronisław bridge. Six cars on a road one car wide."],
		["kamil", "Mud. In my car. I bought seat covers for this. Plastic ones."],
	],
	"offroad_kolonia_won": [
		["mirek", "I'll be washing gravel out of the sills till Christmas. Worth it — and a Ford Focus in the yard for the trouble."],
		["kamil", "My seat covers worked. Nothing else did."],
	],
	"offroad_kolonia_miss": [
		["ola", "We spent two minutes admiring a heron from the ditch."],
		["mirek", "On gravel you brake first and early. Loose roads don't forgive."],
	],
	"knockout_bor_brief": [["kamil", "Mały Bór knockout, my Golf against your Seicento. Unless you're scared."]],
	"knockout_bor_before": [
		["kamil", "My father's old Golf IV. Make the final two and it's yours. Drop out and that Seicento sleeps in my garage."],
		["mirek", "Don't take bets from a Wrona. ...But if you have, don't be last at the sector lines."],
		["ola", "Five sectors, one car out at each. Don't win it. Survive it."],
	],
	"knockout_bor_won": [
		["kamil", "Keys. Take them before I change my mind. It pulls left and the radio only finds polka."],
		["mirek", "A Golf. In my garage. Next to Basia's Seicento. The world's gone mad."],
	],
	"knockout_bor_miss": [
		["kamil", "Your Seicento's safe. I'm generous. Next time I keep it."],
		["ola", "Last at sector three by half a bumper. Half a bumper!"],
	],
	"rally_bor_brief": [["ola", "Rajd Borów. My notebook, your right foot. This one's ours."]],
	"rally_bor_before": [
		["ola", "Special stages round Brzeszcze: Mały Bór, Kolonia Stawowa, Babudy–Góra. On the liaisons we drive like normal people."],
		["ola", "I read the notes, you listen. If I say 'don't cut', don't cut. If I scream, that's a new note."],
		["mirek", "Service is my garage. Bring me back something to fix, not something to bury."],
	],
	"rally_bor_won": [
		["zbyszek", "A RAJD BORÓW PODIUM for the bakery street crew! And the prize: a brand-new Dacia Logan, kindly donated by my cousin!"],
		["ola", "We're a rally crew. Officially. I'm having the notebook framed."],
	],
	"rally_bor_miss": [
		["ola", "We lost it on the stages, not the liaisons. Nine tenths. I'll scream less."],
		["mirek", "Rallies are long and crashes are short. Remember which one you want."],
	],
	"drag_kilometre_brief": [["halina", "My test drivers heard about your quarter mile. They'd like a kilometre."]],
	"drag_kilometre_before": [
		["halina", "Three of my test drivers, a standing kilometre on the S1 at night. Very polite people. They'll still try to beat you."],
		["ola", "Get away first, stay in the middle of the lane, give them no tow. Easy. Ha."],
	],
	"drag_kilometre_won": [
		["halina", "They've asked for a rematch. On paper. With graphs. And a deal is a deal: the chase car's yours. Mind the tailgate."],
		["mirek", "You beat the factory. In Basia's car. Hm."],
	],
	"drag_kilometre_miss": [
		["halina", "Good start, soft middle. Keep it straight and let them chase you."],
		["ola", "We'll get them. They write everything down; we just drive."],
	],
	"sprint_rajsko_brief": [["ola", "The Rajsko farm lads race the lanes to Wilczkowice on Saturdays. The harvest's in, so: tonight."]],
	"sprint_rajsko_before": [
		["ola", "Oświęcimska, Wilamowicka, Pszczyńska and back down Przemysłowa. Seven kilometres of lanes, ditches both sides."],
		["mirek", "Tractors use these roads all day. Mind the mud on the corners, and the dog at number twelve."],
	],
	"sprint_rajsko_won": [
		["ola", "The village gave you the harvest sheaf! It's mostly straw and a ribbon, but it's ours."],
		["mirek", "The dog at number twelve chased you all the way to the line. You still beat it. Good."],
	],
	"sprint_rajsko_miss": [
		["ola", "We spent the last kilometre behind a lad in a Polonez with no exhaust. Quicker next time. And deafer."],
		["mirek", "Square junctions, narrow lanes: brake before the crossroads, not in them."],
	],
	"drift_kopalnia_brief": [["mirek", "The night shift wants the town sideways. I'm on that shift. I've seen nothing."]],
	"drift_kopalnia_before": [
		["mirek", "Midnight, the canteen steps, a thermos and twelve miners with score cards. Harder judges than the Góra lads."],
		["ola", "Ofiar Oświęcimia, Przemysłowa, Leśna, the right angles round the shafts. Sideways into every one. Mirek, look away."],
	],
	"drift_kopalnia_won": [
		["mirek", "Twelve cards went up and every one said ten. Well, one said 'Basia must never know'. Same thing."],
		["ola", "The canteen lady gave you a bowl of żurek. That's the highest honour Brzeszcze has."],
	],
	"drift_kopalnia_miss": [
		["mirek", "The lads say you went round the corners. Round. Like a bus. They want sideways."],
		["ola", "Handbrake at the turn-in, throttle to hold it, and don't straighten up between corners or the combo's gone."],
	],
	"knockout_rajsko_brief": [["kamil", "Rajsko knockout. Eight cars, seven lines. I learnt a lot in the forest. Did you?"]],
	"knockout_rajsko_before": [
		["kamil", "Same rules as Mały Bór, more cars, my new springs. And Halina's test drivers, who read the rules in advance."],
		["halina", "My drivers asked to race you again. I said yes. They've been pacing the ditches with a tape measure."],
		["ola", "Seven sector lines. Never be last at any of them. Win the last one if you can."],
	],
	"knockout_rajsko_won": [
		["kamil", "The final two again, you and me. And you again. I'm going to frame the gap. It's very small."],
		["halina", "My drivers have filed a report. It says 'faster than the model predicted'. They are very upset."],
	],
	"knockout_rajsko_miss": [
		["kamil", "Out before the final! Lucky for you I'm not taking bets today."],
		["ola", "Last at the line by a mirror. A mirror! Again."],
	],
	"rally_zima_brief": [["ola", "Snow on the Rynek and a rally on the roads round town. Home stages, home crowd, frozen feet."]],
	"rally_zima_before": [
		["ola", "Kopalnia, Rajsko–Wilczkowice and Kolonia Stawowa, all in the snow. On the liaisons we drive like normal people, only slower."],
		["mirek", "Winter tyres, a shovel in the boot and a flask of tea for the co-driver. That's the whole service plan."],
		["zbyszek", "And the council is watching! Give them a show today and the Goliath gets its night. I can feel it!"],
	],
	"rally_zima_won": [
		["zbyszek", "A WINTER PODIUM! The council chairman stood in the snow for an hour! He's thawing out now. He's smiling!"],
		["ola", "Three stages in the snow and not one ditch. I'm having 'not one ditch' engraved on the trophy."],
	],
	"rally_zima_miss": [
		["ola", "The snow won that one. It usually does. We'll go again when we've warmed up."],
		["mirek", "In snow, slow is smooth and smooth is quick. Lift earlier and let the car come round."],
	],
}

## One-line phone messages, shown on the HUD banner when a stage or mission opens.
const RADIO := {
	"open_stage_2": ["mirek", "Next is home: the fog round the mine. The beacon's on ul. Dworcowa by KWK Brzeszcze."],
	"open_stage_3": ["ola", "Stage 3 is in Bór, down ul. Bór. Bring sandwiches, the forest is long."],
	"open_stage_4": ["kamil", "Pszczyna's next. My town. West on the DW933, try not to get lost."],
	"open_stage_5": ["mirek", "Regional round one: Bielsko. South on ul. Bielska. The car's going home to where it was born."],
	"open_stage_6": ["ola", "Oświęcim next: east on the DW933. Grandad says bring an umbrella."],
	"open_stage_7": ["zbyszek", "Kraków! The train leaves from Jawiszowice station! The beacon is at the station!"],
	"open_stage_8": ["halina", "Tor Fiata in Tychy: north on the S1. The gate opens at nine. Don't be late."],
	"open_stage_9": ["zbyszek", "TOKYO IS ON! The flight leaves from the Fest at the KS Górnik stadium! Bring a toothbrush!"],
	"open_stage_10": ["zbyszek", "The council said YES! The Goliath is on! Come to the Fest at the stadium!"],
	"open_drag_quarter": ["ola", "The night shift races on the S1 after the last lorry. Beacon's on the northbound side. Don't tell Mirek."],
	"open_sprint_s1": ["zbyszek", "The S1 sprint is open! Who closes an expressway for a Seicento? I DO!"],
	"open_drift_babudy": ["ola", "The Góra lads want sideways. The Babudy beacon is on the map. Bring the handbrake."],
	"open_offroad_kolonia": ["mirek", "Mud race on the fishpond dykes at Kolonia Stawowa. Wash the car after. Before Basia sees."],
	"open_knockout_bor": ["kamil", "Kamil here. Mały Bór, a knockout, my Golf against your Seicento. Unless you're scared."],
	"open_rally_bor": ["ola", "Rajd Borów entries are open and I've entered us already. Obviously."],
	"open_drag_kilometre": ["halina", "My test drivers want a standing kilometre on the S1 tonight. Bring your best gear change."],
	"open_stage_rewanz": ["kamil", "Kamil. Pszczyna, Saturday night, in the rain. One rematch, same beacon on the DW933. Unless you're scared."],
	"open_stage_monza": ["halina", "Monza, Fiat's home crowd. The flight leaves from Katowice: north on the S1 to the airport."],
	"open_stage_eifel": ["ola", "The Nürburgring next! Night train west from Jawiszowice station. I've packed sandwiches for three countries."],
	"open_stage_lemans": ["zbyszek", "LE MANS AT NIGHT! My coach leaves from the Fest at the stadium! Bring a jumper and your passport!"],
	"open_sprint_rajsko": ["ola", "The Rajsko lads race their lanes on Saturday night. The beacon's on ul. Oświęcimska. Don't tell Basia."],
	"open_drift_kopalnia": ["mirek", "The night shift wants a drift round the Kopalnia loop at midnight. Beacon's on Ofiar Oświęcimia. I saw nothing."],
	"open_knockout_rajsko": ["kamil", "Kamil here. A knockout on the Rajsko lanes, eight cars. Bring your elbows."],
	"open_rally_zima": ["ola", "Snow's come early and the Zimowy Rajd Brzeszcze is on. Entries are open, and I've entered us. Obviously."],
}

# ------------------------------------------------------------------ lookups

## The id a campaign index goes by in the beat keys: a stage's id (stage_1..) or a mission's id.
static func event_id(index: int) -> String:
	if Missions.is_mission(index):
		return String(Missions.get_def(index).id)
	if index >= 0 and index < Campaign.STAGES.size():
		return String(Campaign.STAGES[index].id)
	return ""

static func has_beat(key: String) -> bool:
	return BEATS.has(key) or RADIO.has(key)

static func is_radio(key: String) -> bool:
	return RADIO.has(key)

## A beat's lines, [[speaker, text], ...] (a phone message is one line).
static func lines(key: String) -> Array:
	if RADIO.has(key):
		return [RADIO[key]]
	return BEATS.get(key, [])

static func character(speaker: String) -> Dictionary:
	if CHARACTERS.has(speaker):
		return CHARACTERS[speaker]
	return {"name": "", "role": "", "color": NARRATOR_COLOR, "initial": "•"}

static func color_of(speaker: String) -> Color:
	return Color(String(character(speaker).color))

## The one line a beacon's briefing card quotes: [speaker, text], or [] when there is none.
static func brief_line(index: int) -> Array:
	var b: Array = BEATS.get(event_id(index) + "_brief", [])
	return b[0] if not b.is_empty() else []

## A briefing card's body with the event's story line above it.
static func brief_text(index: int, body: String) -> String:
	var b := brief_line(index)
	if b.is_empty():
		return body
	return "%s: “%s”\n\n%s" % [String(character(String(b[0])).name), String(b[1]), body]

## A short title for a beat in the journal.
static func beat_title(key: String) -> String:
	match key:
		"intro": return "PROLOGUE"
		"festival": return "SEICENTO FEST"
		"act_2": return "ACT II"
		"act_3": return "ACT III"
		"epilogue": return "EPILOGUE"
	if key.begins_with("car_"):
		return "NEW CAR: " + CarCatalog.display_name(key.substr(4)).to_upper()
	if key.begins_with("open_"):
		return "PHONE"
	for suffix: String in ["_before", "_won", "_miss", "_brief"]:
		if key.ends_with(suffix):
			var title := _event_title(key.trim_suffix(suffix))
			return "%s · %s" % [title, {"_before": "BEFORE", "_won": "AFTER", "_miss": "AFTER", "_brief": "BRIEFING"}[suffix]]
	return key.to_upper()

static func _event_title(id: String) -> String:
	for st: Dictionary in Campaign.STAGES:
		if String(st.id) == id:
			return String(st.title).to_upper()
	var k := Missions.index_of(id)
	return String(Missions.get_def(k).title).to_upper() if k >= 0 else id.to_upper()

# ------------------------------------------------------------------ seen state (campaign.json "story")

static func seen_keys(prog: Dictionary) -> Array:
	var st = prog.get("story", {})
	if not st is Dictionary:
		return []
	var s = (st as Dictionary).get("seen", [])
	return s if s is Array else []

static func is_seen(key: String, prog: Dictionary = {}) -> bool:
	if prog.is_empty():
		prog = Campaign.load_progress()
	return key in seen_keys(prog)

## Adds keys to the seen list (in order, once each) and saves.
static func mark_seen(keys: Array) -> void:
	var prog := Campaign.load_progress()
	var seen := seen_keys(prog).duplicate()
	for k in keys:
		if not String(k) in seen:
			seen.append(String(k))
	prog["story"] = {"seen": seen}
	Campaign.save_progress(prog)

## A save from before the story (no "story" key) that already has progress: its beats are marked seen silently
## (they stay in the journal) instead of replaying a season's worth of dialogue.
static func needs_catch_up(prog: Dictionary) -> bool:
	if prog.has("story"):
		return false
	var trophies: Array = prog.get("trophies", []) if prog.get("trophies", []) is Array else []
	var missions = prog.get("missions", {})
	return int(prog.get("unlocked", 0)) > 0 or not trophies.is_empty() or (missions is Dictionary and not (missions as Dictionary).is_empty())

# ------------------------------------------------------------------ triggers

static func _won(prog: Dictionary, i: int) -> bool:
	var trophies: Array = prog.get("trophies", []) if prog.get("trophies", []) is Array else []
	return String(Campaign.STAGES[i].trophy) in trophies

static func _stage_open(prog: Dictionary, i: int, fans: int) -> bool:
	if Campaign.STAGES[i].get("fan_lock", false):
		return FanLevels.hypercar_unlocked(fans)
	return i <= int(prog.get("unlocked", 0))

## The beats the save has earned and not yet shown, in the order they should play: the intro, the first visit to
## the Fest, results (stages, then missions), cars won, act changes, the epilogue, then the phone messages.
## points: the live-event medal points held (a mission's phone message waits for its medals); -1 reads the save.
static func pending(prog: Dictionary, fans: int, near_festival := false, points := -1) -> Array[String]:
	if prog.is_empty():
		prog = {"unlocked": 0} # never read from disk here (Missions' lookups do that for an empty one)
	if points < 0:
		points = Missions.live_points() if Missions.gated(prog) else 0
	var seen := seen_keys(prog)
	var out: Array[String] = []
	_add(out, seen, "intro")
	if near_festival:
		_add(out, seen, "festival")
	var fails = prog.get("fails", {})
	if not fails is Dictionary:
		fails = {}
	for i in Campaign.STAGES.size():
		var id := String(Campaign.STAGES[i].id)
		if _won(prog, i):
			_add(out, seen, id + "_won")
		elif int((fails as Dictionary).get(str(i), 0)) > 0:
			_add(out, seen, id + "_miss")
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		var id := String(Missions.MISSIONS[k].id)
		if Missions.is_cleared(idx, prog):
			_add(out, seen, id + "_won")
		elif int(Missions.progress(prog, idx).get("fails", 0)) > 0:
			_add(out, seen, id + "_miss")
	var cars = prog.get("cars", [])
	if cars is Array:
		for c in cars:
			_add(out, seen, "car_" + String(c))
	var unlocked := int(prog.get("unlocked", 0))
	if unlocked >= first_of_act(2):
		_add(out, seen, "act_2")
	if unlocked >= first_of_act(3):
		_add(out, seen, "act_3")
	if _won(prog, Campaign.STAGES.size() - 1):
		_add(out, seen, "epilogue")
	for i in range(1, Campaign.STAGES.size()):
		if _stage_open(prog, i, fans) and not _won(prog, i):
			_add(out, seen, "open_" + String(Campaign.STAGES[i].id))
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		if Missions.is_unlocked(idx, prog, points) and not Missions.is_cleared(idx, prog):
			_add(out, seen, "open_" + String(Missions.MISSIONS[k].id))
	return out

## The place in Campaign.STAGES of an act's first stage (its beat plays once the chain opens it).
static func first_of_act(act: int) -> int:
	for i in Campaign.STAGES.size():
		if int(Campaign.STAGES[i].act) >= act:
			return i
	return Campaign.STAGES.size()

static func _add(out: Array[String], seen: Array, key: String) -> void:
	if has_beat(key) and not key in seen and not key in out:
		out.append(key)

## The beat to play when an event is entered, "" when it has none or it was seen.
static func before_key(index: int, prog: Dictionary = {}) -> String:
	var key := event_id(index) + "_before"
	if not BEATS.has(key):
		return ""
	if prog.is_empty():
		prog = Campaign.load_progress()
	return "" if key in seen_keys(prog) else key

# ------------------------------------------------------------------ the journal

static func act_name(prog: Dictionary, _fans := 0) -> String:
	var last := Campaign.STAGES.size() - 1
	if _won(prog, last):
		return "Epilogue"
	if _won(prog, last - 1):
		return String(Campaign.STAGES[last].act_name)
	return String(Campaign.STAGES[clampi(int(prog.get("unlocked", 0)), 0, last - 1)].act_name)

## What the story asks next, one line. points: the live-event medal points held (-1 reads the save).
static func next_step(prog: Dictionary, fans: int, points := -1) -> String:
	if points < 0:
		points = Missions.live_points() if Missions.gated(prog) else 0
	var last := Campaign.STAGES.size() - 1
	for i in Campaign.STAGES.size():
		if _stage_open(prog, i, fans) and not _won(prog, i):
			var b: Array = BEATS.get(String(Campaign.STAGES[i].id) + "_brief", [[""," "]])
			return "Next: %s. %s" % [String(Campaign.STAGES[i].title), String(b[0][1])]
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		if Missions.is_unlocked(idx, prog, points) and not Missions.is_cleared(idx, prog):
			return "Next: %s (mission). %s" % [String(Missions.MISSIONS[k].title), String(brief_line(idx)[1])]
	for idx in Missions.play_order():
		if Missions.medal_locked(idx, prog, points):
			return "Next: %s (mission). %s." % [String(Missions.get_def(idx).title), Missions.medal_text(idx, points)]
	if _won(prog, last):
		return "The story is told. Ciocia Basia would like her car back on Saturdays."
	if _won(prog, last - 1):
		return "Next: the Goliath. Pan Zbyszek needs the whole town behind him: reach the top fan level (%s)." % FanLevels.TITLES[FanLevels.TITLES.size() - 1]
	return "Next: drive to a beacon."

## The journal: a header (the act and what comes next), then every seen beat in the order it was seen.
## [{title, lines}] as StoryCard.play takes it.
static func journal(prog: Dictionary, fans: int) -> Array:
	var out := [{"title": "STORY SO FAR", "lines": [["", act_name(prog, fans).to_upper()], ["", next_step(prog, fans)]]}]
	for k in seen_keys(prog):
		var key := String(k)
		if has_beat(key) and not key.ends_with("_brief"):
			out.append({"title": beat_title(key), "lines": lines(key)})
	return out

## Beats as StoryCard.play takes them.
static func cards(keys: Array) -> Array:
	var out := []
	for k in keys:
		out.append({"title": beat_title(String(k)), "lines": lines(String(k))})
	return out
