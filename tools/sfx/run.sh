#!/bin/bash
# Run a tools/sfx script with the audio toolchain (numpy/scipy/soundfile from PyPI, no venv).
#   tools/sfx/run.sh build.py [--only=rifle_fire]   render the bank
#   tools/sfx/run.sh measure.py                    loudness / peak report
set -eu
cd "$(dirname "$0")"
exec uv run --with numpy --with scipy --with soundfile python "$(basename "$1")" "${@:2}"
