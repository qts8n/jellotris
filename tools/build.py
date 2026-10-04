#!/usr/bin/env python3
"""Package Jellotris with Python's standard library and optional official runtimes."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import tarfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.2.0"


def zip_tree(folder, destination):
    """Preserve executable bits and macOS framework symlinks in ZIP archives."""
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob("*")):
            if path.is_dir() and not path.is_symlink():
                continue
            info = zipfile.ZipInfo(path.relative_to(folder.parent).as_posix())
            info.create_system = 3
            info.external_attr = path.lstat().st_mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            data = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
            archive.writestr(info, data)


def build_love(root, output, version):
    """Allowlist runtime files; never ship saves, tests, tools, or editor files."""
    output.mkdir(parents=True, exist_ok=True)
    destination = output / f"jellotris-{version}.love"
    files = [root / "main.lua", root / "conf.lua"]
    files += sorted((root / "jellotris").rglob("*.lua"))
    files += sorted(p for p in (root / "assets").rglob("*") if p.suffix in {".png", ".glsl"})
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            info = zipfile.ZipInfo(path.relative_to(root).as_posix())
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    return destination


def render_icons(root, love):
    sizes = (16, 24, 32, 48, 64, 128, 256)
    renders = root / "build" / "icons"
    renders.mkdir(parents=True, exist_ok=True)
    subprocess.run([love, str(root), "--export-icon"], cwd=root, check=True)
    shutil.copy2(renders / "icon-512.png", root / "assets" / "icon.png")

    # Modern ICO and ICNS containers accept PNG payloads directly.
    payloads = [(size, (renders / f"icon-{size}.png").read_bytes()) for size in sizes]
    offset = 6 + len(payloads) * 16
    headers = bytearray(struct.pack("<HHH", 0, 1, len(payloads)))
    for size, payload in payloads:
        headers.extend(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(payload), offset))
        offset += len(payload)
    (root / "assets" / "icon.ico").write_bytes(headers + b"".join(payload for _, payload in payloads))

    chunks = []
    for tag, size in ((b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)):
        payload = (renders / f"icon-{size}.png").read_bytes()
        chunks.append(tag + struct.pack(">I", len(payload) + 8) + payload)
    content = b"".join(chunks)
    (root / "assets" / "icon.icns").write_bytes(b"icns" + struct.pack(">I", len(content) + 8) + content)
    return root / "assets" / "icon.png"


def fresh_folder(output, name):
    folder = output / name
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    return folder


def check_runtime_location(runtime, destination):
    source, target = runtime.resolve(), destination.resolve()
    if source == target or source in target.parents or target in source.parents:
        raise ValueError("Keep the original runtime outside the generated bundle directory.")


def build_windows(root, output, package, version, runtime, rcedit=None):
    if not (runtime / "love.exe").is_file() or not (runtime / "love.dll").is_file():
        raise ValueError("Windows runtime must be the extracted official ZIP, containing love.exe and love.dll.")
    if not (runtime / "license.txt").is_file():
        raise ValueError("Keep license.txt from the official Windows runtime.")
    check_runtime_location(runtime, output / f"jellotris-{version}-windows")
    folder = fresh_folder(output, f"jellotris-{version}-windows")
    shutil.copytree(runtime, folder, dirs_exist_ok=True, symlinks=True)
    executable = folder / "Jellotris.exe"
    shutil.copy2(folder / "love.exe", executable)
    if rcedit:
        # Change resources BEFORE fusing; resource editors may discard an overlay.
        subprocess.run([str(rcedit), str(executable), "--set-icon", str(root / "assets" / "icon.ico")], check=True)
    with executable.open("ab") as target:
        target.write(package.read_bytes())
    (folder / "love.exe").unlink()
    (folder / "lovec.exe").unlink(missing_ok=True)
    shutil.copy2(root / "assets" / "icon.ico", folder / "Jellotris.ico")
    shutil.copy2(root / "README.md", folder / "README.md")
    archive = output / f"{folder.name}.zip"
    zip_tree(folder, archive)
    return archive


def build_macos(root, output, package, version, runtime, bundle_id):
    info_path = runtime / "Contents" / "Info.plist"
    if not info_path.is_file():
        raise ValueError("macOS runtime must point to the extracted love.app bundle.")
    info = plistlib.loads(info_path.read_bytes())
    executable = runtime / "Contents" / "MacOS" / info.get("CFBundleExecutable", "love")
    if not executable.is_file():
        raise ValueError("The macOS runtime is missing its bundle executable.")
    check_runtime_location(runtime, output / f"jellotris-{version}-macos")
    folder = fresh_folder(output, f"jellotris-{version}-macos")
    app = folder / "Jellotris.app"
    shutil.copytree(runtime, app, symlinks=True)
    resources = app / "Contents" / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copy2(package, resources / "jellotris.love")
    shutil.copy2(root / "assets" / "icon.icns", resources / "Jellotris.icns")
    info.update(CFBundleIdentifier=bundle_id, CFBundleName="Jellotris", CFBundleDisplayName="Jellotris",
                CFBundleVersion=version, CFBundleShortVersionString=version, CFBundleIconFile="Jellotris.icns")
    # The game must not register itself as the handler for every .love archive.
    info.pop("UTExportedTypeDeclarations", None)
    info.pop("CFBundleDocumentTypes", None)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps(info))
    # Editing bundle resources invalidates the original outer resource signature.
    signature = app / "Contents" / "_CodeSignature"
    if signature.exists():
        shutil.rmtree(signature)
    shutil.copy2(root / "README.md", folder / "README.md")
    archive = output / f"{folder.name}.zip"
    zip_tree(folder, archive)
    return archive


def build_linux(root, output, package, version, runtime=None):
    if runtime and not (runtime / "bin" / "love").is_file():
        raise ValueError("Linux runtime must be an extracted official AppImage with bin/love.")
    if runtime:
        check_runtime_location(runtime, output / f"jellotris-{version}-linux")
    folder = fresh_folder(output, f"jellotris-{version}-linux")
    if runtime:
        shutil.copytree(runtime, folder, dirs_exist_ok=True, symlinks=True)
        executable = folder / "bin" / "jellotris"
        executable.write_bytes((runtime / "bin" / "love").read_bytes() + package.read_bytes())
        executable.chmod(0o755)
        command = 'exec "$app_dir/bin/jellotris" "$@"\n'
        app_run = folder / "AppRun"
        if app_run.exists() or app_run.is_symlink():
            app_run.unlink()
        app_run.symlink_to("jellotris")
        (folder / "love.desktop").unlink(missing_ok=True)
    else:
        shutil.copy2(package, folder / "jellotris.love")
        command = ('command -v love >/dev/null 2>&1 || { echo "Install LÖVE 11.5 from https://love2d.org" >&2; exit 1; }\n'
                   'exec love "$app_dir/jellotris.love" "$@"\n')
    launcher = folder / "jellotris"
    launcher.write_text('#!/bin/sh\nset -eu\napp_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\n' + command)
    launcher.chmod(0o755)
    shutil.copy2(root / "assets" / "icon.png", folder / "jellotris.png")
    shutil.copy2(root / "README.md", folder / "README.md")
    (folder / "jellotris.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Jellotris\nComment=Jelly, stone, and falling tetrominoes\n"
        "Exec=jellotris\nIcon=jellotris\nTerminal=false\nCategories=Game;BlocksGame;\n")
    archive = output / f"{folder.name}.tar.gz"
    with tarfile.open(archive, "w:gz", dereference=False) as target:
        target.add(folder, arcname=folder.name)
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("love", "linux", "windows", "macos", "icons", "clean"))
    parser.add_argument("--version", default=VERSION)
    parser.add_argument("--runtime", type=Path, help="Extracted official platform runtime directory")
    parser.add_argument("--rcedit", type=Path, help="Optional native Windows rcedit executable")
    parser.add_argument("--bundle-id", default="org.jellotris.game")
    parser.add_argument("--love", default="love", help="LÖVE executable for regenerating icons")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Version must use the form 0.2.0")
    if args.target in {"windows", "macos"} and not args.runtime:
        parser.error(f"{args.target} needs --runtime pointing to an extracted official LÖVE 11.5 runtime")
    if args.target == "clean":
        for name in ("build", "dist"):
            if (ROOT / name).exists():
                shutil.rmtree(ROOT / name)
        return
    try:
        if args.target == "icons":
            result = render_icons(ROOT, args.love)
        else:
            output = ROOT / "dist"
            package = build_love(ROOT, output, args.version)
            runtime = args.runtime.resolve() if args.runtime else None
            if args.target == "windows":
                result = build_windows(ROOT, output, package, args.version, runtime, args.rcedit)
            elif args.target == "macos":
                result = build_macos(ROOT, output, package, args.version, runtime, args.bundle_id)
            elif args.target == "linux":
                result = build_linux(ROOT, output, package, args.version, runtime)
            else:
                result = package
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Build failed: {error}\n")
    print(result.relative_to(ROOT))


if __name__ == "__main__":
    main()
