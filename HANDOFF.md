# HANDOFF — roadmap H: open-world event rivals on the race AI (branch t3/open-world-rivals-race-ai)

Paused on the 95% quota guard (resets 2026-11-24 16:10 UTC). Do not merge yet: tests are not updated and the full suite has not been run.

## Done (committed)
- `godot/scripts/world/event_track.gd` (`EventTrack`): builds a temporary `Track` from an event route: road-centre line
  (LiveEvents.route_profile centre, junction corners rounded with ROUND_PASSES=3), per-sample half width `HW`, surfaces as
  `Track.loose` spans (kind 3 = map asphalt), road heights, walls `REACH` = HW + 1 m, closed as a loop (40 m lead-in, route,
  `beyond` runout, 120 m stub). Racing line from `Track.build_racing_line_span` (open-ended relaxation, COARSE=5), profile from
  `build_profile`. Build is 42-132 ms (1.2-3.7k samples); `phase_ms` has the breakdown (road_at ~40 ms, line ~70 ms).
- `godot/scripts/world/event_field.gd` (`EventField`): wraps a real `Race` on that track (Drivers.ROSTER bots, full physics,
  traffic, contact). Player = `Race.external_player` mirror of FreeCar.car; contact deltas copied back; `player_hits`
  go to `FreeCar.car_contact` (dents/sounds). No rubber band (`diff_params.band = 0`). Knockout, parking past the finish
  (`Race.park_spot`, `stop_at`, `collide_finished`), gone cars, standings/position/gap like StreetRivals.
- Race/Track changes (default-off, parity-safe): `external_player`, `stop_at`, `collide_finished`, `grip_mul`, `park_spot`,
  `Track.half_at` used in traffic/side_room/pursuit/rail/surface/room/shove, `Track.loose_surf`, `Track(def=null)`.
- LiveEvents: non-drag races use EventField (drag keeps StreetRivals); `tick(..., car)`; `car_model`; `_drop_run` disposes.
- OpenWorld: bots drawn from `car_pose`, circle contact only for drags, `RacingArrows` (`scripts/world/racing_arrows.gd`)
  replace the GPS chevrons during an EventField race, `hud.set_brake_cue`.
- Probes: `tests/_event_field_probe.gd` (OLD=1 for StreetRivals; env ONLY, LEVELS, RIVALS, PACEK, TRACE, OFFDBG, KNOCKS),
  `tests/_live_audit.gd` updated for EventField.

## Measurements so far
- OLD field, rival time / LiveEvents.pace_time (all race events): easy median 1.139 (1.076-1.197), medium 1.095
  (1.041-1.149), hard 1.052 (1.007-1.096). Old audit log: scratchpad audit_before.log (reference driver finishes last nearly always).
- NEW, PACEK=1.0 (race skill unscaled): sprint/11 medium full field 1.085-1.209 (median 1.122); solo fastest bot 1.04-1.16.
- Contacts on sprint/11 medium: 163 bot-bot contact ticks, 3 knocks >= 1.5 m/s (after the parking fix; was 2535).
- Off-road (centre > 0.5 m past the drawn road): 1-3% of samples, on 3 m single-track lanes in bends.

## Next
1. Verify `EventField.PACE` (set provisionally to 0.97/1.0/1.035; only medium checked, on sprint/11 — easy and hard unmeasured;
   medium 1.0, hard 1.035): `LEVELS=easy,medium,hard PACEK= ... godot --headless --path godot -s tests/_event_field_probe.gd`
   against the OLD medians above.
2. Run `_live_audit.gd` (all) and check rivals off-road / stuck; knockouts finish.
3. Update tests: test_live_events.gd (lines ~236, 395, 416, 495, 573, 735 use StreetRivals/rivals()), test_street_rivals.gd
   (drop non-drag cases), test_missions.gd ~645, test_difficulty_profile.gd ~105 (street band), _mission_window_probe.gd.
   Typed `var rv := live.rivals()` must become untyped (`var rv = ...`). Add EventField tests: completes, on road,
   player contact resolves, pace independent of player position, arrows shown.
4. Strip StreetRivals to the drag field; update AGENTS.md open-world section; then run_tests.gd, run_qa.gd, _run_race_test.gd.

## Full-field calibration run (PACEK=1.0, all 18 race events x 3 levels, 59 rival times each, 0 unfinished)
easy median 1.104 (1.042-1.191), medium 1.114 (1.034-1.224), hard 1.123 (1.028-1.179) — at race skill the three
levels barely differ (Race.DIFFICULTY's skill steps are small next to traffic). Against the old medians (1.139 / 1.095 /
1.052) the scale wants roughly easy 0.97, medium 1.02, hard 1.07; hard above ~1.03 drives past the mu=1 profile, so
check spins/off-road there, or widen the level spread another way (e.g. per-level spread/mistakes). Re-measure after.
