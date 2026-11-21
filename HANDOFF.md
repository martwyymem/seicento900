# Handoff (2026-11-21)

State: `main` pushed through the commit that adds dynamic aspect / HUD WIDTH and the free-roam weather cycle.
Run: `godot --path godot`; tests `timeout 1800 godot --headless --path godot -s tests/run_tests.gd` (ends `0 failure(s)`),
parity `timeout 900 godot --headless --path godot -s tests/_run_race_test.gd` (`errors=0`).

In flight (uncommitted, 2026-11-21 ~11:00):
- Hyundai i20 (Gemini 4 Neon, key `i20`): half done; 17 test failures are all i20 WIP (catalogue key, spec name,
  roof height, wheels, mission reward/story). Finish it or revert its files before committing anything else.
- V50 model polish (Gemini 4 Neon): build_v50.py / v50.glb only.
- Cold open-world load, streets path (Opus): town_builder.gd streets / town_map.gd; must keep _mesh_fingerprint hashes.
Gemini delegates can finish and then hang "waiting for run_tests": read their thread, cancel, test, commit yourself.

Needs a human in a window: HUD motion feel, HUD WIDTH on an ultrawide, falling rain/snow look and frequency, landmark
snow, canopy tree line, Logan night look, mission rival pace.
Next headless candidates: TASKS.md (Haiku's list: open-world load time, Wola cornfield, track rebuilds, next cars).
Gemini 4 Neon replaces Sonnet for well-scoped and UI work when its quota allows.
