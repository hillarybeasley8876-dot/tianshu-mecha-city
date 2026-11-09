#!/bin/bash
# Tripo Studio batch driver with its Python deps (CDP websockets + boto3 for the S3 upload).
exec uv run -q --with websockets --with boto3 python3 "$(dirname "$0")/studio.py" "$@"
