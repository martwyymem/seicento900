# Handoff (2026-11-24 ~19:30 UTC, paused at 90% of the 5-hour limit; reset 21:10 UTC)

Goal: ship **0.6.0** (user: "release 0.6.0 when everything's merged"; push to GitHub, publish builds).

## Merged on main (HEAD 82f900a)
Rival car ladder (B1/B2), start lights + event spectators, stage dressing (C), campaign from the open world (E),
400/500 m braking boards, mission crowds + organisers' trailer, drivers in every car, A->B sprints (16 stages, ARC 3),
open-world rivals on the race AI (H), harder Nordschleife (skill_boost). Full suite was green at bd4c619.

## Running / to check
- Release gate (no export) on 247d6ca (before the Nordschleife merge): output
  /private/tmp/claude-501/-Users-martwyymem-Developer-Seicento/730f2050-173f-47f1-be2d-712510039c03/scratchpad/gate_247d6ca.out
  If red: fix on main. Then run the full gate (with exports) on the final HEAD.

## User answers (2026-11-24 evening)
- Pop-up: run it on **Gemini 4 Neon** (antigravity_2). Still "Provider is not authenticated" at ~19:40 UTC: retry delegate_task on Neon after the reset; if still unauthenticated, tell the user (don't switch models unasked).
- Stage 1: **no Zafira, Seicentos only.** Leave the stage-1 field as Seicentos.
- Permanent live-event arches/spectators: **keep them** (no change).
- The no-export gate run on 247d6ca was cut off by the session end: rerun the full gate on HEAD.

## Original questions
1. Settings pop-up when entering a stage/mission/event in free roam (VERY important to the user). Neon (antigravity_2) was
   "not authenticated"; asked whether to run it on Claude Sonnet now. Brief is in the thread (task "Stage settings pop-up").
   Should be in 0.6.0.
2. One Zafira in stage 1 (Wilamowice, now a 5.75 km sprint) to make it harder: needs the user's yes; re-measure with
   tests/_campaign_ladder_probe.gd (RIVALS=zafira:1,... overrides) after.
3. Remove permanent live-event arches/spectators at events not being raced (FestivalDressing.sync_live_events)?

## Ship steps
Gate green on HEAD -> bump godot/project.godot config/version 0.6.0, export_presets Windows 0.6.0.0, macOS version 17;
TASKS.md baseline -> commit -> push main + tag 0.6.0 (HTTPS via gh credential, see memory pushing-to-github) ->
gh release create 0.6.0 --target <full sha> with build/seicento.exe and the ditto-zipped app (upload with retries).
