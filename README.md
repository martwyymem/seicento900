# Seicento 900 Cup

A racing game about the humble Fiat Seicento 900, made in [Godot 4](https://godotengine.org/). Race it on
famous circuits, Polish city and forest stages, and a free-roam campaign set in the real town of Brzeszcze,
which was rebuilt from OpenStreetMap data. The menus and HUD follow Colin McRae Rally 2.0, and there are
optional PS1/PS2-style retro filters.

## Download and play

Get the latest build from the **[Releases page](https://github.com/martwyymem/seicento900/releases/latest)**.
Nothing needs to be installed.

| Platform | File | How to run |
|---|---|---|
| Windows 10/11 (64-bit) | `seicento.exe` | Download it and double-click it. If SmartScreen warns you, choose **More info → Run anyway**. |
| macOS (Apple silicon or Intel) | `Seicento-macOS.zip` | Unzip it, then right-click `Seicento.app` and choose **Open**. |

The builds aren't signed with a paid certificate, which is why Windows and macOS warn you on first launch.
If macOS says the app "is damaged", remove the download quarantine and try again:

```sh
xattr -dr com.apple.quarantine Seicento.app
```

You need a GPU that supports Vulkan (Windows) or Metal (macOS). If the game runs slowly, lower the graphics
detail under **Options**.

## What's in the game

- **Campaign:** free-roam open-world Brzeszcze (plus Jawiszowice, Wola, Rajsko, east Góra and the S1 corridor),
  with mine headframes, 13 underpasses, level crossings, an EN57 train, cycling traffic lights, an aerial
  satnav map, 9 speed traps, 27 discoverable landmarks, 7 map-only campaign missions, dynamic Forza-style live
  events, and 10 fan levels unlocking playful modifiers (including Nitrous and Monster Truck).
- **Modes:** Quick Race (lap or timed endurance against AI), Rally, Time Trial (per-car records and ghosts),
  and customizable Championship with F1-style points and saved standings.
- **26 tracks (21 circuits & street tracks + 5 rally stages):** 11 circuits (Nürburgring GP, Nordschleife,
  Monaco, Indianapolis, Le Mans, Monza, Silverstone, Spa-Francorchamps, Suzuka, Zandvoort, Fiat Track), 8
  real-OSM city and street loops (Tokyo C1 + Hamarikyu Spiral, Bielsko-Biała, Kraków, Oświęcim, Wilamowice,
  Brzeszcze Kopalnia, Pszczyna, Bór), The Goliath (27 km) and S1 Sprint (9.6 km), plus 5 Brzeszcze-area
  point-to-point rally stages (Mały Bór, Kolonia Stawowa, Babudy–Góra, Rajsko–Wilczkowice, Lipowiec–Kobylec).
- **9 playable cars:** Stock Seicento 900, Hypercar Seicento (AF Corse #83, AWD), and 7 mission-reward cars
  (VW Golf IV, Dacia Logan, Volvo V50 2.4i, Hyundai i20, Dacia Sandero, Ford Focus Mk3.5, Opel Zafira B) with
  real-car physics specs, factory paint palettes and a Garage turntable.
- **Racing & driving feel:** tyre wear, fuel, pit stops planned by a strategist, stewards' penalties, yellow
  flags and a safety car, slipstreaming, AI drivers that learn how you drive, per-car racing-line braking zones,
  and a drift overhaul (billowing tyre smoke, darker skid trails, camera swing/roll, drift score/chain panel and
  player drift assist).
- **Visuals & conditions:** day and night, dynamic weather (dry, wet, snow, hail, fog, variable) in races and
  free roam, 6 retro post-process styles, a Gran Turismo-style rear-view mirror, and Camera & Screen Effects
  (bloom, lens flare, speed FOV, radial speed blur).
- **Damage & festival (unreleased on `main`):** hinged and detachable body panels (bonnet, doors, bumpers,
  boot/tailgate), bending and detaching wheels, spider-web windscreen cracks and shattering side/rear glass,
  per-lamp breakage, localised crush deformation and scraped bare metal; plus Brzeszcze dressed as a sports
  festival with spectator crowds behind barriers, bunting, string lights, inflatable SEICENTO FEST arches,
  stalls, flags, hay bales and night fireworks.

## What's being worked on

Last updated 2026-11-22. The full task list is in [`TASKS.md`](TASKS.md); the port status is in
[`godot/README.md`](godot/README.md).

**Active now (next release)**

- Open-world map geometry & visual sweep: cleaning up the remaining protruding OSM buildings and running
  windowed visual checks (grass LODs, building passages, street-track braking boards, aerial satnav zoom/pan).
- Street track polish: Bór guardrails vs open verges, Bór far horizon, and an urban ground-shading audit.
- Performance follow-ups: re-measuring High/Ultra night-rain frame time on the GP circuit and optional cold
  open-world load optimization.

**Next up**

- Deciding on per-car circuit loading hero stills vs the open-world cover fallback.
- Expanded live-event variety (weather- and time-gated events) and a longer campaign progression arc (cars
  stay mission rewards, never bought with fans).
- Playtest and feel tuning: damage/festival visual polish, physical gamepad QA, and driving/event balance.

## Controls

Keyboard and gamepad both work. Press **H** during a race to show the controls on screen.

| Keyboard | Gamepad | Action |
|---|---|---|
| `W` / `↑` | `RT` | Accelerate |
| `S` / `↓` | `LT` | Brake / reverse |
| `Space` | `A` | Handbrake |
| `A` `D` / `←` `→` | `Left Stick` | Steer |
| `Q` / `E` | `LB` / `RB` | Shift down / up (manual gearbox) |
| `Shift` | `L3` | Nitrous (when modifier is active) |
| `B` | `R3` / `Right Stick` | Look behind / free camera look |
| `C` | `Y` (open world) | Change camera |
| `R` / `Backspace` | `Back` (race) / `X` (open world) | Reset car onto the road / last gate |
| `P` / `T` | `Y` (race / TT) | Request pit stop / restart Time Trial |
| `[` `]` / `-` `=` / `F` / `Shift+R` | `X` (fuel mix) | Pit tyre / fuel / fuel mix / replan strategy |
| `L` / `G` / `V` / `O` | — | Racing line / ghost car / speed limiter / autopilot (race) |
| `M` or `Tab` / `G` / `Enter` / `T` | `Back` / `D-pad ↑` / `B` | Open-world map / GPS / start event / advance time |
| `F1` | — | Cycle retro graphics styles |
| `H` / `M` (race) | — | Toggle controls help / mute |
| `Esc` | `Start` | Pause |

Menus use the arrow keys or `WASD`, `Enter`, `Esc` (`Q`/`E` for tabs), or the gamepad's D-pad / left stick,
`A`, `B`, `LB`/`RB` and `Start`.

## Running from source

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build; no .NET needed).
2. Clone the repository and open the project:

   ```sh
   git clone https://github.com/martwyymem/seicento900.git
   cd seicento900
   godot --path godot
   ```

   You can also open `godot/project.godot` from the Godot project manager. The first import takes a minute.

3. Run the tests headless:

   ```sh
   godot --headless --path godot -s tests/run_tests.gd
   ```

### Running on NixOS

The repository is a flake (`flake.nix`, pinned in `flake.lock`) with Godot 4.7.2 from nixpkgs:

```sh
nix run                       # the game (= godot --path godot); extra args go to Godot
nix develop                   # shell with `godot` and python3 + numpy for tools/
nix-shell                     # the same shell without flakes (shell.nix, via flake-compat)
```

Godot 4.5+ for x86_64 is compiled for SSE4.2, so on older CPUs without it (AMD K10/Llano such as
the E2-3000M, Intel Core 2) both nixpkgs' and the official binary die with `Illegal instruction`.
For those use the `nosse42` variants (`nix run .#nosse42`, `nix develop .#nosse42`,
`nix-shell -A nosse42`). They rebuild Godot from source at the SSE3 baseline without LTO, which takes hours the
first time. On a GPU without Vulkan (pre-GCN Radeons and other old GPUs) Godot picks Mesa's
software Vulkan (lavapipe, `llvmpipe` in the log), which draws nothing for minutes. Use the
OpenGL Compatibility renderer there: `nix run .#nosse42` does by default, and
`SEICENTO_RENDERING_DRIVER=opengl3 nix run` (or `godot --path godot --rendering-driver opengl3`)
does it for the standard build. The headless tests need no GPU.

Optional: `python3 tools/fetch_assets.py` downloads CC0 HDRI skies and photo textures from Poly Haven
for extra detail. The game looks complete without them.

## Repository layout

| Path | Contents |
|---|---|
| `godot/` | **The game.** Scripts, shaders, scenes, baked track data and models. |
| `tools/` | Generators: Blender scripts for the 3D models (`tools/blender/`), OpenStreetMap track, surroundings and open-world bakers, and the sound baker. |
| repository root (`index.html`, `js/`, `css/`, `vendor/`) | The original browser version. Git-ignored and no longer on GitHub; the files stay local as the parity reference. |

The 3D models, tracks and sounds are built by scripts, so to change one, edit the script and rebuild it
rather than editing the output. The developer documentation covers the details:

- [`godot/README.md`](godot/README.md): features, systems, rendering and remaining port work
- [`how2.md`](how2.md): where to change the car, tyres, circuits, AI, graphics and key bindings
- [`TASKS.md`](TASKS.md): the roadmap
- [`AGENTS.md`](AGENTS.md): build commands and conventions (written for AI coding agents, but useful for anyone)

## Credits

- Built with [Godot Engine](https://godotengine.org/) (MIT).
- Map, road and building data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL).
  Terrain heights come from the Copernicus EU-DEM.
- UI font: Nunito Sans (SIL Open Font License).
- Optional HDRIs and textures from [Poly Haven](https://polyhaven.com/) (CC0).

This is a non-commercial fan project. It is not affiliated with Fiat, Stellantis, Codemasters or any of
the circuits shown.
