#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
mkdir -p build/ci/logs
stage=$(mktemp -d "${TMPDIR:-/tmp}/ntv-media-probe.XXXXXX")
app="$stage/NativeMediaProbe.app"
mkdir -p "$app"
fixture=$(find OrivioTV -name ntv-player-fixture.mp4 -type f)
[[ -n "$fixture" && "$fixture" != *$'\n'* && -s "$fixture" ]]
cp "$fixture" "$app/ntv-player-fixture.mp4"
python3 - "$app/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.ntv.media-probe', CFBundleExecutable='NativeMediaProbe',
        CFBundleName='NativeMediaProbe', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1.0', MinimumOSVersion='17.0', UIDeviceFamily=[3],
        CFBundleSupportedPlatforms=['AppleTVSimulator']), f)
PY
xcrun --sdk appletvsimulator swiftc -swift-version 5 \
  -target "$(uname -m)-apple-tvos17.0-simulator" \
  -sdk "$(xcrun --sdk appletvsimulator --show-sdk-path)" \
  scripts/ci/NativeMediaProbe.swift -o "$app/NativeMediaProbe"
codesign --force --sign - "$app"
simulator=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    if ".tvOS-" in runtime:
        for device in devices:
            if device.get("isAvailable"):
                print(device["udid"]); raise SystemExit(0)
raise SystemExit("No available tvOS simulator")')
xcrun simctl boot "$simulator" || true
xcrun simctl bootstatus "$simulator" -b
open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$simulator"
xcrun simctl install "$simulator" "$app"
python3 - "$simulator" <<'PY' 2>&1 | tee build/ci/logs/native-simulator-probe.log
import subprocess, sys
try:
    result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', sys.argv[1], 'com.ntv.media-probe'], timeout=90)
    raise SystemExit(result.returncode)
except subprocess.TimeoutExpired:
    print('Native simulator probe exceeded 90 seconds.', flush=True)
    raise SystemExit(124)
PY
python3 - build/ci/logs/native-simulator-probe.log <<'PY'
import pathlib, sys
log = pathlib.Path(sys.argv[1]).read_text()
assert 'audiovisual status=1 advanced=true' in log, 'Simulator audiovisual control did not play'
assert 'video_only status=1 advanced=true' in log, 'Simulator video control did not play'
PY
