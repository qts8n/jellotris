"""Archive checks use small fake runtimes; they do not execute foreign binaries."""

import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

from tools import build


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="jellotris-package-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "dist"
        self.package = build.build_love(build.ROOT, self.output, "0.2.0")

    def test_love_contains_only_runtime_files_and_is_reproducible(self):
        original = self.package.read_bytes()
        with zipfile.ZipFile(self.package) as archive:
            names = set(archive.namelist())
            self.assertIn("main.lua", names)
            self.assertIn("jellotris/rock.lua", names)
            self.assertIn("assets/rock.glsl", names)
            self.assertIn("assets/title.glsl", names)
            self.assertIn("assets/icon.png", names)
            self.assertTrue(all(name.startswith(("assets/", "jellotris/")) or name in {"main.lua", "conf.lua"}
                                for name in names))
            self.assertIsNone(archive.testzip())
        build.build_love(build.ROOT, self.output, "0.2.0")
        self.assertEqual(original, self.package.read_bytes())

    def test_windows_fuses_game_and_keeps_runtime_dependencies(self):
        runtime = self.root / "windows-runtime"
        runtime.mkdir()
        for name, data in {"love.exe": b"MZfake-runtime", "lovec.exe": b"unused-console",
                           "love.dll": b"engine", "SDL2.dll": b"sdl", "license.txt": b"runtime-license"}.items():
            (runtime / name).write_bytes(data)
        result = build.build_windows(build.ROOT, self.output, self.package, "0.2.0", runtime)
        prefix = "jellotris-0.2.0-windows/"
        with zipfile.ZipFile(result) as archive:
            self.assertEqual(archive.read(prefix + "Jellotris.exe"), b"MZfake-runtime" + self.package.read_bytes())
            self.assertEqual(archive.read(prefix + "license.txt"), b"runtime-license")
            self.assertIn(prefix + "SDL2.dll", archive.namelist())
            self.assertIn(prefix + "Jellotris.ico", archive.namelist())
            self.assertNotIn(prefix + "love.exe", archive.namelist())
        self.assertEqual((runtime / "love.exe").read_bytes(), b"MZfake-runtime")

    def test_macos_updates_metadata_and_preserves_framework_symlinks(self):
        runtime = self.root / "love.app"
        contents = runtime / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS" / "love").write_bytes(b"fake-mach-o")
        (contents / "MacOS" / "love").chmod(0o755)
        info = {"CFBundleExecutable": "love", "CFBundleIdentifier": "org.love2d.love",
                "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "org.love2d.love-game"}],
                "CFBundleDocumentTypes": [{"CFBundleTypeName": "LÖVE"}]}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        framework = contents / "Frameworks" / "Test.framework"
        (framework / "Versions" / "A").mkdir(parents=True)
        (framework / "Versions" / "A" / "Test").write_bytes(b"test-framework")
        try:
            (framework / "Test").symlink_to("Versions/A/Test")
        except OSError:
            self.skipTest("This host does not permit creating symlinks")
        result = build.build_macos(build.ROOT, self.output, self.package, "0.2.0", runtime, "org.jellotris.game")
        prefix = "jellotris-0.2.0-macos/Jellotris.app/Contents/"
        with zipfile.ZipFile(result) as archive:
            metadata = plistlib.loads(archive.read(prefix + "Info.plist"))
            self.assertEqual(metadata["CFBundleName"], "Jellotris")
            self.assertEqual(metadata["CFBundleIconFile"], "Jellotris.icns")
            self.assertNotIn("UTExportedTypeDeclarations", metadata)
            self.assertNotIn("CFBundleDocumentTypes", metadata)
            self.assertEqual(archive.read(prefix + "Resources/jellotris.love"), self.package.read_bytes())
            link = archive.getinfo(prefix + "Frameworks/Test.framework/Test")
            self.assertTrue(stat.S_ISLNK(link.external_attr >> 16))
            self.assertEqual(archive.read(link), b"Versions/A/Test")
            self.assertTrue(archive.getinfo(prefix + "MacOS/love").external_attr >> 16 & stat.S_IXUSR)
        self.assertEqual(plistlib.loads((contents / "Info.plist").read_bytes()), info)

    def test_linux_archive_has_a_working_relative_launcher(self):
        result = build.build_linux(build.ROOT, self.output, self.package, "0.2.0")
        prefix = "jellotris-0.2.0-linux/"
        with tarfile.open(result) as archive:
            self.assertTrue(archive.getmember(prefix + "jellotris").mode & stat.S_IXUSR)
            self.assertEqual(archive.extractfile(prefix + "jellotris.love").read(), self.package.read_bytes())
        if os.name == "nt":
            return
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_love = fake_bin / "love"
        fake_love.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        fake_love.chmod(0o755)
        folder = self.output / "jellotris-0.2.0-linux"
        moved = self.root / "moved game with spaces"
        folder.rename(moved)
        result = subprocess.run([str(moved / "jellotris"), "--smoke"], cwd=self.root,
                                env={**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]},
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.splitlines(), [str(moved / "jellotris.love"), "--smoke"])

    @unittest.skipIf(os.name == "nt", "Linux bundles require Unix symlinks")
    def test_linux_optional_runtime_is_fused_and_license_preserved(self):
        runtime = self.root / "squashfs-root"
        (runtime / "bin").mkdir(parents=True)
        (runtime / "bin" / "love").write_bytes(b"fake-elf")
        (runtime / "license.txt").write_text("keep this license")
        (runtime / "AppRun").symlink_to("bin/love")
        result = build.build_linux(build.ROOT, self.output, self.package, "0.2.0", runtime)
        prefix = "jellotris-0.2.0-linux/"
        with tarfile.open(result) as archive:
            self.assertEqual(archive.extractfile(prefix + "bin/jellotris").read(), b"fake-elf" + self.package.read_bytes())
            self.assertEqual(archive.getmember(prefix + "AppRun").linkname, "jellotris")
            self.assertIn(prefix + "license.txt", archive.getnames())

    def test_packaging_cannot_delete_its_input_runtime(self):
        runtime = self.output / "jellotris-0.2.0-windows" / "original-runtime"
        runtime.mkdir(parents=True)
        for name in ("love.exe", "love.dll", "license.txt"):
            (runtime / name).write_bytes(b"original")
        with self.assertRaisesRegex(ValueError, "outside"):
            build.build_windows(build.ROOT, self.output, self.package, "0.2.0", runtime)
        self.assertEqual((runtime / "love.exe").read_bytes(), b"original")

    def test_native_icon_containers_have_valid_png_payloads(self):
        png_header = b"\x89PNG\r\n\x1a\n"
        ico = (build.ROOT / "assets" / "icon.ico").read_bytes()
        reserved, kind, count = struct.unpack_from("<HHH", ico)
        self.assertEqual((reserved, kind, count), (0, 1, 7))
        for index in range(count):
            width, height, _, _, _, bits, size, offset = struct.unpack_from("<BBBBHHII", ico, 6 + index * 16)
            payload = ico[offset:offset + size]
            self.assertEqual(payload[:8], png_header)
            self.assertEqual(bits, 32)
            self.assertEqual(struct.unpack_from(">II", payload, 16), (width or 256, height or 256))
        icns = (build.ROOT / "assets" / "icon.icns").read_bytes()
        self.assertEqual(icns[:4], b"icns")
        self.assertEqual(struct.unpack_from(">I", icns, 4)[0], len(icns))
        offset = 8
        for tag in (b"ic07", b"ic08", b"ic09", b"ic10"):
            self.assertEqual(icns[offset:offset + 4], tag)
            size = struct.unpack_from(">I", icns, offset + 4)[0]
            self.assertEqual(icns[offset + 8:offset + 16], png_header)
            offset += size
        self.assertEqual(offset, len(icns))


if __name__ == "__main__":
    unittest.main()
