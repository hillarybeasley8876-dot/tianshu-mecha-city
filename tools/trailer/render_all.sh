#!/bin/bash
# Render every take the cut needs (see tools/trailer/render_all.py for the options).
exec python3 "$(cd "$(dirname "$0")" && pwd)/render_all.py" "$@"
