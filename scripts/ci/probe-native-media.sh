#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
mkdir -p build/ci/logs
# Framework-only control: no nTV target, personal account or network media.
fixture=$(find OrivioTV -name ntv-player-fixture.mp4 -type f)
[[ -n "$fixture" && "$fixture" != *$'\n'* && -s "$fixture" ]]
python3 - "$fixture" <<'PY' 2>&1 | tee build/ci/logs/native-host-probe.log
import subprocess, sys
try:
    result = subprocess.run(["xcrun", "swift", "scripts/ci/NativeMediaProbe.swift", sys.argv[1]], timeout=90)
    raise SystemExit(result.returncode)
except subprocess.TimeoutExpired:
    print("Native host probe exceeded 90 seconds.", flush=True)
    raise SystemExit(124)
PY
