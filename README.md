# Seicento 900 Cup

A 3D browser racing game: you in a Fiat Seicento 900 against up to 15 AI Seicentos, with real elevation,
tyre wear, fuel, weather and working pit strategy. There are eight tracks: the Nürburgring GP-Strecke and
Nordschleife, the Triple Crown circuits (Monaco, the Indianapolis oval and Le Mans' Circuit de la Sarthe) and three Grand Prix
classics (Monza, Silverstone and Spa-Francorchamps).
Races run either over a set number of laps or against the clock, up to a full 24 hours through the night.
A classic top-down 2D view is still available in the setup screen.
Championship mode runs one race on each of the eight circuits, with F1-style points and standings after every round; the standings are saved in the browser, so you can quit and continue later.

## Run

No build step. Three.js is vendored as a plain script (`vendor/three.min.js`, MIT), so opening
`index.html` directly works; you can also serve the folder:

```sh
python3 -m http.server 8765   # then open http://localhost:8765
```

## Controls

| Key | Action |
| --- | --- |
| ↑ / W, ↓ / S, ← → / A D | throttle, brake (hold at a standstill to reverse), steer |
| E / Q | shift up / down (manual gearbox) |
| P | request / cancel a pit stop this lap |
| [ ] | choose the tyre compound for the next stop |
| − / = | fuel to add at the next stop |
| R | ask the strategist to re-plan from the current state |
| C | camera: chase → far chase → roof cam → bird's-eye (2D view: chase ↔ north-up) |
| L / O | racing line, autopilot (co-driver) |
| , / . | time warp down / up (×1 … ×60); the co-driver takes the wheel while it's on |
| M / H / Esc | mute, hide help, pause |

Gamepad: left stick steers, RT/LT for throttle/brake, RB/LB to shift, Y to request a stop, Start to pause.

## How it works

- **Tracks** use real OpenStreetMap geometry (`tools/osm_*.json` → `tools/build_tracks.py` → `js/tracks.js`):
  the GP circuit (5.09 km), the Nordschleife T13 layout (20.69 km), and the Triple Crown circuits, all taken
  from their OSM circuit relations or raceway ways:
  - Monaco, 3.29 km, with the tunnel, the harbour and a city of flats around it.
  - Indianapolis, 4.06 km, with a SAFER wall, catch fence and big grandstands.
  - Le Mans, 13.55 km, including the Hunaudières straight and its chicanes.
  - Monza (5.77 km), Silverstone (5.86 km) and Spa-Francorchamps (6.96 km, with Eau Rouge and Raidillon), from their OSM circuit relations.
- **Elevation**: EU-DEM 25 m heights (NED 10 m for Indianapolis) from the OpenTopoData API
  (`tools/fetch_elevation.py`, cached in `tools/elevation.json`), covering both the centreline and a terrain grid.
  Monaco's road uses the circuit's published profile (sea level to 42 m at Casino), because the DEM there picks
  up buildings and the cliff above the tunnel. The Nordschleife runs from 340 m
  at Breidscheid to 629 m at Hohe Acht. Road gradient feeds the physics: the Seicento crawls up the
  climbs and reaches about 157 km/h downhill.
- **3D** (`js/render3d.js`): terrain blended into the road, kerbs, Armco or tyre walls, pit garages,
  grandstands, a start gantry with working lights, instanced forests, and a Seicento model built to the real
  car's proportions (lofted body, teardrop headlights, tall tail lights, wraparound bumpers, hubcaps) with steering,
  spinning wheels, working head and brake lights, body roll and pitch. Also shadows, a sky that turns grey with rain, and a
  glossy wet track. Surfaces are procedural but detailed: asphalt with aggregate, normal and roughness maps
  and a rubbered-in racing line, gravel, grass without visible tiling, earthy banks, and layered spruces and
  leafy broadleaf trees (detailed near the camera, simpler further out). High/Ultra light the scene
  physically from the sky, with haze that takes the horizon's colour, bloom only on real light sources, and a
  light camera grade (vignette, grain).
- **Car model** (`js/car.js`): the 899 cc engine's torque curve (39 hp @ 5500, 65 Nm @ 3000), five-speed
  gearing, drag and rolling resistance, FWD traction limit and fuel burn from brake-specific fuel consumption.
  That gives 0–100 km/h in about 18 s and a top speed of about 140 km/h, close to the real car.
- **Vehicle dynamics** (`js/physics.js`): your car is a rigid body on four tyres, simulated at 960 Hz.
  - Pacejka "Magic Formula" tyres with combined slip (braking or accelerating costs cornering grip), load
    sensitivity, and per-wheel surface grip (two wheels on the grass really do pull you off).
  - A sprung body: weight shifts forward under braking and outward in corners; the inside rear wheel lifts
    at the limit, just like the real car; lifting off or trail-braking can rotate the rear.
  - Each wheel spins on its own: engine inertia and engine braking, an auto clutch that never stalls, and an
    open front differential (the unloaded inside wheel spins up first). Front-biased brakes lock the fronts.
  - Rigid-body contact: hitting a barrier or another car with a corner spins you the way it would for real,
    and scraping along a wall costs speed through friction.
  - Driving aids (menu): ABS + traction control + stability control, ABS only, or none — applied equally
    to you and every bot, so nobody's on a setting you didn't choose. On the full tier, a steering guide
    (`js/driver.js`) also caps a keyboard or pad's digital "full lock the instant you press it" to a bit
    more than the angle the coming corner's curvature actually needs — the same pure-pursuit geometry
    that steers the bots — so mashing the key through a gentle bend doesn't throw the car into a slide the
    bots would never suffer for the same corner. It only touches steering that's already pointed the way
    the corner goes; opposite-lock, drifting or anything else is untouched.
  - Bots and the lap simulator include the same cornering drag from tyre scrub, so the field stays matched.
- **Tyres**: Soft / Medium / Hard / Wet compounds, each with its own grip and life, plus a wear cliff, warm-up
  and wet-weather crossover (slicks lose grip as the track gets wet; wets overheat on a dry track).
- **Strategy** (`js/strategy.js`): a lap simulation calibrates how lap time responds to grip and fuel mass,
  and measures the time lost in the pit lane. A dynamic programme then finds the fastest stint plans that obey
  the rules: mandatory stop, two dry compounds, refuelling ban, tank size, crew speed, and service done in
  parallel or in sequence.
- **AI** (`js/race.js`, `js/driver.js`): at normal speed, bots drive the same four-wheel physics as the player
  — the same tyres, aero, gearbox and grip — steered by a pure-pursuit controller (`js/driver.js`) chasing a
  target speed and line rather than a scripted pace. They lock up, run wide, spin and have to recover exactly
  like you do; a lighter rail model (speed/position solved directly, no tyre forces) takes over only under
  time warp, in the pit lane, or while a spun car rejoins, so it never has to look convincing at ×60. A
  learning brain (`js/brain.js`) picks each bot's target pace per corner from its skill and studies you lap by
  lap — your cornering speed, line, and where you like to pass — and both the learning and the odd real
  mistake (missed apex, late brake) come from that pace model, whatever's driving the car underneath. Bots
  slipstream, overtake, and follow their own pit strategies, re-planning live when the rain comes, tyres wear
  out or fuel runs low. On top of that, a difficulty-scaled rubber band (off entirely on Alien) leans on
  pace a few percent once a gap passes about 5 seconds, so one mistake costs you the position without
  costing you the race, and the reverse: bots that have fallen well behind push a little harder to stay
  relevant. It fades to nothing once the gap closes back up, so it never overturns a real pace difference.
- **Pit lane**: 60 km/h limiter, a box for each car, and service time based on the crew, the tyre change and
  the litres of fuel added. Cars queue in the fast lane and are held in the box until it's safe to release them.
- **Endurance races** (15 min to 24 h):
  - The flag falls when the leader crosses the line after the clock runs out.
  - Long races are planned over a rolling horizon of about three tanks, and every car extends its plan as it goes.
  - Variable weather brings a shower every few hours.
  - The local time of day runs in real time from the chosen start time, with a June sun path, dusk, stars,
    headlights, lit windows and pit garages at night.
  - Time warp (up to ×60) hands the car to the co-driver, and the strategist calls the stops while they drive.
