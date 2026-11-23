#!/usr/bin/env python3
"""
Download the RAMA air quality annual ZIP files (2004-2024) and the station
catalog from SEDEMA, then extract the Excel files into 04RAMA/.

Source: https://aire.cdmx.gob.mx/rama.php
"""

import sys
import urllib.request
import zipfile
from pathlib import Path

BASE_URL = "https://aire.cdmx.gob.mx/descargas/Opendata/Bases_publicas/RAMA/"
CATALOG_URL = "https://aire.cdmx.gob.mx/descargas/Opendata/catalogos/cat_estacion.csv"


def download(url: str, dest: Path) -> None:
    with urllib.request.urlopen(url) as response, open(dest, "wb") as f:
        f.write(response.read())


def main():
    script_dir = Path(__file__).parent
    rama_dir = script_dir.parent / "04RAMA"
    rama_dir.mkdir(exist_ok=True)

    # Station catalog: codes, names and coordinates used by convert_data.py
    catalog_file = script_dir / "cat_estacion.csv"
    print(f"Downloading station catalog -> {catalog_file.name}")
    download(CATALOG_URL, catalog_file)
    # The published file is ISO-8859-1 and starts with a title line; normalize it.
    raw = catalog_file.read_bytes().decode("iso-8859-1")
    lines = raw.splitlines()[1:]  # drop "Catalogo de estaciones,,,,,,"
    catalog_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    for year in range(2004, 2025):
        zip_name = f"{str(year)[-2:]}RAMA.zip"
        zip_path = rama_dir / zip_name

        print(f"{year}: {zip_name}")
        try:
            download(BASE_URL + zip_name, zip_path)
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(rama_dir)
            zip_path.unlink()
        except Exception as e:
            print(f"  failed: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
