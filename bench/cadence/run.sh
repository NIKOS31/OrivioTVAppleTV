#!/usr/bin/env bash
# Benchmark-only: builds 56, 57 and the 57c diagnostic variant on the same
# runner with the same injected probe, then runs NTVCadenceBenchmark in a
# mirrored order (56 57 57c 57c 57 56) on one simulator, then records Time
# Profiler traces of the app's main thread during sustained remote presses.
# Outside the qualification manifest; never packages or publishes an app.
set -euo pipefail

bench_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench_src="$bench_root/bench/cadence"
out="$bench_root/build/bench"
mkdir -p "$out/logs"
# full: builds 56 57 57c, cadence rounds, then profiles. profile: builds 56 57, profiles only.
mode=${BENCH_MODE:-full}
[[ $mode == full || $mode == profile ]]
commit_of() { case $1 in 56) echo f2382df9d6ec04acbad6a8b2bee65802ca387b26 ;; 57|57b|57c) echo 24e09dc7f3231478add084769e74854811307096 ;; *) exit 2 ;; esac; }

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
  if [[ $label == 57c ]]; then
    # Diagnostic only: poster cells gated by == again, callbacks behind a stable box.
    git -C "$tree" apply --whitespace=nowarn "$bench_src/57c-equatable-poster-cells.diff"
  fi
  if [[ $label == 57* ]]; then
    python3 "$bench_src/patch_container.py" "$tree/OrivioTV/Custom/Screens/NTVNativeCatalogScroll.swift" "${label/57c/57}"
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

if [[ $mode == full ]]; then labels="56 57 57c"; rounds="56 57 57c 57c 57 56"; else labels="56 57"; rounds=""; fi
for label in $labels; do prepare "$label"; done

crash_marker="$RUNNER_TEMP/bench-start"; touch "$crash_marker"
xcrun simctl boot "$simulator" || true
xcrun simctl bootstatus "$simulator" -b
open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$simulator"
status=0
round=0
for label in $rounds; do
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
if [[ $mode == full ]]; then
  python3 "$bench_src/summarize.py" "$out" > "$out/summary.json" || status=1
fi

# Profiles: best effort, never change the cadence status. `sample` (macOS)
# records the app's process 55 s to 91 s after it appears: in run
# 45831603069 the sustained presses ran from 50-56 s to 93-99 s after launch
# in all five tests. xctrace never started recording a simulator app there.
mkdir -p "$out/profiles" "$out/results"
# Run 45802547277: xctrace never returned once the app ended (orphan at the job limit).
# Interrupt after a deadline so the tool writes what it has, then kill it.
bounded() {
  local seconds=$1 cmd i; shift
  # Background jobs of a script start with SIGINT ignored; restore it so the
  # interrupt reaches the command and it can write its output.
  "${python:-python3}" -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' "$@" & cmd=$!
  for i in $(seq 1 "$seconds"); do kill -0 "$cmd" 2>/dev/null || { wait "$cmd"; return $?; }; sleep 1; done
  echo "bounded: interrupt after ${seconds}s: $1 $2" >&2
  kill -INT "$cmd" 2>/dev/null || true
  for i in $(seq 1 60); do kill -0 "$cmd" 2>/dev/null || { wait "$cmd" || true; return 124; }; sleep 1; done
  echo "bounded: kill: $1 $2" >&2
  kill -KILL "$cmd" 2>/dev/null || true; wait "$cmd" 2>/dev/null || true; return 124
}

profile() {
  local label=$1 test=$2 tree="$RUNNER_TEMP/ntv-$1" name="$1-$2" pid="" i
  local raw="$out/profiles/$name.sample.txt" app_pattern='/OrivioTV[.]app/OrivioTV( |$)' before candidate
  before=$(pgrep -f "$app_pattern" | tr '\n' ' ' || true)
  (cd "$tree" && TEST_RUNNER_NTV_PROFILE=1 xcodebuild test-without-building "${test_options[@]}" \
    CODE_SIGN_ENTITLEMENTS="$tree/Config/NTV-CI-Simulator.entitlements" \
    -derivedDataPath "$tree/build/ci/DerivedData" -resultBundlePath "$out/results/profile-$name.xcresult" \
    -only-testing:"OrivioTVUITests/NTVCadenceBenchmark/$test") > "$out/logs/profile-test-$name.log" 2>&1 &
  local xcode=$!
  # A new process only: the command line carries the launch arguments after the path.
  for i in $(seq 1 240); do
    for candidate in $(pgrep -f "$app_pattern" || true); do
      [[ " $before " == *" $candidate "* ]] || { pid=$candidate; break; }
    done
    [[ -n $pid ]] && break
    sleep 0.5
  done
  if [[ -z $pid ]]; then
    echo "no app process" > "$out/logs/profile-record-$name.log"; wait "$xcode" || true; return 0
  fi
  sleep 55
  # Simulator apps are host processes; sudo when available so task_for_pid is not refused.
  local sampler=(sample)
  sudo -n true 2>/dev/null && sampler=(sudo -n sample)
  bounded 80 "${sampler[@]}" "$pid" 36 1 -mayDie -file "$raw" > "$out/logs/profile-record-$name.log" 2>&1 \
    || echo "sample exit $?" >> "$out/logs/profile-record-$name.log"
  wait "$xcode" || echo "profile test exit $?" >> "$out/logs/profile-record-$name.log"
  [[ -s $raw ]] || return 0
  python3 "$bench_src/profile.py" "$raw" "$label" "$test" \
    > "$out/profiles/$name.json" 2> "$out/logs/profile-parse-$name.log" || true
}
for spec in 57:testProfileFilmsVertical 56:testProfileFilmsVertical 57:testProfileHomeVertical \
            56:testProfileHomeVertical 57:testProfileFilmsHorizontal; do
  profile "${spec%%:*}" "${spec#*:}" || true
done
# Crash reports written during the bench (app or test runner), to explain an
# unexpected exit. Fixture app only; no profile or viewing data.
mkdir -p "$out/logs/crash"
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 2 -type f -newer "$crash_marker" \
  \( -name 'OrivioTV*' -o -name 'OrivioTVUITests*' \) -exec cp {} "$out/logs/crash/" \; 2>/dev/null || true
ls -l "$out/logs/crash" || true
if [[ $mode == profile ]]; then
  ls "$out"/profiles/*.json >/dev/null 2>&1 || { echo "No profile was produced."; status=1; }
else
  cat "$out/summary.json"
fi
exit "$status"
