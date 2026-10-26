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

- **Campaign:** drive around an open-world Brzeszcze, with its mine headframes, streets, level crossings and a
  train. To start a stage, drive to its beacon.
- **Quick race:** lap or timed endurance races against up to a full grid of AI drivers. With 0 opponents
  it becomes a time trial against your own ghost.
- **Championship:** a calendar of rounds with F1-style points and saved standings.
- **19 tracks:** Nürburgring GP, Nordschleife, Monaco, Indianapolis, Le Mans, Monza, Silverstone,
  Spa-Francorchamps, Suzuka, Zandvoort, Fiat Track and the Tokyo C1 Expressway, plus the Polish stages
  Bielsko-Biała, Kraków, Oświęcim, Wilamowice, Brzeszcze, Pszczyna and Bór.
- **Racing:** tyre wear, fuel, pit stops planned by a strategist, damage, stewards' penalties, yellow flags
  and a safety car, slipstreaming, and AI drivers that learn how you drive.
- **Conditions:** day and night, rain and other weather, and eight camera views.

## Controls

Keyboard and gamepad both work. Press **H** during a race to show the controls on screen.

| Key | Action |
|---|---|
| W / ↑ | Accelerate |
| S / ↓ / Space | Brake / reverse |
| A D / ← → | Steer |
| Q / E | Shift down / up (manual gearbox) |
| C | Change camera |
| P | Request a pit stop |
| R / Backspace | Reset the car onto the track |
| V | Flag speed limiter |
| L / G | Show the racing line / ghost car |
| F1 | Cycle the retro graphics styles |
| M | Mute |
| Esc | Pause |

Menus use the arrow keys, Enter and Esc, or the gamepad's d-pad, A and B.

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

Optional: `python3 tools/fetch_assets.py` downloads CC0 HDRI skies and photo textures from Poly Haven
for extra detail. The game looks complete without them.

## Repository layout

| Path | Contents |
|---|---|
| `godot/` | **The game.** Scripts, shaders, scenes, baked track data and models. |
| `tools/` | Generators: Blender scripts for the 3D models (`tools/blender/`), OpenStreetMap track, surroundings and open-world bakers, and the sound baker. |
| repository root (`index.html`, `js/`, `css/`) | The original browser version, kept as a reference while the Godot port is finished. |

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
