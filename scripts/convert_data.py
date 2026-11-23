#!/usr/bin/env python3
"""
Convert RAMA air quality Excel files to per-year JSON for web visualization.

Reads every YYYY<Pollutant>.xls in 04RAMA/ and writes one JSON per year to
data/air_quality_YYYY.json, plus data/years.json listing the available years.

Station names and coordinates come from the official SEDEMA catalog vendored in
scripts/cat_estacion.csv (downloaded from
https://aire.cdmx.gob.mx/descargas/Opendata/catalogos/cat_estacion.csv).
Each year only includes the stations that actually report that year, because the
RAMA station roster changes over time.
"""

import csv
import json
import re
from pathlib import Path

import pandas as pd

CATALOG_FILE = Path(__file__).parent / "cat_estacion.csv"
FILE_RE = re.compile(r"^(\d{4})([A-Za-z0-9]+)\.xls$")

# Pollutants the program sonifies. RAMA also publishes PM10 and PMCO (PM10-2.5);
# PM2.5 is the fraction used to track long-term deterioration, so the coarser
# particles are left out of the pipeline.
POLLUTANT_INFO = {
    "CO": {"name": "Monóxido de Carbono", "unit": "ppm"},
    "NO": {"name": "Óxido Nítrico", "unit": "ppb"},
    "NO2": {"name": "Dióxido de Nitrógeno", "unit": "ppb"},
    "NOX": {"name": "Óxidos de Nitrógeno", "unit": "ppb"},
    "O3": {"name": "Ozono", "unit": "ppb"},
    "PM25": {"name": "Material Particulado 2.5μm", "unit": "μg/m³"},
    "SO2": {"name": "Dióxido de Azufre", "unit": "ppb"},
}

# Centro geográfico de la zona metropolitana. Cada estación se asigna a uno de
# los cuatro puntos cardinales según el eje que domina respecto a este punto,
# de modo que cada estación cae en exactamente una zona y una zona ocupa una
# bocina del arreglo cuadrafónico.
ZONE_CENTER = {"lat": 19.4326, "lon": -99.1332}
ZONE_NAMES = ("Norte", "Sur", "Este", "Oeste")


def zone_for(lat: float, lon: float) -> str:
    """Cuadrante cardinal de una estación respecto a ZONE_CENTER."""
    dlat = lat - ZONE_CENTER["lat"]
    dlon = lon - ZONE_CENTER["lon"]
    if abs(dlat) >= abs(dlon):
        return "Norte" if dlat >= 0 else "Sur"
    return "Este" if dlon >= 0 else "Oeste"


def load_catalog() -> dict:
    """Read the official station catalog (one row per station code)."""
    with open(CATALOG_FILE, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    catalog = {}
    for row in rows:
        code = (row["cve_estac"] or "").strip()
        if not code:
            continue
        alt = (row["alt"] or "").strip()
        lat = round(float(row["latitud"]), 6)
        lon = round(float(row["longitud"]), 6)
        catalog[code] = {
            "name": row["nom_estac"].strip(),
            "lat": lat,
            "lon": lon,
            "altitude": int(alt) if alt.isdigit() else None,
            "zone": zone_for(lat, lon),
            "note": (row["obs_estac"] or "").strip(),
        }
    return catalog


def read_pollutant_file(filepath: Path) -> pd.DataFrame:
    """Read a RAMA Excel file and return a cleaned DataFrame."""
    df = pd.read_excel(filepath, engine="xlrd")

    df.columns = [str(c).strip().upper() for c in df.columns]

    # Replace -99 with None (missing data)
    numeric_cols = df.columns[2:]  # Skip FECHA, HORA
    df[numeric_cols] = df[numeric_cols].replace(-99, None)

    # Convert date to proper format
    df["FECHA"] = pd.to_datetime(df["FECHA"], format="%d/%m/%Y", errors="coerce")
    df = df[df["FECHA"].notna()]

    return df


def extract_daily_data(df: pd.DataFrame) -> tuple[dict, set]:
    """Promedio diario por estación: date -> station -> promedio (o None).

    La app ya no recorre las horas: la línea de tiempo avanza por día, semana o
    año, así que basta con el promedio del día. Los datos por hora siguen
    disponibles en 04RAMA/ y se pueden regenerar.
    """
    stations = [col for col in df.columns if col not in ("FECHA", "HORA")]
    acc: dict[str, dict[str, list]] = {}
    used = set()

    for _, row in df.iterrows():
        date_key = row["FECHA"].strftime("%Y-%m-%d")
        hour = int(row["HORA"]) - 1  # Convert to 0-indexed
        if not 0 <= hour < 24:
            continue

        day = acc.setdefault(date_key, {s: [0.0, 0] for s in stations})
        for station in stations:
            value = row[station]
            if pd.notna(value):
                day[station][0] += float(value)
                day[station][1] += 1
                used.add(station)

    data = {
        date: {
            station: (round(total / count, 2) if count else None)
            for station, (total, count) in day.items()
        }
        for date, day in acc.items()
    }
    return data, used


def main():
    script_dir = Path(__file__).parent
    data_dir = script_dir.parent / "04RAMA"
    output_dir = script_dir.parent / "data"
    output_dir.mkdir(exist_ok=True)

    catalog = load_catalog()

    # Group input files by year: {2004: {"O3": path, ...}, ...}
    by_year: dict[int, dict[str, Path]] = {}
    for filepath in sorted(data_dir.glob("*.xls")):
        match = FILE_RE.match(filepath.name)
        if not match:
            continue
        year, pollutant = int(match.group(1)), match.group(2).upper()
        if pollutant not in POLLUTANT_INFO:
            continue
        by_year.setdefault(year, {})[pollutant] = filepath

    if not by_year:
        print(f"No RAMA Excel files found in {data_dir}")
        return

    unknown = set()
    written = []
    all_dates = []  # todas las fechas, para la línea de tiempo de 2004 a 2024

    for year in sorted(by_year):
        year_data: dict[str, dict] = {}
        stations_used: set[str] = set()

        for pollutant, filepath in sorted(by_year[year].items()):
            print(f"{year} {pollutant}...")
            df = read_pollutant_file(filepath)
            pollutant_data, used = extract_daily_data(df)
            stations_used |= used
            for date_key, stations_dict in pollutant_data.items():
                year_data.setdefault(date_key, {})[pollutant] = stations_dict

        unknown |= stations_used - set(catalog)
        stations_used &= set(catalog)

        output = {
            "metadata": {
                "year": year,
                "description": f"Calidad del aire CDMX - RAMA {year}",
                "stations_count": len(stations_used),
                "pollutants": sorted(by_year[year]),
                "missing_value": None,
                "hours_per_day": 24,
                "aggregation": "promedio diario",
            },
            "stations": {code: catalog[code] for code in sorted(stations_used)},
            "pollutant_info": POLLUTANT_INFO,
            "data": year_data,
        }

        output_file = output_dir / f"air_quality_{year}.json"
        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, separators=(",", ":"))

        written.append((year, len(stations_used), len(year_data), output_file.stat().st_size))
        all_dates.extend(year_data)
        zones = {}
        for code in stations_used:
            zones.setdefault(catalog[code]["zone"], []).append(code)
        print(f"  -> {output_file.name}: {len(year_data)} días, {len(stations_used)} estaciones, "
              f"zonas {', '.join(f'{z}:{len(zones.get(z, []))}' for z in ZONE_NAMES)}")

    # Índice de años, leído por el mapa para armar el selector
    with open(output_dir / "years.json", "w", encoding="utf-8") as f:
        json.dump({"years": sorted(by_year)}, f)

    print("\nYears written:")
    for year, stations, days, size in written:
        print(f"  {year}: {stations:2d} estaciones, {days:3d} días, {size / 1024:6.0f} KB")
    print(f"\nTotal: {len(written)} años -> {output_dir}")

    if unknown:
        print(f"\nAdvertencia: estaciones sin coordenadas en el catálogo (se omiten): {' '.join(sorted(unknown))}")


if __name__ == "__main__":
    main()
