# trailer r4 — lead brief: the captures batch (run ONLY when the lead dispatches it with the user's OK)

## Why
Since 11-05 every unit has worked headless, because the user works on this Mac and windowed Godot runs
take over the screen. Each unit listed the windowed proof it could not take under **"Captures needed"**
in its status file:
- `audio`, `enemies`, `feel`, `flow`, `hero-v3`, `hud`, `mech-move`, `melee-defense`, `monster-assets`,
  `weapons` (`status/<unit>.md`).

The user has OK'd the screen for this run. You own the capture and render tooling, so you run them all.

## Rules for this run
- `MC_WINDOW_OK=1` is set for you. ONE Godot window at a time, strictly sequential. Never `open` the
  exported app.
- Read each unit's "Captures needed" section and run its commands EXACTLY as written, fixing only
  obvious path typos. Some are multi-line commands with `\` continuations.
- If a command fails or produces something different from what the unit expects, do not fix the
  unit's code. Record it, and move on.
- Never use git stash. Commit only under `captures/`, `tmp/trailer/` and `status/trailer.md` (where
  allowed); the captures folder is git-ignored anyway.

## Deliver
1. For each unit, a contact sheet `captures/batch_r4/<unit>_sheet.jpg` of every image or movie frame
   its section asked for, labelled with the command and the timestamp.
2. A table in an r4 section of `status/trailer.md`: unit, command, exit code, engine errors, output
   paths, and one honest line on what the image shows against what the unit claimed. Examples: "the
   shield reads as a translucent cyan cap with a rim: matches"; "the plume is still a white slab:
   DOES NOT match".
3. Leave the frames in place. The lead reviews every sheet.

## Order
Run the quick stills first and the movies last:
1. hud
2. melee-defense
3. weapons
4. hero-v3
5. mech-move
6. flow
7. enemies
8. feel
9. monster-assets
10. audio

Budget about 60–90 min.

## Dispatch (11-09 03:20)
The user OK'd the screen ("现在全部跑，我离开电脑"). Prefix every windowed command with `MC_WINDOW_OK=1`.
One window at a time. This run comes right after your r5 re-record, so the build is unchanged since then.
