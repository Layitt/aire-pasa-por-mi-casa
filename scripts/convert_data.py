#!/usr/bin/env python3
"""
Convert RAMA air quality Excel files to JSON for web visualization.
Reads all pollutant files from 04RAMA/ and outputs a single JSON file.
"""

import os
import json
import pandas as pd
from pathlib import Path

# Approximate coordinates for RAMA monitoring stations in CDMX
# Format: station_code: {name, lat, lon}
STATION_COORDS = {
    "LAG": {"name": "Tlalnepantla", "lat": 19.5447, "lon": -99.2403},
    "TAC": {"name": "Tacuba", "lat": 19.4583, "lon": -99.1983},
    "FAC": {"name": "Ferrería", "lat": 19.4892, "lon": -99.1761},
    "TLA": {"name": "Tláhuac", "lat": 19.2700, "lon": -99.0050},
    "XAL": {"name": "Xalostoc", "lat": 19.5000, "lon": -99.1200},
    "MER": {"name": "Merced", "lat": 19.4269, "lon": -99.1186},
    "PED": {"name": "Pedregal", "lat": 19.3250, "lon": -99.1750},
    "CES": {"name": "Cerro de la Estrella", "lat": 19.3600, "lon": -99.0600},
    "PLA": {"name": "Plateros", "lat": 19.3833, "lon": -99.1500},
    "HAN": {"name": "Hangares", "lat": 19.4333, "lon": -99.0833},
    "UIZ": {"name": "UAM Iztapalapa", "lat": 19.3600, "lon": -99.1100},
    "ARA": {"name": "Aragón", "lat": 19.4667, "lon": -99.1167},
    "IMP": {"name": "Impresora", "lat": 19.4500, "lon": -99.1333},
    "BJU": {"name": "Benito Juárez", "lat": 19.3833, "lon": -99.1500},
    "TAX": {"name": "Taxqueña", "lat": 19.4000, "lon": -99.1333},
    "MIN": {"name": "Minería", "lat": 19.3333, "lon": -99.1833},
    "TLI": {"name": "Tlalnepantla (ALT)", "lat": 19.5333, "lon": -99.2333},
    "ATI": {"name": "Atizapán", "lat": 19.5667, "lon": -99.2333},
    "VIF": {"name": "Villa Francisca", "lat": 19.4167, "lon": -99.1333},
    "SAG": {"name": "San Agustín", "lat": 19.4000, "lon": -99.1667},
    "VAL": {"name": "Vallejo", "lat": 19.4833, "lon": -99.1500},
    "AZC": {"name": "Azcapotzalco", "lat": 19.4833, "lon": -99.1833},
    "SUR": {"name": "Sur", "lat": 19.3000, "lon": -99.1500},
}

# Pollutant display names and units
POLLUTANT_INFO = {
    "CO": {"name": "Monóxido de Carbono", "unit": "ppm"},
    "NO": {"name": "Óxido Nítrico", "unit": "ppb"},
    "NO2": {"name": "Dióxido de Nitrógeno", "unit": "ppb"},
    "NOX": {"name": "Óxidos de Nitrógeno", "unit": "ppb"},
    "O3": {"name": "Ozono", "unit": "ppb"},
    "PM10": {"name": "Material Particulado 10μm", "unit": "μg/m³"},
    "PM25": {"name": "Material Particulado 2.5μm", "unit": "μg/m³"},
    "SO2": {"name": "Dióxido de Azufre", "unit": "ppb"},
}


def read_pollutant_file(filepath: Path) -> pd.DataFrame:
    """Read a RAMA Excel file and return a cleaned DataFrame."""
    df = pd.read_excel(filepath, engine="xlrd")

    # Replace -99 with None (missing data)
    numeric_cols = df.columns[2:]  # Skip FECHA, HORA
    df[numeric_cols] = df[numeric_cols].replace(-99, None)

    # Convert date to proper format
    df["FECHA"] = pd.to_datetime(df["FECHA"], format="%d/%m/%Y")

    return df


def extract_hours_data(df: pd.DataFrame) -> dict:
    """Convert DataFrame to nested dict: date -> station -> [24 values]."""
    data = {}
    stations = [col for col in df.columns if col not in ["FECHA", "HORA"]]

    for _, row in df.iterrows():
        date_key = row["FECHA"].strftime("%Y-%m-%d")
        hour = int(row["HORA"]) - 1  # Convert to 0-indexed

        if date_key not in data:
            data[date_key] = {s: [None] * 24 for s in stations}

        for station in stations:
            value = row[station]
            if pd.notna(value):
                data[date_key][station][hour] = float(value)

    return data


def main():
    script_dir = Path(__file__).parent
    data_dir = script_dir.parent / "04RAMA"
    output_dir = script_dir.parent / "data"
    output_dir.mkdir(exist_ok=True)

    # Find all Excel files
    excel_files = sorted(data_dir.glob("2004*.xls"))

    if not excel_files:
        print(f"No Excel files found in {data_dir}")
        return

    print(f"Found {len(excel_files)} pollutant files")

    # Process each pollutant
    all_data = {}
    for filepath in excel_files:
        pollutant = filepath.stem.replace("2004", "")
        print(f"Processing {pollutant}...")
        df = read_pollutant_file(filepath)
        all_data[pollutant] = extract_hours_data(df)

    # Build output structure
    output = {
        "metadata": {
            "year": 2004,
            "description": "Calidad del aire CDMX - RAMA 2004",
            "stations_count": len(STATION_COORDS),
            "pollutants": list(POLLUTANT_INFO.keys()),
            "missing_value": None,
            "hours_per_day": 24,
        },
        "stations": STATION_COORDS,
        "pollutant_info": POLLUTANT_INFO,
        "data": {},
    }

    # Merge all pollutant data by date
    dates = set()
    for pollutant_data in all_data.values():
        dates.update(pollutant_data.keys())

    for date in sorted(dates):
        output["data"][date] = {}
        for pollutant in all_data:
            if date in all_data[pollutant]:
                output["data"][date][pollutant] = all_data[pollutant][date]

    # Write JSON
    output_file = output_dir / "air_quality_2004.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=None)

    print(f"\nDone! Output: {output_file}")
    print(f"Total dates: {len(dates)}")
    print(f"File size: {output_file.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
