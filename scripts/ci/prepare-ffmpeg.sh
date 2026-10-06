#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$task_root"
[[ $(uname -s) == Darwin ]] || { echo 'FFmpeg tvOS requires Xcode on macOS.' >&2; exit 1; }
command -v pkg-config >/dev/null || brew install pkgconf
command -v gpg >/dev/null || brew install gnupg
output="$task_root/build/ci/ffmpeg"
mkdir -p "$output/downloads" "$output/keyring"
chmod 700 "$output/keyring"
archive="$output/downloads/ffmpeg-6.1.6.tar.xz"
curl --fail --location --retry 3 https://ffmpeg.org/releases/ffmpeg-6.1.6.tar.xz --output "$archive"
printf '%s  %s\n' d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a "$archive" | shasum -a 256 --check
curl --fail --location --retry 3 https://ffmpeg.org/releases/ffmpeg-6.1.6.tar.xz.asc --output "$archive.asc"
gpg --batch --homedir "$output/keyring" --import Config/ffmpeg-release-key.asc
gpg --batch --homedir "$output/keyring" --status-fd 1 --verify "$archive.asc" "$archive" > "$output/signature-status.txt"
grep -q '^\[GNUPG:\] VALIDSIG FCF986EA15E6E293A5644F10B4322F04D67658D8 ' "$output/signature-status.txt"
headers="$output/downloads/vulkan-headers-1.3.280.tar.gz"
curl --fail --location --retry 3 https://codeload.github.com/KhronosGroup/Vulkan-Headers/tar.gz/refs/tags/v1.3.280 --output "$headers"
printf '%s  %s\n' 717b49c52dbd37c78cf2f7f0fc715292c42e74841219e6cca918cd293ad5dce4 "$headers" | shasum -a 256 --check
python3 scripts/ci/rebuild-ffmpeg.py "$archive" "$headers"
