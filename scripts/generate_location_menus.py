#!/usr/bin/env python3
"""Build location menu Excel files from the canonical client CSV seed."""

import csv
import shutil
from pathlib import Path

from openpyxl import Workbook

ROOT = Path(__file__).resolve().parents[1]
CSV_SOURCE = ROOT / "assets/templates/shilpa_enterprise_menu_1401.csv"
XLSX_SOURCE = ROOT / "assets/templates/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx"
OUT_DIR = ROOT / "assets/templates/locations"
FIXTURE = ROOT / "test/fixtures/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx"

HEADERS = [
    "category",
    "item_name",
    "sub_item",
    "barcode",
    "qty_per_sale",
    "packets",
    "units_per_packet",
    "unit",
    "opening stock",
    "cost_price",
    "selling_price",
]

LOCATIONS = [
    "Gt world mall",
    "Magadi road",
    "Subbanna garden",
]


def read_csv_rows(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.reader(handle):
            rows.append([(row[i] if i < len(row) else "") for i in range(len(HEADERS))])
    return rows


def write_xlsx(path: Path, rows: list[list[str]]) -> None:
    wb = Workbook()
    ws = wb.active
    for row in rows:
        ws.append([value if value != "" else None for value in row])
    wb.save(path)


def main() -> None:
    if not CSV_SOURCE.is_file():
        raise SystemExit(f"Missing client CSV seed: {CSV_SOURCE}")

    rows = read_csv_rows(CSV_SOURCE)
    if not rows or [cell.strip() for cell in rows[0]] != HEADERS:
        raise SystemExit("Client CSV header row does not match the expected menu format.")

    write_xlsx(XLSX_SOURCE, rows)
    shutil.copy2(XLSX_SOURCE, FIXTURE)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in LOCATIONS:
        target = OUT_DIR / f"{name}.xlsx"
        shutil.copy2(XLSX_SOURCE, target)
        print(f"Wrote {target}")


if __name__ == "__main__":
    main()
