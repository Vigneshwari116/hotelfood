#!/usr/bin/env python3
"""Convert Shilpa Enterprise menu PDFs into location Excel import files."""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

import pdfplumber
from openpyxl import Workbook

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/templates/locations"
MASTER_XLSX = ROOT / "assets/templates/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx"
FIXTURE_XLSX = ROOT / "test/fixtures/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx"
CSV_SEED = ROOT / "assets/templates/shilpa_enterprise_menu_1401.csv"

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

CATEGORY_ORDER = {
    "SAUCES": 0,
    "OTHERS": 1,
    "SNACKS": 2,
    "FRIED ITEMS": 3,
    "BURGERS": 4,
    "ROLLS": 5,
}


def _col(words: list[dict], x0: float, x1: float) -> str:
    return " ".join(
        w["text"]
        for w in sorted(words, key=lambda item: item["x0"])
        if x0 <= w["x0"] < x1
    ).strip()


def _group_words_by_y(words: list[dict], min_y: float = 70) -> dict[float, list[dict]]:
    by_y: dict[float, list[dict]] = {}
    for word in words:
        y = round(word["top"], 0)
        if y < min_y:
            continue
        by_y.setdefault(y, []).append(word)
    return by_y


def _parse_page1(page) -> list[dict[str, str | float]]:
    by_y = _group_words_by_y(page.extract_words())

    rows: list[dict[str, str | float]] = []
    for y in sorted(by_y.keys()):
        ws = by_y[y]
        row = {
            "y": y,
            "category": _col(ws, 0, 120),
            "item_name": _col(ws, 120, 230),
            "sub_item": _col(ws, 230, 340),
            "barcode": _col(ws, 340, 410),
            "qty_per_sale": _col(ws, 410, 520),
        }
        if any(str(value).strip() for key, value in row.items() if key != "y"):
            rows.append(row)
    return rows


def _parse_page2_row(words: list[dict]) -> dict[str, str]:
    packets = ""
    units_per_packet = ""
    unit = ""
    opening_stock = ""
    cost_price = ""
    selling_price = ""

    for word in sorted(words, key=lambda item: item["x0"]):
        x = word["x0"]
        text = word["text"]
        if x < 130:
            packets = text
        elif x < 195:
            units_per_packet = text
        elif x < 265:
            unit = text
        elif x < 410:
            opening_stock = text
        elif x < 468:
            cost_price = text
        else:
            selling_price = text

    # Some PDF rows omit the selling_price column; the value lands in opening stock.
    if selling_price == "" and opening_stock.isdigit() and unit in {"g", "pc"}:
        selling_price = opening_stock
        opening_stock = "0"

    return {
        "packets": packets,
        "units_per_packet": units_per_packet,
        "unit": unit,
        "opening stock": opening_stock,
        "cost_price": cost_price,
        "selling_price": selling_price,
    }


def _parse_page2(page) -> dict[float, dict[str, str]]:
    by_y = _group_words_by_y(page.extract_words())
    rows: dict[float, dict[str, str]] = {}
    for y, words in by_y.items():
        row = _parse_page2_row(words)
        if any(row.values()):
            rows[y] = row
    return rows


def _normalize_category(category: str) -> str:
    cleaned = re.sub(r"\s+", " ", category.strip().upper())
    if cleaned == "FRIED ITEM":
        return "FRIED ITEMS"
    return cleaned


PAGE2_OVERRIDES: dict[tuple[str, str], dict[str, str]] = {
    # Page 2 omits this row entirely in the client PDF.
    ("ROLLS", "Krisper roll"): {
        "units_per_packet": "27",
        "unit": "pc",
        "opening stock": "0",
        "selling_price": "109",
    },
}


def _clean_row(left: dict[str, str | float], right: dict[str, str] | None) -> list[str]:
    right = dict(right or {})
    category = _normalize_category(str(left.get("category", "")))
    item_name = str(left.get("item_name", "")).strip()
    sub_item = str(left.get("sub_item", "")).strip()

    override = PAGE2_OVERRIDES.get((category, item_name))
    if override:
        right.update(override)

    opening_stock = right.get("opening stock", "").strip() or "0"

    return [
        category,
        item_name,
        sub_item,
        str(left.get("barcode", "")).strip(),
        str(left.get("qty_per_sale", "")).strip(),
        right.get("packets", "").strip(),
        right.get("units_per_packet", "").strip(),
        right.get("unit", "").strip(),
        opening_stock,
        right.get("cost_price", "").strip(),
        right.get("selling_price", "").strip(),
    ]


def parse_menu_pdf(pdf_path: Path) -> list[list[str]]:
    with pdfplumber.open(pdf_path) as doc:
        if len(doc.pages) < 2:
            raise ValueError(f"Expected a 2-page menu PDF, got {len(doc.pages)} pages.")

        page1 = _parse_page1(doc.pages[0])
        page2_by_y = _parse_page2(doc.pages[1])

    rows = [
        _clean_row(left, page2_by_y.get(float(left["y"])))
        for left in page1
    ]
    return rows


def write_xlsx(path: Path, rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    workbook = Workbook()
    worksheet = workbook.active
    worksheet.title = "Sheet1"
    worksheet.append(HEADERS)
    for row in rows:
        worksheet.append([value if value != "" else None for value in row])
    workbook.save(path)


def write_csv(path: Path, rows: list[list[str]]) -> None:
    import csv

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(HEADERS)
        writer.writerows(rows)


def publish_menu_files(rows: list[list[str]]) -> None:
    write_xlsx(MASTER_XLSX, rows)
    shutil.copy2(MASTER_XLSX, FIXTURE_XLSX)
    write_csv(CSV_SEED, rows)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for location in LOCATIONS:
        target = OUT_DIR / f"{location}.xlsx"
        shutil.copy2(MASTER_XLSX, target)
        print(f"Wrote {target}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "pdf",
        type=Path,
        help="Path to the client menu PDF",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional single .xlsx output path (also publishes templates when omitted)",
    )
    args = parser.parse_args()

    if not args.pdf.is_file():
        raise SystemExit(f"PDF not found: {args.pdf}")

    rows = parse_menu_pdf(args.pdf)
    if not rows:
        raise SystemExit("No menu rows were extracted from the PDF.")

    if args.output:
        write_xlsx(args.output, rows)
        print(f"Wrote {args.output}")
        return

    publish_menu_files(rows)
    print(f"Published {len(rows)} menu rows to templates and {len(LOCATIONS)} locations.")


if __name__ == "__main__":
    main()
