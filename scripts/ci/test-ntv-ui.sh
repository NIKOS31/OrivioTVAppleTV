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
open -a "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$simulator"
# The runner contains only test fixtures; retain native media startup failures.
xcrun simctl spawn "$simulator" log stream --style compact --level info \
  --predicate 'process == "OrivioTV" AND (eventMessage CONTAINS "[OrivioPlayer]" OR eventMessage CONTAINS "[FocusTrace]" OR subsystem BEGINSWITH "com.apple.coremedia" OR subsystem BEGINSWITH "com.apple.avfoundation")' \
  > "$output/logs/native-media.log" 2>&1 &
media_log_pid=$!
trap 'kill "$media_log_pid" 2>/dev/null || true' EXIT
# Keep the result bundle available for screenshots even when the test fails.
test_options=(
  -project OrivioTV.xcodeproj -scheme OrivioTV \
  -configuration Debug -sdk appletvsimulator \
  -destination "platform=tvOS Simulator,id=$simulator" \
  -derivedDataPath "$output/DerivedData" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS="$task_root/Config/NTV-CI-Simulator.entitlements" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES
)
run_test_bundle() {
  result_bundle="$results/$1.xcresult"
  shift
  xcodebuild test "${test_options[@]}" -resultBundlePath "$result_bundle" "$@" \
    2>&1 | tee -a "$output/logs/ntv-ui.log"
  test_pipeline=("${PIPESTATUS[@]}")
}
set +e
# A native startup failure must surface before the longer remote journeys.
run_test_bundle native-video \
  -only-testing:OrivioTVTests/NTVFFmpegTests/testBundledFixtureStartsInNativePlayer
if ((test_pipeline[0] == 0 && test_pipeline[1] == 0)); then
  # Surface the known remote-navigation regression before the full UI suite.
  run_test_bundle catalog-focus \
    -only-testing:OrivioTVUITests/NTVDesignSmoke/testSeanimeCatalogRapidMovesYieldToNewNavigation \
    -only-testing:OrivioTVUITests/NTVDesignSmoke/testSeanimeCategoriesAndMainRailHaveDistinctRemotePaths \
    -only-testing:OrivioTVUITests/NTVDesignSmoke/testAdvancedSubtitleOptionsStayNearTransportAndRestoreFocus \
    -only-testing:OrivioTVUITests/NTVDesignSmoke/testPlayerTimelineCancelAndCommit
fi
if ((test_pipeline[0] == 0 && test_pipeline[1] == 0)); then
  run_test_bundle navigation \
    -only-testing:OrivioTVUITests/NTVDesignSmoke \
    -only-testing:OrivioTVTests/NTVCoreTests \
    -only-testing:OrivioTVTests/NTVPlayerComfortTests \
    -only-testing:OrivioTVTests/NTVAnimeTests \
    -only-testing:OrivioTVTests/NTVTwitchTests \
    -only-testing:OrivioTVTests/NTVSecurityTests \
    -only-testing:OrivioTVTests/NTVAddonPayloadTests \
    -only-testing:OrivioTVTests/NTVPerformanceTests \
    -only-testing:OrivioTVTests/NTVArtworkTests \
    -only-testing:OrivioTVTests/NTVTopShelfTests \
    -only-testing:OrivioTVTests/NTVFFmpegTests
fi
kill "$media_log_pid" 2>/dev/null || true
wait "$media_log_pid" 2>/dev/null || true
trap - EXIT
set -e
if ((test_pipeline[0] != 0 || test_pipeline[1] != 0)); then
  printf '\n--- Native media and focus diagnostics (last 160 lines) ---\n'
  tail -n 160 "$output/logs/native-media.log"
fi

export_status=0
if [[ -d "$result_bundle" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$result_bundle" \
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

# Record the actual launch overlay, with no demo argument that skips animation.
# This is the simulator app built and tested above; no personal accounts exist here.
preview_app="$output/DerivedData/Build/Products/Debug-appletvsimulator/OrivioTV.app"
preview_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$preview_app/Info.plist")
xcrun simctl install "$simulator" "$preview_app"
xcrun simctl terminate "$simulator" "$preview_bundle" 2>/dev/null || true
xcrun simctl io "$simulator" recordVideo --codec=h264 "$output/screenshots/ntv-launch.mp4" > "$output/logs/launch-recording.log" 2>&1 &
record_pid=$!
trap 'kill -INT "$record_pid" 2>/dev/null || true' EXIT
sleep 1
xcrun simctl launch "$simulator" "$preview_bundle" > "$output/logs/launch-preview.log"
sleep 7
kill -INT "$record_pid"
record_status=0
wait "$record_pid" || record_status=$?
if ((record_status != 0 && record_status != 130)); then exit "$record_status"; fi
trap - EXIT
[[ -s "$output/screenshots/ntv-launch.mp4" ]]

python3 - "$output/build-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
data["ui_tests_executed"] = True
data["ui_test_scope"] = "nTV sidebar/Library, top floating menu, real-addon Home/Movies/Detail/manual Sources/Addon recovery/Series, Addons QR/restart/state persistence, offline profile characters, full-window artwork/width, Twitch QR/follows/search UI with offline fixtures, player timeline cancel/commit and actual launch recording"
data["unit_test_scope"] = "legacy profiles/local avatar persistence/remote sync, TV home exclusion/pagination/stale category, Twitch public OAuth/encoding/identity/Helix/session cancellation/concurrent refresh; security real Keychain/migration/revocation/private scope, Orivio/Stremio account races, stale Stremio pull and positive addon import, stale addon responses, real phone import server/HTTP framing/Origin/Host/capability/expiry/quota, linked media dependency inventory; offline account fixtures"
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf '\n- nTV simulator UI and model tests passed; see build-info.json for scope. Twitch tests use offline fixtures, not a personal Twitch account. Physical Apple TV playback remains a separate check.\n' >> "$GITHUB_STEP_SUMMARY"
fi
