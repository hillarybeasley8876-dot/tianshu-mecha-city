#!/bin/bash
# hero-v3: shoot every gait filmstrip and tile the contact sheets the lead judges.
#
#   zsh blender/hero3/shoot_strips.sh            all five strips
#   zsh blender/hero3/shoot_strips.sh walk run   just these
#
# Each strip writes its measured stride / cadence / double support / pelvis height to
# captures/hero3_strip_<name>.txt, which make_strip.py draws across the top of the sheet.
set -u
ROOT="$HOME/m/mecha-city"
cd "$ROOT" || exit 1
STRIPS=("$@")
[ ${#STRIPS[@]} -eq 0 ] && STRIPS=(walk run strafe back turn)

for name in "${STRIPS[@]}"; do
  echo "=== $name"
  tools/godot.sh shot --scene=res://player/model/hero3/hero3_strip.tscn \
      --strip="$name" --views=front,side --out="hero3_strip_$name" 2>&1 \
    | grep -E "^STRIP [a-z]+  stride" | tee "captures/hero3_strip_$name.txt"
done

uv run --with pillow python3 blender/hero3/make_strip.py "${STRIPS[@]}"
