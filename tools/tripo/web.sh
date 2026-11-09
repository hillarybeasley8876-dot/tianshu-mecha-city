#!/bin/bash
# Run tools/tripo/web.py with its dependency (websockets) via uv.
exec uv run -q --with websockets python3 "$(dirname "$0")/web.py" "$@"
