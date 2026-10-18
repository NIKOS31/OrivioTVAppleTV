#!/usr/bin/env bash
set -euo pipefail

validation=ui-tested
case ${1:-} in
  '') ;;
  --device-test) validation=device-test ;;
  *) echo 'Use no argument for validated packages, or --device-test for manual Apple TV testing.' >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || exit 1

task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
output="$task_root/build/ci"
app="$output/DerivedData/Build/Products/Release-appletvos/OrivioTV.app"
package_dir="$output/packages"

if [[ $(uname -s) != Darwin || ! -d "$app" ]]; then
  echo 'Package the successful Release Apple TV build on macOS.' >&2
  exit 1
fi

# Manual device tests keep their untested status; normal releases still require successful UI tests.
python3 scripts/ci/verify-ntv-icon-assets.py "$app/Info.plist" "$app/Assets.car"
python3 - "$app/Info.plist" "$output/build-info.json" "$validation" <<'PY'
import json
import plistlib
import subprocess
import sys

with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    build = json.load(handle)
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
if info.get("CFBundleDisplayName") != "nTV" or info.get("CFBundleName") != "nTV":
    raise SystemExit("Unexpected app display name.")
if info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon") != "NTVPrimaryIconV2":
    raise SystemExit("The system must reference the dedicated nTV icon, including the app switcher.")
if info.get("CFBundleSupportedPlatforms") != ["AppleTVOS"] or 3 not in info.get("UIDeviceFamily", []):
    raise SystemExit("Expected a device tvOS app, never simulator output.")
if build.get("commit") != head:
    raise SystemExit("The build must match this exact checkout.")
if sys.argv[3] != "device-test" and build.get("ui_tests_executed") is not True:
    raise SystemExit("This checkout has no successful nTV UI-test record.")
PY

executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
xcrun lipo "$app/$executable" -verify_arch arm64
mkdir -p "$package_dir"
stage=$(mktemp -d "$output/ipa-stage.XXXXXX")
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/OrivioTV.app"
# Preserve a device package without shared-container requests for recovery if
# the viewer's local signing service cannot provision the requested group.
ditto -c -k --keepParent "$stage/Payload" "$package_dir/nTV-standalone.ipa"

# CODE_SIGNING_ALLOWED=NO leaves no Mach-O entitlement carrier. The local
# signer's capability request is based on those embedded entitlements, not on
# source .entitlements files or Info.plist. An ad-hoc signature conveys only
# the existing common group request; an Apple account/device signature remains
# required. Never insert an Apple identity, profile, token or certificate in CI.
carrier="$stage/Payload/OrivioTV.app"
for framework in "$carrier"/Frameworks/*.framework "$carrier"/Frameworks/*.dylib; do
  [[ -e "$framework" ]] || continue
  codesign --force --sign - "$framework"
done
for extension in "$carrier"/PlugIns/*.appex; do
  [[ -d "$extension" ]] || continue
  codesign --force --sign - --entitlements OrivioTopShelf/OrivioTopShelf.entitlements "$extension"
done
codesign --force --sign - --entitlements Config/OrivioTV.entitlements "$carrier"
codesign --verify --deep --strict "$carrier"
codesign -d --entitlements :- "$carrier" > "$output/app-carrier-entitlements.plist" 2>/dev/null
extension=$(find "$carrier/PlugIns" -maxdepth 1 -type d -name '*.appex')
[[ -n "$extension" && "$extension" != *$'\n'* ]]
codesign -d --entitlements :- "$extension" > "$output/shelf-carrier-entitlements.plist" 2>/dev/null
python3 - "$output/app-carrier-entitlements.plist" "$output/shelf-carrier-entitlements.plist" <<'PY'
import plistlib, sys
groups=[]
for path in sys.argv[1:]:
    with open(path, 'rb') as f:
        groups.append(plistlib.load(f).get('com.apple.security.application-groups', []))
if not groups[0] or groups[0] != groups[1]:
    raise SystemExit('The app and extension must carry the identical local-sharing request.')
print('Ad-hoc capability carrier verified; personal Apple signature still required.')
PY
# ditto preserves the framework permissions and symbolic links in the bundle.
ditto -c -k --keepParent "$stage/Payload" "$package_dir/nTV-unsigned.ipa"

python3 - "$package_dir" "$output/build-info.json" "$validation" <<'PY'
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import zipfile

directory = Path(sys.argv[1])
ipa = directory / "nTV-unsigned.ipa"
with zipfile.ZipFile(ipa) as archive:
    root = "Payload/OrivioTV.app/"
    info = plistlib.loads(archive.read(root + "Info.plist"))
    if archive.testzip() is not None or root + info["CFBundleExecutable"] not in archive.namelist():
        raise SystemExit("Invalid IPA payload.")
with ipa.open("rb") as handle:
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
checksum = digest.hexdigest()
with open(sys.argv[2], encoding="utf-8") as handle:
    build = json.load(handle)
record = {
    "file": ipa.name,
    "sha256": checksum,
    "bytes": ipa.stat().st_size,
    "commit": build["commit"],
    "display_name": info["CFBundleDisplayName"],
    "bundle_identifier": info["CFBundleIdentifier"],
    "version": info["CFBundleShortVersionString"],
    "build": info["CFBundleVersion"],
    "minimum_tvos": info.get("MinimumOSVersion"),
    "supported_platforms": info["CFBundleSupportedPlatforms"],
    "signature_required": True,
    "capability_carrier": "ad-hoc",
    "local_sharing_entitlement_requested": True,
    "personal_addons_configured": False,
    "ui_tests_executed": build["ui_tests_executed"],
    "validation": sys.argv[3],
    "ffmpeg": build["ffmpeg"],
}
(directory / "nTV-unsigned.ipa.sha256").write_text(checksum + "  " + ipa.name + "\n", encoding="utf-8")
(directory / "package-info.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
standalone = directory / "nTV-standalone.ipa"
fallback = dict(record, file=standalone.name, bytes=standalone.stat().st_size,
    sha256=hashlib.sha256(standalone.read_bytes()).hexdigest(), capability_carrier="none",
    local_sharing_entitlement_requested=False)
(directory / "package-info-standalone.json").write_text(json.dumps(fallback, indent=2) + "\n", encoding="utf-8")
print(json.dumps(record, indent=2))
PY

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf '\n- nTV unsigned device IPA packaged (%s). Sign it locally before installing on an Apple TV.\n' "$validation" >> "$GITHUB_STEP_SUMMARY"
fi
