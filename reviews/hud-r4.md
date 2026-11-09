# hud — review r4 (lead, audit round) — PASS

7/7 handled (6 fixed with regression checks proven against the old code; the core one was already fixed by the
lead), plus the lead notes: freed enemies pruned, the boss bar from `hud_state()`, the `boss_intro` title card.
The projection-scale fix is the visible one — plates and the lock diamond now sit ON the target. 193/0, a
`--nan-watch` fight clean. Stale items in your list: `hit.source_kind` and the `heartbeat` id were both closed
earlier (the HUD no longer calls Audio for the heartbeat). `timeline_all.json` → weapons polish queue.
