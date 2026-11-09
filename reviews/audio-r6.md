# audio r6 — lead brief: the credits name exactly what ships, file by file

One acceptance finding, `audio-credit-facts` (minor, in `~/m/mc-lead/accept/findings_all.json`; minor findings were
not adversarially verified), plus two defects found at HEAD while this brief was written (items 4 and 5). The
finding was made on the frozen copy at `b5d26d4`. HEAD is `79c69d3`, `git log b5d26d4..HEAD -- game/audio tools/sfx
game/ui/menus/credits_data.gd` is empty, and every repro below was re-run on the live tree. Re-check each item on
HEAD first anyway; if one is already fixed, say so with the evidence.

## Why
Everything that ships is CC0 (the finding re-read all 8 OGA SFX pages on 11-05), so no attribution is missing. But
the credits page is a public claim, to the player and to the people who made the sounds, and hud builds it from
your facts: `game/ui/menus/credits_data.gd` reads `audio_manifest.csv` and copies `CREDITS_AUDIO.md` by hand. Today
those facts credit a pack nothing uses, credit four recordists' library to its uploader, point five tracks at a
collection page instead of the track, and claim licence records that do not exist. This round changes provenance
only: **no audio file changes.**

## 1. A credited pack that nothing ships — minor
- **Defect:** `CREDITS_AUDIO.md:24` and `status/audio.md:17` credit "OGA — Monster Sound Effects 2" (ogrebane) for
  boss vocal bases, and hud copies it (`credits_data.gd:19`). No shipped file layers it: `recorded.py:117` maps
  role `huge` to `oga_monster2`, but the role map in `creature_voice` (`bank_common.py:204-205`) never produces
  `huge`, so that entry and the pack at `sources.py:50` are dead code. `bank_enemies.py:3` drifts the same way: it
  says "Bases are synthesised, not sampled", yet 20 ids layer OGA — 80 CC0 Creature SFX.
- **Repro:** `grep -c 'Monster Sound Effects 2' game/audio/audio_manifest.csv` → 0;
  `grep -n '"huge"' tools/sfx/*.py`; `sed -n 204,205p tools/sfx/bank_common.py`.
- **Done:** the pack is gone from both docs, the dead entry and the pack are removed, and the docstring says what
  the bank does. Do not layer the pack in instead: that changes the boss's voice, and judging it needs an ear.
- **Gate:** item 6 flags the pack on HEAD and not after the fix.

## 2. The Firearm library is credited to its uploader — minor
- **Defect:** "bart" in `CREDITS_AUDIO.md:27`, `status/audio.md:20`, `sources.py:56` (so in the author cell of all
  25 manifest rows that layer it) and hud's `credits_data.gd:22`. The OGA page
  (https://opengameart.org/content/the-free-firearm-sound-library) reads "Author: Ben Jaszczak, et al. (Submitted
  by bart)", "License(s): CC0", and in its Attribution Instructions "These sounds were created and recorded by Ben
  Jaszczak, Brian Nelson, Kevin Heras, and Matthew Nanney".
- **Root cause, so a re-fetch writes "bart" again:** `oga_fetch.py:22` (`AUTHOR_RE`) takes the first
  `/users/<name>` link after the author field. Here the author is plain text (`<span class='username'>` with no
  link), so the first link is the "Submitted by" one. Run on the live page while writing this brief, it returned
  `bart`; on a normal page (100 CC0 SFX) it returns the linked author.
- **Done:** the fetcher records what the page states (the author field's own text, and the Attribution
  Instructions when present), and the four creators are credited (optionally "submitted to OGA by bart") in
  CREDITS_AUDIO.md, the status file, `sources.py` and from there the manifest. `sources.py:37-58` types every
  author by hand, while `music_tracks.py:45-61` reads them from the sidecars: whichever way you go, item 6
  compares the two.
- **Gate:** item 6 shows the firearm record holding the four names, and every credit agreeing with it.

## 3. The licence records the status file claims do not exist — minor
- **Defect:** `status/audio.md:5-7` says every pack's licence and author were read off its OGA node at fetch time
  into an `oga_sources.json` sidecar. Only `oga_bossmetal`, `oga_kenney2` and `oga_music` have one. Seven shipped
  packs have none: `oga_creature`, `oga_firearm`, `oga_moresounds`, `oga_scifi50`, `oga_sfx100`, `oga_sfx100v2`,
  `oga_swishes` (`oga_monster2` neither; item 1 retires it). Kenney Sci-Fi Sounds is not on OGA: its record is the
  archive's own `kenney_scifi/License.txt` (CC0). Kenney Digital Audio's is `oga_kenney2/oga_sources.json`, by URL.
- **Repro:** `for d in art/audio_src/oga_*; do printf '%s ' "${d##*/}"; ls "$d" | grep -c oga_sources.json; done`
- **Done:** every third-party pack and track a shipped file layers has a record on disk that says CC0, written by
  the fixed `oga_fetch.py` without `--get` (no re-download) and dated; the status sentence says these seven were
  recorded on 11-05, not at fetch time. In the same tool, `:67-69` prints "skipping" for a licence outside
  CC0/CC-BY but still records and downloads it, and `get()` (`:26-29`) never retries (one OGA page timed out here).
- **Gate:** item 6 finds no shipped pack without a CC0 record.

## 4. Five music rows credit a collection, not the track — minor (found at HEAD)
- **Defect:** `build.py:31-33` gives 5 of the 6 clip rows the source "OpenGameArt CC0 music collection" and the URL
  https://opengameart.org/content/cc0-music-0: a user's (midcyber's) "CC0 Music" collection page, where no licence
  was read. The track and its page survive only inside the author cell, e.g.
  `chester01 (https://opengameart.org/content/epic-combat)`; the boss row does name its track. No CREDITS_AUDIO.md
  row is that "collection", so five shipped files cannot be joined to a credit.
- **Repro:** `grep -n 'cc0-music-0' game/audio/audio_manifest.csv tools/sfx/build.py`
- **Done:** all six clip rows name their track in one format, with the track's own page as `source_url`, and each
  joins to exactly one row of the CREDITS music table. hud keys on these strings (`credits_data.gd:37-42`).
- **Gate:** item 6.

## 5. A partial build strips every pack credit from the manifest — minor (found at HEAD)
- **Defect:** a row's pack set is filled only while the row renders (`build.py:56`, read at `registry.py:50`).
  `--manifest-only` (`build.py:143-145`) renders nothing and `--only=<id>` (`:146-161`) renders one id, yet both
  rewrite every row. A dry run on HEAD (`build.manifest_rows()`, no render) gives 0 of 240 SFX rows naming a pack;
  the committed manifest has 160. Items 2 and 4 need a regenerated manifest, so this is the trap of the round.
- **Done:** both modes write exactly what a full build writes, or refuse with a non-zero exit and a message. Until
  then, regenerate the manifest only with a full `tools/sfx/run.sh build.py`.
- **Gate:** after a full build, copy the manifest to `tmp/audio/`; run `--manifest-only`, then `--only=rifle_fire`,
  and `cmp` each against the copy (or show the refusal). Old code: same run shows the loss; `git checkout` after.

## 6. The gate itself: `tools/sfx/credits_check.py`
One command from the repo root, `tools/sfx/run.sh credits_check.py`; it exits 0 only when everything matches.
- **Lists every shipped audio file**, one line each: file → manifest source(s) → CREDITS_AUDIO.md row(s) → licence.
  "Shipped" = every `.wav/.ogg/.mp3/.flac` under `game/` outside `.godot/` and the export's own excludes
  (`game/export_presets.cfg:8-10`: `*/tests/*`, `*/demo/*`). Today: 300.
- **Per credited pack or track:** the files and ids that layer it, its licence record's path, and that record's
  licence and author.
- **Fails, in either direction, on:** a shipped file with no manifest row, or a row whose file is gone; a source
  with no CREDITS row, or with a different licence; a CREDITS row, or a pack or music row in `status/audio.md`,
  that no shipped file names; a `sources.PACKS` entry nothing uses; a shipped third-party source with no CC0
  record, or credited (in CREDITS_AUDIO.md or the manifest's author cell) to someone its record does not name.
  Without `art/audio_src/` (a clean checkout) it says so and fails that part; it never crashes.
- **Ends with one summary line**, e.g. `files=300 unmatched file→credit=0 credit→file=0 no_record=0`.
- **Both docs follow it.** "Used for" describes the ids the check lists: `CREDITS_AUDIO.md:25` says 202 More Sound
  Effects serves "weapon switch", but `weapon_switch` layers Kenney Sci-Fi and 100 CC0 SFX, and 202 More is
  layered only by `block`, `missile_launch` and `reload`. Counts come from the check: the Files column in
  `status/audio.md:9-21` counts pack members on disk (73, 62, …, "30 (curated from 104)"), not what ships. One
  table beats two: the status file may point at CREDITS_AUDIO.md and paste the check's summary.
- **It must FAIL on HEAD:** commit the check first and run it on the unfixed tree into
  `tmp/audio/r6_credits_head.txt`. It must flag item 1's pack, item 3's seven packs and item 4's five rows.

## Gates
- **The check:** `tools/sfx/run.sh credits_check.py > tmp/audio/r6_credits.txt; echo "exit=$?"` → exit 0 and a
  summary of all zeros; `tmp/audio/r6_credits_head.txt` holds the HEAD failures.
- **The rebuild:** one full `tools/sfx/run.sh build.py`, then `git status --short game/audio`: **no `.wav`
  changes.** The five OGG beds re-encode with new container serials (`status/audio.md:47-50`), and so do the six
  clips if you re-run `music_tracks.py`: restore them from HEAD and commit no audio file. `git diff --word-diff
  game/audio/audio_manifest.csv` touches only the cells items 2 and 4 name.
- **Item 5:** the `cmp` pair. **The firearm record:** `art/audio_src/oga_firearm/oga_sources.json` holds the four
  names and `CC0`.
- **Unchanged:** `tools/godot.sh check --only=res://audio/` (0 errors, 0 warnings) and
  `tools/godot.sh test res://audio/tests/test_audio.gd` (PASS).
- **File size:** `wc -l` on every file you touch; none over 600 lines (split in its own commit first). Every file
  in `tools/sfx/` is under 300 today.
- **Status:** `status/audio.md` gets an r6 section (per item: the HEAD re-check, cause, fix, re-run output), the
  check in How to verify, and Request 4 closed (hud's page already reads the manifest, `credits_data.gd:98-121`).
- **Commits:** an explicit path list (hero-v3 has uncommitted files in the tree); no dead code; no "fixed" without
  the re-run.

## Coordination
- **hud r6 runs at the same time** and owns `game/ui/**`, `credits_data.gd` included: do not edit it. Its brief
  says to copy author changes into `PACKS` (`:12-23`); this round also drops a `PACKS` row and renames the music
  keys in `OTHER` (`:37-42`). Until hud copies them, its page lists each unknown source with a `push_warning`
  (`:72-76`). Before you commit the manifest, post the exact final strings (pack names, the firearm credit, the
  music sources) in your Requests; the lead forwards them.
- **Granted:** writing `oga_sources.json` in `art/audio_src/<pack>/` (lead-owned `art/**`, git-ignored); touch no
  download. **Yours:** `game/audio/**`, `tools/sfx/**`. **Not yours:** `.gitignore`, `game/ui/**`,
  `game/export_presets.cfg`, `docs/**`. Whether the records get committed is the lead's call (`.gitignore:18`).
- **Requests from other rounds may arrive:** skills r4 (`timeline_reel.json` t=46 rift_step now blinks ~44 m);
  mech-move r7's Feel `last_stand` and feel r5's `boss_kill` (no sound row, so one unknown-id warning each once
  they land). Log them; they are not this round.
- **Requests channel:** the Requests section of `status/audio.md`.
