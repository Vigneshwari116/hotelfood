#!/usr/bin/env python3
"""Copy the canonical client menu seed to each location template filename."""

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/templates/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx"
OUT_DIR = ROOT / "assets/templates/locations"

LOCATIONS = [
    "Gt world mall",
    "Magadi road",
    "Subbanna garden",
]


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(
            f"Missing client seed file: {SOURCE}\n"
            "Place Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx there unchanged."
        )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in LOCATIONS:
        target = OUT_DIR / f"{name}.xlsx"
        shutil.copy2(SOURCE, target)
        print(f"Wrote {target}")


if __name__ == "__main__":
    main()
