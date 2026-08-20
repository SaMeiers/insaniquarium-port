#!/usr/bin/env python3
"""
Verifica que exista en disco todo lo que properties/resources.xml referencia.

Una copia incompleta del juego no se nota hasta que falla, y algunos casos son
peores que un mensaje de error: si falta una imagen que Board dibuja, el juego
CRASHEA en partida, porque Graphics::DrawImageMirror hace theImage->GetWidth()
sin chequear null.

Respeta <SetDefaults path="..."> , que fija el directorio base de cada grupo, y
distingue <Image> de <Sound> y <Font>: todos usan el atributo path= pero viven
en carpetas distintas y con extensiones distintas.

Tambien detecta desajustes de MAYUSCULAS: en Windows dan igual, en Android no,
y son 65 en la copia de GOG.

Uso:
    verify-assets.py [raiz] [--fix-case]

    --fix-case renombra los archivos a la capitalizacion exacta que pide
    resources.xml. Se usa sobre la copia de assets del APK, nunca sobre los
    archivos originales del juego.
"""
import re
import sys
import pathlib

BIN = pathlib.Path(__file__).resolve().parent / "bin"
FIX_CASE = False

# extensions the loader tries when the path carries none
EXTS = {
    "Image": ["gif", "jpg", "jpeg", "png", "tga"],
    "Sound": ["ogg", "wav", "au", "mp3"],
    "Font":  ["txt"],
}

TAG_RE = re.compile(r'<\s*(SetDefaults|Image|Sound|Font)\b([^>]*)>', re.I)
ATTR_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')


class DirEntries:
    """Nombres reales de un directorio, con indice en minusculas."""

    def __init__(self, names):
        self.names = names
        self.lower_map = {n.lower(): n for n in names}

    def __contains__(self, name):
        return name in self.names


_dir_cache = {}


def listdir_cached(d: pathlib.Path) -> DirEntries:
    key = str(d).lower()
    if key not in _dir_cache:
        try:
            _dir_cache[key] = DirEntries({p.name for p in d.iterdir()})
        except OSError:
            _dir_cache[key] = DirEntries(set())
    return _dir_cache[key]


def main():
    xml = BIN / "properties" / "resources.xml"
    if not xml.is_file():
        print(f"no encuentro {xml}")
        return 1

    text = xml.read_text(encoding="utf-8", errors="replace")

    base = ""          # directorio actual segun SetDefaults
    missing = []
    mismatched = []
    checked = 0

    for m in TAG_RE.finditer(text):
        kind = m.group(1)
        attrs = dict((k.lower(), v) for k, v in ATTR_RE.findall(m.group(2)))

        if kind.lower() == "setdefaults":
            if "path" in attrs:
                base = attrs["path"].replace("\\", "/").strip("/")
            continue

        path = attrs.get("path")
        if not path:
            continue

        kind = kind.capitalize()
        rel = path.replace("\\", "/")
        # a path with its own folder ignores SetDefaults
        full = rel if "/" in rel else (f"{base}/{rel}" if base else rel)

        checked += 1
        candidates = []
        if pathlib.PurePath(full).suffix:
            candidates.append(BIN / full)
        else:
            # Besides the bare name, the loader accepts both SexyAppFramework
            # alpha-image forms: _name and name_. If the base is missing but the
            # alpha is present it uses the alpha as the image (white RGB plus the
            # grey channel as alpha), so any of the three counts.
            d, _, base_name = full.rpartition("/")
            prefix = f"{d}/" if d else ""
            names = [full, f"{prefix}_{base_name}", f"{full}_"]
            for name in names:
                for e in EXTS.get(kind, []):
                    candidates.append(BIN / f"{name}.{e}")

        # is_file() cannot be used here. This runs on Windows, where the
        # filesystem is case-insensitive, so is_file() returns True even when the
        # real name is cased differently -- exactly the case that breaks on
        # Android and Linux. The directory listing has to be compared against.
        exact = None
        case_hit = None
        for c in candidates:
            entries = listdir_cached(c.parent)
            if c.name in entries:
                exact = c
                break
            lower = c.name.lower()
            if case_hit is None and lower in entries.lower_map:
                case_hit = (c.name, entries.lower_map[lower])

        if exact is None:
            if case_hit is not None:
                mismatched.append((full, case_hit[0], case_hit[1], kind))
            else:
                missing.append((kind, full))

    print(f"  {checked} recursos referenciados")

    if mismatched and FIX_CASE:
        # Renamed only to the exact name resources.xml asks for, not blanket
        # lowercased: font .txt files reference their .gif internally with a
        # different case, and renaming too much would break that reference.
        fixed = 0
        companions = 0
        for ref, want, real, kind in mismatched:
            d = (BIN / ref).parent
            try:
                (d / real).rename(d / want)
                fixed += 1
            except OSError as e:
                print(f"    no pude renombrar {real} -> {want}: {e}")
                continue

            # Images have an alpha-channel companion, "_name" or "name_", that
            # resources.xml never mentions: the loader derives it from the main
            # name. Renaming the main file without the companion loses the alpha
            # and the image renders on a black background (alpha-only graphics
            # disappear entirely).
            #
            # Not done for fonts: the .txt references its .gif by name inside the
            # file, and renaming would break that.
            if kind != "Image":
                continue

            real_stem, real_ext = real.rsplit(".", 1) if "." in real else (real, "")
            want_stem, want_ext = want.rsplit(".", 1) if "." in want else (want, "")
            entries = {p.name.lower(): p.name for p in d.iterdir()}
            for old_pat, new_name in (
                (f"_{real_stem}.{real_ext}".lower(), f"_{want_stem}.{want_ext}"),
                (f"{real_stem}_.{real_ext}".lower(), f"{want_stem}_.{want_ext}"),
            ):
                actual = entries.get(old_pat)
                if actual and actual != new_name:
                    try:
                        (d / actual).rename(d / new_name)
                        companions += 1
                    except OSError:
                        pass

        print(f"  {fixed} archivos renombrados a la capitalizacion que pide resources.xml")
        print(f"  {companions} compañeras de canal alpha renombradas para acompañarlos")
        mismatched = []
    elif mismatched:
        print(f"  {len(mismatched)} con MAYUSCULAS distintas (fallan en Android, no en Windows):")
        for ref, want, real, _kind in mismatched:
            print(f"    {ref}: pide '{want}', el archivo es '{real}'")

    if missing:
        for kind, f in missing:
            print(f"  FALTA ({kind}): {f}")
        print(f"  -> {len(missing)} faltante(s). Revisa tu copia del juego:")
        print("     en GOG Galaxy, 'Verificar / reparar archivos instalados'.")
        return 1

    if mismatched:
        return 1

    print("  ok, todos presentes")
    return 0


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        if arg == "--fix-case":
            FIX_CASE = True
        else:
            BIN = pathlib.Path(arg)
    sys.exit(main())
