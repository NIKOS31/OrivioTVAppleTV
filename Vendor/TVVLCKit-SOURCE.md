# TVVLCKit for nTV

The fallback engine uses the official VideoLAN tvOS binary distribution dated
2026-09-30, containing libVLC **3.0.24 Vetinari**. Both device and simulator
slices are checked during preparation. The previous SwiftPM wrapper shipped
libVLC 3.0.21, affected by VideoLAN security bulletins 3022 and 3024.

Before generating the Xcode project, run:

```sh
bash scripts/ci/prepare-tvvlckit.sh
xcodegen generate --spec project.yml
```

CI performs these steps automatically. The downloaded xcframework is ignored
by Git; the source URL and SHA-256 checksum are pinned in the preparation script.
No Apple account is needed to download or verify it.

Distribution: https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz

SHA-256: `07892cae8e59e95a23f1fcf11692f802eae106312aa5ad9782faa2556b2d65d5`

Upstream source and license: https://code.videolan.org/videolan/VLCKit
and https://code.videolan.org/videolan/vlc

Security bulletin: https://www.videolan.org/security/sb-vlc3024.html
The unchanged upstream license is provided in `TVVLCKit-COPYING.txt`.
