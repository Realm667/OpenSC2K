"""Verify and run a downloaded RS archive with isolated user data and Dummy audio."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_files(folder):
    checked = 0
    listed = set()
    for line in (folder / "SHA256SUMS.txt").read_text().splitlines():
        expected, name = line.split("  ", 1)
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or ":" in name or "\\" in name:
            raise ValueError(f"Unsafe inventory path: {name}")
        if digest(folder / name) != expected:
            raise ValueError(f"Payload hash mismatch: {name}")
        listed.add(name)
        checked += 1
    actual = {path.relative_to(folder).as_posix() for path in folder.rglob("*")
              if path.is_file() and not path.is_symlink() and path.name != "SHA256SUMS.txt"}
    if actual != listed:
        raise ValueError("Unexpected or missing payload files")
    return checked


def check(binary, arguments, env, output):
    result = subprocess.run([str(binary), "--headless", "--audio-driver", "Dummy", *arguments],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    output.write_bytes(result.stdout)
    if result.returncode or b"ERROR:" in result.stdout:
        raise RuntimeError(f"Packaged application failed: {output}\n{result.stdout.decode(errors='replace')[-6000:]}")
    return result.stdout


def smoke(packages, platform, output):
    if platform.startswith("macos"):
        user_data = Path.home() / "Library/Application Support/Godot/app_userdata/OpenSC2K"
        if os.environ.get("GITHUB_ACTIONS") != "true" or user_data.exists():
            raise ValueError("macOS smoke requires a fresh disposable GitHub runner profile")
    output.mkdir(parents=True, exist_ok=False)
    info = json.loads((packages / "build-info.json").read_text())
    suffix = ".dmg" if platform.startswith("macos") else ".zip" if platform.startswith("windows") else ".tar.gz"
    name = f"ReticulatingSplines-{info['label']}-{platform}{suffix}"
    archive = packages / name
    if digest(archive) != info["sha256"][name]:
        raise ValueError("Download hash mismatch")
    with tempfile.TemporaryDirectory(prefix="rs-package-smoke-") as temporary:
        work = Path(temporary)
        env = dict(os.environ)
        profile = work / "profile"
        profile.mkdir()
        for variable in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            env[variable] = str(profile)
        mount = None
        try:
            if platform.startswith("macos"):
                mount = work / "mounted"
                subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(archive)], check=True)
                count = verify_files(mount)
                app = work / "ReticulatingSplines.app"
                subprocess.run(["ditto", str(mount / app.name), str(app)], check=True)
                subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
                metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                binary = app / "Contents/MacOS" / metadata["CFBundleExecutable"]
                subprocess.run(["lipo", "-verify_arch", "x86_64", "arm64", str(binary)], check=True)
            else:
                unpacked = work / "unpacked"
                unpacked.mkdir()
                if suffix == ".zip":
                    with zipfile.ZipFile(archive) as bundle:
                        if bundle.testzip() is not None:
                            raise ValueError("Invalid ZIP")
                        bundle.extractall(unpacked)
                else:
                    with tarfile.open(archive) as bundle:
                        bundle.extractall(unpacked, filter="data")
                folder = unpacked / name.removesuffix(suffix)
                count = verify_files(folder)
                extension = ".exe" if platform.startswith("windows") else ".arm64" if platform.endswith("arm64") else ".x86_64"
                binary = folder / ("ReticulatingSplines" + extension)
            check(binary, ["--quit-after", "180"], env, output / "startup.log")
            probe = Path(__file__).with_name("rs_package_probe.gd").resolve()
            result = check(binary, ["--script", str(probe)], env, output / "packs.log")
            if b"PASS: exported application" not in result:
                raise ValueError("Package probe did not complete")
            (output / "verification.json").write_text(json.dumps(dict(result="PASS", platform=platform,
                host=sys.platform, commit=info['commit'], version=info['version'], archive=name,
                sha256=digest(archive), files_verified=count, startup="PASS", replacement_packs="PASS"), indent=2) + "\n")
        finally:
            if mount is not None and mount.exists():
                subprocess.run(["hdiutil", "detach", str(mount)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages", type=Path, required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    smoke(args.packages.resolve(), args.platform, args.output.resolve())
