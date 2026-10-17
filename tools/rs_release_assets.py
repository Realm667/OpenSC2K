"""Allowlisted replacement packs and public notices for Reticulating Splines releases."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil


def destination(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or ":" in name or "\\" in name:
        raise ValueError(f"Unsafe source path: {name}")
    prefix = "packs/standalone-graphics/graphics/"
    if name.startswith(prefix) and (path.suffix == ".png" or path.name in ("pack.json", "LICENSE-STATUS.txt")):
        return "graphic/reticulating-splines/" + name.removeprefix(prefix)
    for source, target, extension in (("music", "music", ".mp3"), ("sound", "sounds", ".wav")):
        prefix = f"packs/standalone-audio/{source}/"
        if name.startswith(prefix) and (path.suffix == extension or path.name == "pack.json"):
            return f"{target}/reticulating-splines/" + name.removeprefix(prefix)
    return None


def verify_manifest(path):
    def walk(value):
        if isinstance(value, dict):
            for item in value.values():
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, str) and PurePosixPath(value).suffix.lower() in (".png", ".mp3", ".wav"):
            relative = PurePosixPath(value)
            if relative.is_absolute() or ".." in relative.parts or ":" in value or "\\" in value:
                raise ValueError(f"Unsafe manifest reference: {value}")
            if not (path.parent / value).is_file():
                raise ValueError(f"Missing manifest asset: {path}: {value}")
    walk(json.loads(path.read_text(encoding="utf-8-sig")))


def install(source, folder, platform, source_zip):
    macos = platform.startswith("macos")
    public = folder / "ReticulatingSplines.app/Contents/Resources" if macos else folder
    data = public / "bundled-packs" if macos else public / "data"
    for path in sorted((source / "packs").rglob("*")):
        if not path.is_file():
            continue
        target = destination(path.relative_to(source).as_posix())
        if target:
            if path.is_symlink():
                raise ValueError(f"Linked pack input: {path}")
            out = data / target
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, out)
    for kind in ("graphic", "music", "sounds"):
        verify_manifest(data / kind / "reticulating-splines/pack.json")
    licenses = public / "licenses"
    for path in (source / "game/assets/licenses").rglob("*.txt"):
        out = licenses / path.relative_to(source / "game/assets/licenses")
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)
    for path in (source / "game/assets/fonts").rglob("OFL.txt"):
        out = licenses / "fonts" / path.relative_to(source / "game/assets/fonts")
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)
    notices = licenses / "reticulating-splines"
    notices.mkdir(parents=True, exist_ok=True)
    provenance = json.loads((source / "packs/standalone-graphics/provenance.json").read_text(encoding="utf-8-sig"))
    (notices / "graphics-provenance.json").write_text(json.dumps({key: provenance[key] for key in ("scope", "generation", "references", "license")}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(source / "packs/standalone-audio/provenance.json", notices / "audio-provenance.json")
    shutil.copy2(source / "packs/standalone-audio/README.txt", notices / "audio-notices.txt")
    shutil.copy2(source / "LICENSE", public / "LICENSE.txt")
    shutil.copy2(source_zip, public / "FluidSynth-corresponding-source.zip")
    text = (source / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
    (public / "THIRD_PARTY_NOTICES.md").write_text(text.replace("OpenSC2K-<version>-fluidsynth-source.zip", "FluidSynth-corresponding-source.zip"), encoding="utf-8")
    if macos:
        (folder / "THIRD_PARTY_NOTICES.md").write_text(text.replace("OpenSC2K-<version>-fluidsynth-source.zip", "ReticulatingSplines.app/Contents/Resources/FluidSynth-corresponding-source.zip"), encoding="utf-8")
    instructions = ("Drag ReticulatingSplines.app into Applications. Your cities and settings are stored in your user profile.\n"
                    "This preview is ad-hoc signed unless build-info.json confirms notarization. macOS may require explicit approval in Privacy & Security.\n"
                    if macos else "Extract the entire archive to a writable folder and run ReticulatingSplines. Your cities and settings are stored in data/.\n")
    instructions += "Use the included replacement graphics, music and sounds. Importing your own supported SimCity 2000 installation is optional. No original game files or personal data are included.\nSee LICENSE.txt, THIRD_PARTY_NOTICES.md and licenses/ for terms.\n"
    (folder / "INSTALL.md").write_text("# Reticulating Splines\n\n" + instructions, encoding="utf-8")
    if macos:
        shutil.copy2(folder / "INSTALL.md", public / "INSTALL.md")


def inventory(folder):
    hashes = {}
    for path in sorted(folder.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                hashes[path.relative_to(folder).as_posix()] = hashlib.file_digest(stream, "sha256").hexdigest()
    (folder / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()), encoding="utf-8")
    return hashes
