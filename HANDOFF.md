# Handoff: harder Nordschleife (stage_eifel). Wilamowice deferred (being converted to an A->B sprint elsewhere).
Done (committed, full suite NOT yet confirmed green; first run segfaulted in test_ui_and_audio town builder under load, rerun alone in progress: .gate_suite2.log):
- campaign.gd stage_eifel: 14 opponents, grid p15, rivals v50:8 focus:5 zafira:1, pace 1.0 (Alien), "boost": 0.065.
- Campaign.skill_boost(stage) = boost * clamp(level-2,0,1); configure_stage sets RaceSettings.skill_boost (new, default 0).
- Race.build_field adds skill_boost to rivals' skill; Brain.add_bot lifts talent (0.999) and cap (1.004) ceilings by it.
  Cause of the V50 cap: skill saturates at Alien (0.995) and Brain clamps talent/cap at 0.999/1.004; the V50 is also grip-limited (~660 s).
- tests/test_campaign_ladder.gd: skill_boost checks. Probe: GRID/OPP/RIVALS/SHIFT/BOOST env overrides.
Results (H=1.0, human = auto x 0.945, 4 seeds): baseline m1 -20.6 (-10.7..-33.0, 3 seeds) -> now +0.1 (-3.0..+6.4); P3 margin -13.6.
run_qa 0 failures; _run_race_test completed=true errors=0.
