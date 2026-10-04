#!/usr/bin/env bash
set -euo pipefail

task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
output="$task_root/build/ci"
results="$output/results/ntv-ui-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$output/logs" "$results"
xcrun simctl list devices available --json > "$output/simulators.json"
simulator=$(python3 - "$output/simulators.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    devices = json.load(handle)["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if ".tvOS-" in runtime:
        for device in entries:
            if device.get("isAvailable"):
                print(device["udid"])
                raise SystemExit(0)
raise SystemExit("No available tvOS simulator on this runner.")
PY
)

xcrun simctl boot "$simulator" || true
xcrun simctl bootstatus "$simulator" -b
# Keep the result bundle available for screenshots even when the test fails.
set +e
xcodebuild test \
  -project OrivioTV.xcodeproj -scheme OrivioTV \
  -configuration Debug -sdk appletvsimulator \
  -destination "platform=tvOS Simulator,id=$simulator" \
  -derivedDataPath "$output/DerivedData" \
  -resultBundlePath "$results/navigation.xcresult" \
  -only-testing:OrivioTVUITests/NTVDesignSmoke \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  2>&1 | tee "$output/logs/ntv-ui.log"
test_pipeline=("${PIPESTATUS[@]}")
set -e

export_status=0
if [[ -d "$results/navigation.xcresult" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$results/navigation.xcresult" \
    --output-path "$output/screenshots" \
    2>&1 | tee "$output/logs/screenshots.log"; then
    :
  else
    export_status=$?
  fi
else
  printf 'No UI-test result bundle to export.\n' >&2
  export_status=1
fi

# Exporting diagnostics must never turn a failed test into a green job.
for status in "${test_pipeline[@]}" "$export_status"; do
  if ((status != 0)); then exit "$status"; fi
done

python3 - "$output/build-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
data["ui_tests_executed"] = True
data["ui_test_scope"] = "nTV sidebar/Library, real-addon Home/Movies/Detail/manual Sources/Addon recovery/Series, Addons QR/restart/state persistence"
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf '\n- nTV simulator tests passed: sidebar/Library, real-addon Home/Movies/Detail/manual Sources/Addon recovery/Series and Addons QR/restart/state persistence.\n' >> "$GITHUB_STEP_SUMMARY"
fi
