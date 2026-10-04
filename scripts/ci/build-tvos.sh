#!/usr/bin/env bash
set -euo pipefail

task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"

if [[ $(uname -s) != Darwin ]]; then
  echo 'tvOS builds require macOS and Xcode. Use the tvOS baseline GitHub workflow.' >&2
  exit 1
fi
for tool in git python3 xcodebuild xcodegen xcrun; do
  command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done

output="$task_root/build/ci"
derived_data="$output/DerivedData"
lockfile='OrivioTV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
results="$output/results/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$output/logs" "$results"
cp "$lockfile" "$output/Package.resolved.baseline"

# CI uses the checked-in template, never repository/account credentials.
# Generate after this copy so XcodeGen includes the ignored Secrets.swift.
if [[ ! -f OrivioTV/Secrets.swift ]]; then
  cp Secrets.example.swift OrivioTV/Secrets.swift
fi
xcodebuild -version | tee "$output/logs/xcode.log"
if ! xcrun metal --version 2>&1 | tee "$output/logs/metal.log"; then
  xcodebuild -downloadComponent MetalToolchain 2>&1 | tee "$output/logs/metal-download.log"
  xcrun metal --version 2>&1 | tee "$output/logs/metal.log"
fi
xcodegen generate --spec project.yml 2>&1 | tee "$output/logs/generate.log"

# XcodeGen may rewrite project metadata; keep the upstream dependency lock.
if [[ ! -f "$lockfile" ]]; then
  mkdir -p "$(dirname "$lockfile")"
  cp "$output/Package.resolved.baseline" "$lockfile"
fi
xcodebuild -resolvePackageDependencies \
  -project OrivioTV.xcodeproj -scheme OrivioTV \
  -derivedDataPath "$derived_data" \
  -onlyUsePackageVersionsFromResolvedFile \
  2>&1 | tee "$output/logs/resolve.log"

# Ignore lockfile schema/format changes, but reject changed dependency pins.
python3 - "$output/Package.resolved.baseline" "$lockfile" <<'PY'
import json
import sys

def pins(filename):
    with open(filename, encoding="utf-8") as handle:
        data = json.load(handle)
    return sorted(data["pins"], key=lambda pin: pin["identity"])

if pins(sys.argv[1]) != pins(sys.argv[2]):
    raise SystemExit("Dependency pins changed during resolution; update the lock explicitly.")
print("Upstream dependency pins preserved.")
PY

# Leave SourcePackages inside DerivedData: upstream's vendor sanitization
# pre-build script locates the framework checkouts relative to BUILD_DIR.
xcodebuild build \
  -project OrivioTV.xcodeproj -scheme OrivioTV \
  -configuration Release -sdk appletvos \
  -destination 'generic/platform=tvOS' \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$results/device.xcresult" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  2>&1 | tee "$output/logs/device.log"

xcodebuild build \
  -project OrivioTV.xcodeproj -scheme OrivioTV \
  -configuration Debug -sdk appletvsimulator \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$results/simulator.xcresult" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
  2>&1 | tee "$output/logs/simulator.log"

python3 - "$output/build-info.json" <<'PY'
import json
import subprocess
import sys

data = {
    "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "xcodegen": subprocess.check_output(["xcodegen", "--version"], text=True).strip(),
    "builds": {"device": "Release", "simulator": "Debug"},
    "code_signing": False,
    "ui_tests_executed": False,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<'SUMMARY'
### tvOS baseline

- Release device and Debug simulator builds succeeded.
- Upstream dependency pins were preserved; signing was disabled.
- Optional integration keys were left blank in the CI checkout.
- The nTV simulator test is reported separately; physical Apple TV playback/focus tests were not executed.
- Logs and Xcode result bundles are available in the diagnostics artifact.

SUMMARY
fi
