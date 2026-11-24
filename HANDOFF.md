# Handoff: harder Stage 1 (Wilamowice, idx 0) + Nordschleife (stage_eifel, idx 10)
State: nothing in campaign.gd changed yet. Only tests/_campaign_ladder_probe.gd got env overrides
(GRID=, OPP=, RIVALS="sandero:2,stock:5", SHIFT=) so layouts can be tried without editing data.
Setup per CLAUDE brief: rsync gitignored godot assets, `godot --headless --path godot --import`, HOME=$PWD/.gate_home_X.

## Probe convention (worked out)
Projected human = autopilot total x 0.945; margin m1 = human - best rival time (negative = clear), m3 = vs 3rd rival.
Autopilot skill H saturates: H=0.97..1.0 give the same lap (~311 s on stage 1), so use H=1.0.
Scratchpad helpers (may be gone): probe.sh (per-run HOME, greps RESULT/TIMES) and summ.py (prints m1/m3).

## Stage 1 findings (H=1.0, seeds 0-1; baseline 6 seeds at H=0.945 gave m1 -7.2..-7.7)
- baseline p5/6 stock x5: m1 -9.0 (P1 rival ~302.6 s, human ~294)
- p8, 7 opps (all stock): -6.3 (traffic costs the autopilot ~2 s only)
- 2 Sanderos + 3 stock (p5): -11.6; Sandero as a rival/player is NOT faster than a Seicento on Wilamowice
  (player in sandero 302.5 vs stock 302.3): check the Sandero's rail profile/kit for a bug or accept it.
- p8, 7 opps, 2 Sanderos: -8.1
- SHIFT +1.0 level: -10.0 (noisy -7.5..-12.4); rival P1 time pinned ~300.8-302.7 whatever the level
- Player slot test on stage 1 (CAR=, autopilot): focus 270.0 s, v50 272.9, zafira 287.3, sandero 302.5, stock ~311.6.
=> Rivals cannot get faster than ~301 s with Seicentos; to reach m1 about 0 (P1 ~ 294-298 s) the field needs a quicker car:
   one Zafira (~288-290 s as a rival) as P1 would give roughly +5 to m1 and keep P3 reachable (but it is Touring, two classes
   above City: needs the user's OK), or fix the Sandero pace. Not yet measured as a rival.
## Nordschleife: see numbers printed when this file was written (baseline 4 seeds); no lever tried yet.
Next: try RIVALS=zafira:1,stock:4 (and with GRID=p8 OPP=7) on stage 0; Nordschleife: replace v50 with focus/zafira,
SHIFT=1..2, find why v50 does not speed up past hard (likely physics-limited, not a skill clamp: Race.DIFFICULTY alien skill .995).
Then edit stage data, update tests/test_campaign_ladder.gd, run run_tests/run_qa/_run_race_test, commit.
