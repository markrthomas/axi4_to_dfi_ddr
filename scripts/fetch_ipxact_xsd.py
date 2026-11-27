#!/usr/bin/env python3
"""Fetch the IEEE 1685-2014 (IP-XACT) XML schema for offline validation.

Kit template (templates/signoff/pkg/). Adopt into scripts/ with the pin file.

Usage:  scripts/fetch_ipxact_xsd.py <out-dir>
Then:   IPXACT_XSD=<out-dir>/index.xsd make pkg        (or just: make pkg-xsd)

The schema is published by Accellera (IEEE publishes only the standard's text).
Its files are a fixed set, all with relative schemaLocations, so they are stored
byte-for-byte as downloaded. The Accellera notice allows copying "WITHOUT
modifications" only, so nothing is rewritten.

Integrity: every file must match the SHA-256 pinned in
pkg/ip-xact/schema/ieee-1685-2014.sha256 (hash of the content with CRLF
normalised to LF, so a line-ending-only difference between hosts is not a
mismatch).

Sources, tried in order for the whole file set:
  1. http://www.accellera.org/XMLSchema/IPXACT/1685-2014/   (canonical)
  2. https://www.accellera.org/XMLSchema/IPXACT/1685-2014/
  3. https://www.eda.org/XMLSchema/IPXACT/1685-2014/        (Accellera's other host)
  4. https://raw.githubusercontent.com/edaa-org/IPXACT-Schema/<pinned commit>/ieee-1685-2014/
A source that answers with something other than an XML Schema (an HTML page)
or a network error is skipped and the next source is tried. A source that
serves a real schema file whose hash does not match the pin is a HARD FAILURE:
that means the published schema changed or something is tampering, and it
must not be hidden by falling back.

A completed fetch writes <out-dir>/.complete and is reused when every pinned
hash still matches, so CI can cache the directory.

Exit codes: 0 = schema present and verified; 3 = no source served the schema
(nothing validated: the caller must report "not run", never a pass);
1 = hash mismatch (integrity failure); 2 = usage error.
"""
import hashlib
import re
import sys
import time
import urllib.request
from pathlib import Path

import os

# Pins: pkg/ip-xact/schema/ieee-1685-2014.sha256 in the repo (run from the repo root),
# overridable with IPXACT_PINS. Copy the pin file from the kit with this script.
PIN_FILE = Path(os.environ.get("IPXACT_PINS", "pkg/ip-xact/schema/ieee-1685-2014.sha256"))
GITHUB_COMMIT = "3c683290483598378435ff93d38c5354fb9e5514"
SOURCES = [
    "http://www.accellera.org/XMLSchema/IPXACT/1685-2014/",
    "https://www.accellera.org/XMLSchema/IPXACT/1685-2014/",
    "https://www.eda.org/XMLSchema/IPXACT/1685-2014/",
    f"https://raw.githubusercontent.com/edaa-org/IPXACT-Schema/{GITHUB_COMMIT}/ieee-1685-2014/",
]
SCHEMA_RE = re.compile(rb"<(?:xs|xsd):schema\b")
EXIT_OK, EXIT_MISMATCH, EXIT_USAGE, EXIT_UNAVAILABLE = 0, 1, 2, 3


class Unavailable(Exception):
    """The source did not serve an XML Schema (HTML page, HTTP or network error)."""


class Mismatch(Exception):
    """The source served a schema file whose content does not match the pin."""


def norm_hash(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def load_pins() -> dict:
    pins = {}
    for line in PIN_FILE.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            h, name = line.split(None, 1)
            pins[name.strip()] = h
    return pins


def get(url: str, attempts: int = 2) -> bytes:
    last = ""
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ipxact-xsd-fetch"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if SCHEMA_RE.search(data):
                return data
            last = f"not an XML Schema (starts: {data.lstrip()[:40]!r})"
        except Exception as e:  # HTTP error, timeout, DNS, ...
            last = repr(e)
        if i < attempts - 1:
            time.sleep(5)
    raise Unavailable(f"{url}: {last}")


def fetch_from(base: str, pins: dict) -> dict:
    files = {}
    for name in sorted(pins):
        data = get(base + name)
        got = norm_hash(data)
        if got != pins[name]:
            raise Mismatch(f"{base}{name}: sha256 {got} != pinned {pins[name]}")
        files[name] = data
    return files


def cached_ok(out: Path, pins: dict) -> bool:
    if not (out / ".complete").is_file():
        return False
    return all((out / n).is_file() and norm_hash((out / n).read_bytes()) == h for n, h in pins.items())


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return EXIT_USAGE
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    pins = load_pins()

    if cached_ok(out, pins):
        print(f"[XSD] using cached schema in {out}/ ({len(pins)} files, all pinned hashes match)")
        return EXIT_OK

    for base in SOURCES:
        try:
            files = fetch_from(base, pins)
        except Unavailable as e:
            print(f"[XSD] source unavailable, trying the next one: {e}", file=sys.stderr)
            continue
        except Mismatch as e:
            print(f"[XSD] FAIL: integrity: {e}", file=sys.stderr)
            print("[XSD] The served schema differs from the pinned IEEE 1685-2014 files. "
                  "Not falling back: investigate before changing the pins.", file=sys.stderr)
            return EXIT_MISMATCH
        for name, data in files.items():
            (out / name).write_bytes(data)          # stored unmodified
        (out / ".complete").write_text(f"source {base}\n")
        print(f"[XSD] fetched {len(files)} schema files from {base} into {out}/ "
              f"(all match pkg/ip-xact/schema/ieee-1685-2014.sha256)")
        return EXIT_OK

    print("[XSD] no source served the IEEE 1685-2014 schema", file=sys.stderr)
    return EXIT_UNAVAILABLE


if __name__ == "__main__":
    sys.exit(main())
