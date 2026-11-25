#!/usr/bin/env bash
# Benchmark-only: builds 56, 57 and the 57b diagnostic variant on the same
# runner with the same injected probe, then runs NTVCadenceBenchmark in a
# mirrored order (56 57 57b 57b 57 56) on one simulator.
# Outside the qualification manifest; never packages or publishes an app.
set -euo pipefail

bench_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench_src="$bench_root/bench/cadence"
out="$bench_root/build/bench"
mkdir -p "$out/logs"
commit_of() { case $1 in 56) echo f2382df9d6ec04acbad6a8b2bee65802ca387b26 ;; 57|57b) echo 24e09dc7f3231478add084769e74854811307096 ;; *) exit 2 ;; esac; }

xcrun simctl list devices available --json > "$out/simulators.json"
simulator=$(python3 - "$out/simulators.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1], encoding="utf-8"))["devices"]
for runtime, entries in sorted(devices.items(), reverse=True):
    if ".tvOS-" in runtime:
        for device in entries:
            if device.get("isAvailable"):
                print(device["udid"]); raise SystemExit(0)
raise SystemExit("No available tvOS simulator on this runner.")
PY
)

prepare() {
  local label=$1 tree="$RUNNER_TEMP/ntv-$1"
  git -C "$bench_root" worktree add --detach "$tree" "$(commit_of "$label")"
  [[ $(git -C "$tree" rev-parse HEAD) == "$(commit_of "$label")" ]]
  cp "$bench_src/NTVCadenceProbe.swift" "$tree/OrivioTV/Components/"
  cp "$bench_src/NTVCadenceBenchmark.swift" "$tree/OrivioTVUITests/"
  python3 - "$tree/OrivioTV/OrivioTVApp.swift" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
anchor = "            if perf.settings.showFPSOverlay { FPSOverlay() }\n"
if text.count(anchor) != 1:
    raise SystemExit("Expected exactly one FPS overlay hook.")
hook = "            if NTVCadenceProbe.isRequested { NTVCadenceProbeView().frame(width: 1, height: 1).allowsHitTesting(false) }\n"
open(path, "w", encoding="utf-8").write(text.replace(anchor, anchor + hook))
PY
  if [[ $label == 57* ]]; then
    python3 "$bench_src/patch_container.py" "$tree/OrivioTV/Custom/Screens/NTVNativeCatalogScroll.swift" "$label"
  fi
  git -C "$tree" diff > "$out/logs/injection-$label.diff"
  git -C "$tree" diff --stat > "$out/logs/injection-$label.txt"
  git -C "$tree" status --short >> "$out/logs/injection-$label.txt"
  (
    cd "$tree"
    [[ -f OrivioTV/Secrets.swift ]] || cp Secrets.example.swift OrivioTV/Secrets.swift
    xcrun metal --version >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain
    bash scripts/ci/prepare-tvvlckit.sh
    mkdir -p OrivioTV/Resources/FFmpegLicenses
    xcodegen generate --spec project.yml
    xcodebuild -resolvePackageDependencies -project OrivioTV.xcodeproj -scheme OrivioTV \
      -derivedDataPath "$tree/build/ci/DerivedData" -onlyUsePackageVersionsFromResolvedFile
    bash scripts/ci/prepare-ffmpeg.sh
    xcodebuild build-for-testing "${test_options[@]}" -derivedDataPath "$tree/build/ci/DerivedData" \
      CODE_SIGN_ENTITLEMENTS="$tree/Config/NTV-CI-Simulator.entitlements"
  ) > "$out/logs/build-$label.log" 2>&1
}

test_options=(
  -project OrivioTV.xcodeproj -scheme OrivioTV
  -configuration Debug -sdk appletvsimulator
  -destination "platform=tvOS Simulator,id=$simulator"
  -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 300
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES
)

for label in 56 57 57b; do prepare "$label"; done

xcrun simctl boot "$simulator" || true
xcrun simctl bootstatus "$simulator" -b
open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$simulator"
status=0
round=0
for label in 56 57 57b 57b 57 56; do
  round=$((round + 1))
  tree="$RUNNER_TEMP/ntv-$label"
  result="$out/results/round$round-$label.xcresult"
  mkdir -p "$out/results"
  set +e
  (cd "$tree" && xcodebuild test-without-building "${test_options[@]}" \
    CODE_SIGN_ENTITLEMENTS="$tree/Config/NTV-CI-Simulator.entitlements" \
    -derivedDataPath "$tree/build/ci/DerivedData" -resultBundlePath "$result" \
    -only-testing:OrivioTVUITests/NTVCadenceBenchmark) > "$out/logs/test-round$round-$label.log" 2>&1
  code=$?
  set -e
  ((code == 0)) || status=$code
  xcrun xcresulttool export attachments --path "$result" --output-path "$out/attachments/round$round-$label" \
    > "$out/logs/export-round$round-$label.log" 2>&1 || status=1
done
python3 "$bench_src/summarize.py" "$out" > "$out/summary.json" || status=1
cat "$out/summary.json"
exit "$status"
