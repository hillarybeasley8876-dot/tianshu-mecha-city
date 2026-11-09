# city-layout r8b — lead brief: finish the 3D route rule (18/40 → 40/40)

## Verdict on r8: accepted as a step, not done
The 3D solids model and the route sub-checks a–d exist. They model what the Blender build really
makes: parapets, trusses, viaducts, tunnel linings, building holes, the Spire, the pagoda. The layout
moved from **1/40 to 18/40 connectors passing a–d**, with 47 deck holes, 59 parapet openings and 13
shafts.

The lead re-ran `validate_layout.py`: `18/40 … FAIL (56)`, and `validate_graph`: PASS. The md5 is
`615d1f71…`, deterministic. The honest "not passing" note is the right report.

The hive moves are accepted: `hive_a2` moved 125 m, `hive_a6` 27 m. You posted them; flow and trailer
re-check. The lead is starting city-build r11 now, on your r8 commit, for the items that do not depend
on you. It will rebuild once more on r8b.

## Do (in this order)
1. **The Knot.** Re-design its four ramps and `con_K1_K3_edgejump` so they pass a–d, and give
   `hive_a2` its third inbound route. Use your r8 rule: keep the datums (K3 at +32), and make every 3D
   fix a cut or filter that draws no random number.
2. **The shaft tops.** Four top stops land on no floor, and three columns report a cap. Give each a
   landing deck or a declared opening; city-build builds what you declare.
3. **Headroom.** Ten edgejumps and two ramps fail headroom, because no open take-off exists within
   90 m. For each one, either declare an opening, re-route the graph edge to a kind that fits (L1 allows
   re-routing), or drop the edge with a reason. Never leave a FAIL without a decision.
4. **The C14 regression and the cover.**
   - 135 of 544 crates moved onto route strips. Put them back off the strips without a re-roll.
   - Fix A5's cover pair under 6 m.
   - Fix the L4 points more than 60 m from full cover: A4 at (511,571,+128), A5 at (618,-82,+32),
     A6 at (31,-458,+144).
5. **The per-key diff against r8.** Every change is attributed to one of items 1–4, and nothing else
   moves.

## Gates
- `validate_layout.py`: PASS, and 40/40 connectors pass a–d. Any connector dropped or marked
  `usable: false` is named with its reason in status. Those count as resolved only if L1 still passes.
- `validate_graph.py`: PASS. `build_layout.py` run twice gives an identical md5.
- `layout_diff.py` against r8: every change is attributed.
- No `tools/map` file over 600 lines. `status/city-layout.md` gets an r8b section.
- Post each commit. city-build rebuilds on your final commit.

## Coordination
- city-build r11 runs in parallel, on your r8 commit. Post any new `openings` or `holes` fields in
  Requests before you rely on them.
- Read `reviews/r16-lead-decisions.md` (city-layout sections) and `reviews/r16-conflicts.md` (rows
  E1–E7). Never use git stash.
