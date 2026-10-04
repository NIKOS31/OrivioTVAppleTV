#!/usr/bin/env bash
set -euo pipefail

task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
output="$task_root/build/ci"
app="$output/DerivedData/Build/Products/Release-appletvos/OrivioTV.app"
package_dir="$output/packages"

if [[ $(uname -s) != Darwin || ! -d "$app" ]]; then
  echo 'Package the successful Release Apple TV build on macOS.' >&2
  exit 1
fi

# Never package simulator output or publish an untested checkout.
python3 - "$app/Info.plist" "$output/build-info.json" <<'PY'
import json
import plistlib
import subprocess
import sys

with open(sys.argv[1], "rb") as handle:
    info = plistlib.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    build = json.load(handle)
head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
if info.get("CFBundleDisplayName") != "nTV":
    raise SystemExit("Unexpected app display name.")
if info.get("CFBundleSupportedPlatforms") != ["AppleTVOS"] or 3 not in info.get("UIDeviceFamily", []):
    raise SystemExit("Expected a device tvOS app, never simulator output.")
if build.get("commit") != head or build.get("ui_tests_executed") is not True:
    raise SystemExit("This checkout has no successful nTV UI-test record.")
PY

executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
xcrun lipo -verify_arch arm64 "$app/$executable"
mkdir -p "$package_dir"
stage=$(mktemp -d "$output/ipa-stage.XXXXXX")
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/OrivioTV.app"
# ditto preserves the framework permissions and symbolic links in the bundle.
ditto -c -k --keepParent "$stage/Payload" "$package_dir/nTV-unsigned.ipa"

python3 - "$package_dir" "$output/build-info.json" <<'PY'
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
    "personal_addons_configured": False,
    "ui_tests_executed": build["ui_tests_executed"],
}
(directory / "nTV-unsigned.ipa.sha256").write_text(checksum + "  " + ipa.name + "\n", encoding="utf-8")
(directory / "package-info.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps(record, indent=2))
PY

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf '\n- nTV unsigned device IPA packaged after successful UI tests. Sign it locally before installing on an Apple TV.\n' >> "$GITHUB_STEP_SUMMARY"
fi
