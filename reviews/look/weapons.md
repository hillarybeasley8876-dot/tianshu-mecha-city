# Look diagnosis items for weapons (lead-verified workflow wf_5e92d07a-bee, 2026-11-02)

Source: an independent critique of the user's screenshot `tmp/lead/user_shot_1.png` (A6 hive fight) against the key art.
Do them in this order (impact per hour). Each item: what is in the picture, the cause (file:line), the fix.

## The empty rifle reads '0 / 9 CHARGE': the trigger silently does nothing and there is no reload cue  (impact 5, ~0.5 h)

**In the picture:** The weapon panel at bottom right (1204-1544, 834-900) shows '0' in white and '/ 9', with the dim word 'CHARGE' and empty charge pips. The gun is empty, yet the HUD tells the player to charge it. Nothing is amber, there is no RELOAD anywhere, and nothing appears at the reticle.

**Cause:** /Users/minimax/m/mecha-city/game/combat/weapons/rifle.gd:60 starts a shot only `if pressed and ammo > 0`. At 0 ammo the press is ignored, `_release()` never runs, and the auto-reload at rifle.gd:123-124 can never be reached. The only way to reload is the R key (/Users/minimax/m/mecha-city/game/combat/weapons/weapon_system.gd:144-145). /Users/minimax/m/mecha-city/game/ui/widgets/weapon_panel.gd:58-59 draws the ammo count in WHITE at any value. weapon_panel.gd:78-87 falls through to the 'CHARGE' state when ammo is 0.

**Fix:** 1. rifle.gd:60: when ammo is 0, a trigger press calls reload(). Also auto-reload 0.25 s after the last round leaves, as AC6 does.
2. weapon_panel.gd: when ammo is 0 and the rifle is not reloading, draw the count in AMBER and replace 'CHARGE' with 'RELOAD [R]' (16 px, amber, outlined).
3. Add a 14 px amber 'RELOAD' tag 40 px to the right of the reticle.

Visual target: Daemon X Machina (ref image 17), where 'RW RELOAD' sits beside the reticle in a bright accent colour.
