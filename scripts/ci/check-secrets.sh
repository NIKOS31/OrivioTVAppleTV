#!/bin/bash
set -euo pipefail

# No third-party action token or remote scan service. Verify the official CLI
# archive before executing it. Reports stay outside the public artifact paths.
version=8.30.1
case "$(uname -m)" in
  arm64) archive_name="gitleaks_${version}_darwin_arm64.tar.gz"
         expected=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5 ;;
  x86_64) archive_name="gitleaks_${version}_darwin_x64.tar.gz"
          expected=dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709 ;;
  *) echo 'Unsupported secret-scanner architecture.' >&2; exit 1 ;;
esac

tools_dir=$(mktemp -d "${RUNNER_TEMP:?}/ntv-secret-scan.XXXXXX")
archive="$tools_dir/release.tar.gz"
curl --fail --location --retry 3 --max-time 120 \
  "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive_name}" \
  --output "$archive"
printf '%s  %s\n' "$expected" "$archive" | shasum -a 256 --check
tar -xzf "$archive" -C "$tools_dir" gitleaks
chmod +x "$tools_dir/gitleaks"
test "$("$tools_dir/gitleaks" version)" = "$version"

# The baseline contains exact immutable fingerprints of reviewed historical
# findings. It never excludes a whole dependency, path, rule or future commit.
"$tools_dir/gitleaks" git \
  --log-opts='--all' \
  --config .gitleaks.toml \
  --gitleaks-ignore-path .gitleaksignore \
  --ignore-gitleaks-allow \
  --redact=100 --no-banner --no-color --timeout=180 \
  --report-format=json --report-path "$tools_dir/report.json" .
