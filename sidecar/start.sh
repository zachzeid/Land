#!/bin/bash
cd "$(dirname "$0")/.."
pip install -r sidecar/requirements.txt -q
python -m uvicorn sidecar.server:app --host 127.0.0.1 --port 8080
