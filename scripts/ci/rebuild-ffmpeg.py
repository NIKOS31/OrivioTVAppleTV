#!/usr/bin/env python3
"""Replace the pinned wrapper's tvOS core archives with signed FFmpeg 6.1.6.

Other FFmpegKit libraries and the patched KSPlayer remain unchanged. Each
configure check links real target libraries; pkg-config cannot use host packages.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/ci/ffmpeg"
PIN = "c32be9bfb628042737ad3ef622e930c5c7b15954"
CORE = ["avcodec", "avdevice", "avfilter", "avformat", "avutil", "swresample", "swscale"]
SOURCE_SHA = "d4fcb164028dd3beee5d92c0ac72e46aac6973c75ea12dc14de07bf8f407370a"
HEADERS_SHA = "717b49c52dbd37c78cf2f7f0fc715292c42e74841219e6cca918cd293ad5dce4"


def run(args, **kwargs):
    print("+ " + shlex.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def capture(args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def unpack(archive):
    with tarfile.open(archive) as handle:
        names = {member.name.split("/")[0] for member in handle.getmembers()}
        if len(names) != 1:
            raise RuntimeError("Expected one source root")
        # Reject links and traversal before extracting these verified source trees.
        for member in handle.getmembers():
            target = (OUT / member.name).resolve()
            if not target.is_relative_to(OUT.resolve()) or member.issym() or member.islnk():
                raise RuntimeError("Unsafe source archive member")
        handle.extractall(OUT, filter="data")
    return OUT / names.pop()


def slice_path(name, simulator, arch):
    root = CHECKOUT / "Sources" / (name + ".xcframework")
    info = plistlib.loads((root / "Info.plist").read_bytes())
    rows = [row for row in info["AvailableLibraries"] if row["SupportedPlatform"] == "tvos"
            and (row.get("SupportedPlatformVariant") == "simulator") == simulator
            and arch in row["SupportedArchitectures"]]
    if len(rows) != 1:
        raise RuntimeError("Expected one target slice for " + name)
    row = rows[0]
    return root, info, row, root / row["LibraryIdentifier"] / row["LibraryPath"]


def copy_headers(source, destination):
    # SwiftPM protects its checkout; do not propagate read-only modes into
    # the merged build include tree or silently choose conflicting headers.
    destination.mkdir(parents=True, exist_ok=True)
    for entry in source.rglob("*"):
        target = destination / entry.relative_to(source)
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif entry.is_file():
            data = entry.read_bytes()
            if target.exists():
                if target.read_bytes() != data:
                    raise RuntimeError("Conflicting dependency header: " + str(target))
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)


def writable(path):
    path.chmod(path.stat().st_mode | 0o200)


def dependencies(simulator, arch, directory, sdk):
    include, lib, pc = (directory / name for name in ("include", "lib", "pkgconfig"))
    for path in (include, lib, pc):
        path.mkdir(parents=True, exist_ok=True)
    versions = {
        "libdav1d": ("dav1d", "1.1.0"), "gnutls": ("gnutls", "3.8.3"),
        "lcms2": ("lcms2", "2.16"), "libplacebo": ("libplacebo", "6.338.2"),
        "libshaderc_combined": ("shaderc", "2024.0"),
        "libsmbclient": ("smbclient", "4.15.13"), "libsrt": ("srt", "1.5.3"),
        "libzvbi": ("zvbi-0.2", "0.2.42"),
    }
    # Names that upstream flattened while packaging frameworks need their
    # original include prefix restored for C's configure/build checks.
    prefixes = {"gnutls": "gnutls", "nettle": "nettle", "libplacebo": "libplacebo"}
    targets = ["gmp", "nettle", "hogweed", "gnutls", "libdav1d", "lcms2",
               "libplacebo", "libshaderc_combined", "libsmbclient", "libsrt", "libzvbi", "MoltenVK"]
    library_names = []
    for name in targets:
        _, _, _, path = slice_path(name, simulator, arch)
        if path.suffix == ".framework":
            binary = path / name
            headers = path / "Headers"
            copy_headers(headers, include / prefixes.get(name, ""))
        else:
            binary = path
        basename = name[3:] if name.startswith("lib") else name
        link = lib / ("lib" + basename + ".a")
        if not link.exists():
            link.symlink_to(binary)
        library_names.append("-l" + basename)
    copy_headers(VULKAN / "include", include)
    common = " ".join(library_names + ["-lc++", "-liconv", "-lresolv", "-lz", "-lbz2",
                "-framework Security", "-framework CoreFoundation", "-framework Foundation",
                "-framework Metal", "-framework QuartzCore", "-framework IOSurface",
                "-framework CoreGraphics", "-framework CoreVideo"])
    for name, (pkg, version) in versions.items():
        (pc / (pkg + ".pc")).write_text(
            f"Name: {pkg}\nDescription: Pinned FFmpegKit target archive\nVersion: {version}\n"
            f"Cflags: -I{include} -I{include}/samba-4.0\nLibs: -L{lib} {common}\n", encoding="utf-8")
    (pc / "vulkan.pc").write_text(
        f"Name: vulkan\nDescription: Khronos headers only\nVersion: 1.3.280\nCflags: -I{include}\nLibs:\n", encoding="utf-8")
    # libxml2 is the platform SDK's library, never the runner's Homebrew copy.
    (pc / "libxml-2.0.pc").write_text(
        f"Name: libxml2\nDescription: Apple SDK\nVersion: 2.9.0\n"
        f"Cflags: -I{sdk}/usr/include/libxml2\nLibs: -lxml2\n", encoding="utf-8")
    return include, lib, pc


def baseline_config(simulator, arch):
    _, _, _, framework = slice_path("Libavutil", simulator, arch)
    strings = re.findall(rb"[\x20-\x7e]{16,}", (framework / "Libavutil").read_bytes())
    candidates = [line.decode("ascii") for line in strings if b"--enable-cross-compile" in line]
    if not candidates:
        raise RuntimeError("Original FFmpeg configure record missing")
    options = shlex.split(candidates[0])
    omitted = ("--prefix=", "--arch=", "--target-os=")
    options = [option for option in options if not option.startswith(omitted)
               and option not in ("--enable-neon", "--disable-neon", "--enable-asm", "--disable-asm", "--disable-avdevice")]
    old_header = (framework / "Headers/config.h").read_text()
    return options, old_header


def rebuild(simulator, arch):
    label = "simulator" if simulator else "device"
    directory = OUT / label
    directory.mkdir(exist_ok=True)
    sdk_name = "appletvsimulator" if simulator else "appletvos"
    sdk = capture(["xcrun", "--sdk", sdk_name, "--show-sdk-path"])
    compiler = capture(["xcrun", "--sdk", sdk_name, "--find", "clang"])
    target = f"{arch}-apple-tvos17.0" + ("-simulator" if simulator else "")
    include, lib, pc = dependencies(simulator, arch, directory / "deps", sdk)
    options, old_config = baseline_config(simulator, arch)
    (directory / "baseline-options.json").write_text(json.dumps(options, indent=2) + "\n")
    build = directory / "objects"
    build.mkdir(exist_ok=True)
    prefix = directory / "installed"
    flags = shlex.join(["-target", target, "-isysroot", sdk, "-Os", "-I" + str(include)])
    ldflags = flags + " -L" + str(lib)
    args = [SOURCE / "configure", *options, "--disable-autodetect", "--enable-avdevice",
            "--prefix=" + str(prefix), "--arch=" + ("aarch64" if arch == "arm64" else "x86_64"),
            "--target-os=darwin", "--cc=" + compiler, "--cxx=" + compiler + "++",
            "--as=" + compiler, "--extra-cflags=" + flags, "--extra-cxxflags=" + flags,
            "--extra-ldflags=" + ldflags, "--pkg-config=" + shutil.which("pkg-config")]
    args += ["--enable-neon", "--enable-asm"] if arch == "arm64" else ["--disable-neon", "--disable-asm"]
    env = dict(os.environ, PKG_CONFIG_LIBDIR=str(pc), PKG_CONFIG_PATH="", SDKROOT=sdk)
    run(args, cwd=build, env=env)
    new_config = (build / "config.h").read_text()
    # Mandatory capabilities of the previous actual tvOS binary must survive.
    capabilities = ["VIDEOTOOLBOX", "AUDIOTOOLBOX", "GNUTLS", "GMP", "LIBDAV1D",
                    "LIBPLACEBO", "LIBSHADERC", "LIBSMBCLIENT", "LIBSRT", "LIBZVBI", "LIBXML2", "VULKAN"]
    for name in capabilities:
        define = "#define CONFIG_" + name + " 1"
        if define in old_config and define not in new_config:
            raise RuntimeError("Lost original FFmpeg capability: " + name)
    run(["make", "-j", str(os.cpu_count() or 3)], cwd=build, env=env)
    run(["make", "install"], cwd=build, env=env)
    records = {}
    extra = {"avutil": ["getenv_utf8", "libm", "thread", "intmath", "mem_internal", "attributes_internal", "internal"],
             "avcodec": ["mathops"], "avformat": ["os_support"]}
    for name in CORE:
        module = "Lib" + name
        root, info, row, framework = slice_path(module, simulator, arch)
        archive = prefix / "lib" / ("lib" + name + ".a")
        if not archive.is_file():
            raise RuntimeError("Missing rebuilt " + module)
        # All paths are resolved from the pinned checkout and a fixed module list.
        if not framework.resolve().is_relative_to(CHECKOUT):
            raise RuntimeError("Framework destination escaped checkout")
        for parent in [framework, *framework.parents]:
            if parent.is_relative_to(CHECKOUT):
                writable(parent)
        headers = framework / "Headers"
        for child in [headers, *headers.rglob("*")]:
            if child.is_dir():
                writable(child)
        shutil.rmtree(headers)
        copy_headers(prefix / "include" / ("lib" + name), headers)
        for header in extra.get(name, []):
            shutil.copyfile(SOURCE / ("lib" + name) / (header + ".h"), headers / (header + ".h"))
        if name in ("avutil", "avcodec", "avformat"):
            shutil.copyfile(build / "config.h", headers / "config.h")
        if name == "avutil":
            internal = headers / "internal.h"
            internal.write_text(internal.read_text().replace('#include "timer.h"', '// timer.h is private to the FFmpeg build.'))
        for header in headers.glob("*.h"):
            text = header.read_text()
            for other in CORE:
                text = re.sub(r'#\s*include\s+["<]lib' + other + r'/([^">]+)[">]',
                              r'#include <Lib' + other + r'/\1>', text)
            header.write_text(text)
        writable(framework / module)
        shutil.copyfile(archive, framework / module)
        row["SupportedArchitectures"] = [arch]
        writable(root / "Info.plist")
        (root / "Info.plist").write_bytes(plistlib.dumps(info))
        fw_info = plistlib.loads((framework / "Info.plist").read_bytes())
        fw_info.update(CFBundleShortVersionString="6.1.6", CFBundleVersion="6.1.6", MinimumOSVersion="17.0")
        writable(framework / "Info.plist")
        (framework / "Info.plist").write_bytes(plistlib.dumps(fw_info))
        run(["xcrun", "lipo", framework / module, "-verify_arch", arch])
        records[module] = hashlib.sha256(archive.read_bytes()).hexdigest()
    return {"target": target, "capabilities_preserved": capabilities, "archives_sha256": records}


if __name__ == "__main__":
    if platform.system() != "Darwin":
        raise SystemExit("Use macOS/Xcode for tvOS archives")
    checkouts = ROOT / "build/ci/DerivedData/SourcePackages/checkouts"
    matches = [path for path in checkouts.iterdir() if path.name.lower() == "ffmpegkit"]
    if len(matches) != 1:
        raise SystemExit("Expected the resolved FFmpegKit checkout")
    CHECKOUT = matches[0].resolve()
    if capture(["git", "-C", CHECKOUT, "rev-parse", "HEAD"]) != PIN:
        raise SystemExit("Unexpected FFmpegKit revision")
    for path, expected in ((Path(sys.argv[1]), SOURCE_SHA), (Path(sys.argv[2]), HEADERS_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit("Unverified source archive")
    signature = (OUT / "signature-status.txt").read_text()
    if "[GNUPG:] VALIDSIG FCF986EA15E6E293A5644F10B4322F04D67658D8 " not in signature:
        raise SystemExit("Expected the verified FFmpeg release signature")
    SOURCE = unpack(Path(sys.argv[1]))
    VULKAN = unpack(Path(sys.argv[2]))
    # Same Apple Metal compatibility correction as the pinned upstream builder.
    vt = SOURCE / "libavcodec/videotoolbox.c"
    vt.write_text(vt.read_text().replace("kCVPixelBufferOpenGLESCompatibilityKey", "kCVPixelBufferMetalCompatibilityKey")
                  .replace("kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey", "kCVPixelBufferMetalCompatibilityKey"))
    host_arch = platform.machine()
    if host_arch not in ("arm64", "x86_64"):
        raise SystemExit("Unsupported simulator host architecture")
    record = {"version": "6.1.6", "source_sha256": hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest(),
              "release_signature_verified": True, "wrapper_revision": PIN,
              "slices": [rebuild(False, "arm64"), rebuild(True, host_arch)]}
    (OUT / "provenance.json").write_text(json.dumps(record, indent=2) + "\n")
    license_dir = ROOT / "OrivioTV/Resources/FFmpegLicenses"
    license_dir.mkdir(exist_ok=True)
    for name in ("COPYING.GPLv3", "COPYING.LGPLv3", "LICENSE.md"):
        shutil.copyfile(SOURCE / name, license_dir / name)
    shutil.copyfile(OUT / "provenance.json", license_dir / "ntv-ffmpeg-build.json")
