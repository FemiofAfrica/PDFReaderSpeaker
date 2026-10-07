#!/bin/sh
# kokoro-worker — Launches the Kokoro TTS Python worker in a clean environment.
# unset PYTHON{PATH,HOME} and use python -I (isolated mode) so no external
# venv (e.g. Hermes agent) can pollute the import path.
BASE="$HOME/Library/Application Support/LatteReader/kokoro"
unset PYTHONPATH
unset PYTHONHOME
exec "$BASE/.venv/bin/python" -I "$BASE/kokoro_worker.py"
