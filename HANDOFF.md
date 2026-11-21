# Handoff (2026-11-21)

State: `main` pushed through the commit that adds dynamic aspect / HUD WIDTH and the free-roam weather cycle.
Run: `godot --path godot`; tests `timeout 1800 godot --headless --path godot -s tests/run_tests.gd` (ends `0 failure(s)`),
parity `timeout 900 godot --headless --path godot -s tests/_run_race_test.gd` (`errors=0`).

In flight (uncommitted, not in that commit):
- NixOS laptop (linked environment "nixos", project at /home/mikol2137/Developer/Seicento): an Opus agent adds
  `flake.nix` on a local `nixos-run` branch there and runs the tests; bring the flake into main when it reports.

Needs a human in a window: HUD motion feel, HUD WIDTH on an ultrawide, falling rain/snow look and frequency, landmark
snow, canopy tree line, Logan night look, mission rival pace.
Next headless candidates: TASKS.md (Haiku's list: open-world load time, Wola cornfield, track rebuilds, next cars).
Gemini 4 Neon replaces Sonnet for well-scoped and UI work when its quota allows.
