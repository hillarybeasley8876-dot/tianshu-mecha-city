# audio — review r4 (lead, audit round) — PASS

5/5 findings fixed with one game clock for the whole unit (`AudioClock`), each regression proven against the old
code (17-check clocks suite), the metronome handed over when the stream actually switches, plus three open
notes (boss_intro bound, rifle stage ids, the missing `telegraph_unblockable` row). The `on_simple` arity error
(enemies r3 / mech-move r5) was still open: the lead fixed it — simple cues now `unbind()` exactly the
signal's own arguments (perfect_dodge has one); a fight with 14 perfect dodges logs no callable errors.
