#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
output="$task_root/build/ci/vendor-vlc"
mkdir -p "$output"
archive="$output/TVVLCKit-20260930.tar.xz"
checksum=07892cae8e59e95a23f1fcf11692f802eae106312aa5ad9782faa2556b2d65d5
url=https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "$url" --output "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 --check

# Extract only the framework from this verified archive, never sample code.
# No unverified cache or previously prepared framework is accepted.
python3 - "$archive" "$output" "$task_root/Vendor/TVVLCKit.xcframework" <<'PY'
import pathlib
import shutil
import sys
import tarfile

archive, output, target = map(pathlib.Path, sys.argv[1:])
prefix = 'TVVLCKit-binary/TVVLCKit.xcframework/'
with tarfile.open(archive) as bundle:
    members = [m for m in bundle.getmembers() if m.name.startswith(prefix) and '/dSYMs/' not in m.name]
    for member in members:
        if '..' in pathlib.PurePosixPath(member.name).parts or pathlib.PurePosixPath(member.name).is_absolute():
            raise SystemExit('Unsafe archive path.')
    bundle.extractall(output, members=members, filter='data')
framework = output / 'TVVLCKit-binary/TVVLCKit.xcframework'
for platform in ('tvos-arm64', 'tvos-arm64_x86_64-simulator'):
    binary = framework / platform / 'TVVLCKit.framework/TVVLCKit'
    if b'3.0.24 Vetinari\0' not in binary.read_bytes():
        raise SystemExit('Expected the patched libVLC 3.0.24 in both tvOS slices.')
shutil.copytree(framework, target, dirs_exist_ok=True)
print('Official libVLC 3.0.24 prepared for Apple TV and simulator.')
PY
