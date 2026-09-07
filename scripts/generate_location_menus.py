#!/usr/bin/env python3
"""Generate per-location menu Excel files from the Shilpa Enterprise PDF menu."""

import csv
from pathlib import Path

from openpyxl import Workbook

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

# Parsed from Shilpa_Enterprise_menu_items PDF (all three locations share this menu).
MENU_ROWS = [
    ["BEVARGES", "water 1/2 liter", "water", "BEVARGES", "1", "", "24", "pc", "", "", "10"],
    ["BEVARGES", "cool drinks glass", "cool drinks", "BEVARGES", "1", "", "24", "pc", "", "", "15"],
    ["BEVARGES", "pepsi 300 ml", "pepsi", "BEVARGES", "1", "", "24", "pc", "", "", "20"],
    ["BURGERS", "star burger", "Crispy Chicken Patty", "COMBO", "1", "", "20", "pc", "0", "", "60"],
    ["BURGERS", "Hot Crispy burger", "Hot Crispy Patty", "COMBO", "1", "", "5", "pc", "0", "", "110"],
    ["BURGERS", "Paneer Delight burger", "Paneer Patty", "COMBO", "1", "", "14", "pc", "0", "", "90"],
    ["BURGERS", "Tandoori Burger Bun", "Tandoori Patty", "COMBO", "1", "", "13", "pc", "0", "", "95"],
    ["BURGERS", "Hungery bird burger", "Whole Muscle Patty", "COMBO", "1", "", "13", "pc", "0", "", "100"],
    ["BURGERS", "Veg Burger", "Veg Patty", "COMBO", "1", "", "13", "pc", "0", "", "65"],
    ["BURGERS", "smokey burger", "smokey burger", "COMBO", "1", "", "10", "pc", "", "", "129"],
    ["FRIED ITEMS", "mirchi bites", "mirchi bites", "FRIED ITEM", "8", "", "40", "pc", "", "", "109"],
    ["FRIED ITEMS", "saucy bites", "boneless bites", "FRIED ITEM", "2", "", "10", "pc", "", "", "99"],
    ["FRIED ITEMS", "chicken lollipops", "chicken lollipops", "FRIED ITEM", "", "", "4", "pc", "", "", "119"],
    ["FRIED ITEMS", "Mini Bucket", "Thai Crispy", "FRIED ITEM", "5", "", "10", "pc", "", "", "385"],
    ["FRIED ITEMS", "Big Buckets", "Thai Crispy", "FRIED ITEM", "10", "", "10", "pc", "", "", "765"],
    ["FRIED ITEMS", "Chicken Popcorn", "Chicken Popcorn Small", "FRIED ITEM", "80", "", "", "g", "0", "", "70"],
    ["FRIED ITEMS", "Chicken Strips", "Chicken Strips", "FRIED ITEM", "3", "", "27", "pc", "0", "", "99"],
    ["FRIED ITEMS", "Chilli Burst", "Chilli Burst", "FRIED ITEM", "1", "", "10", "pc", "0", "", "80"],
    ["FRIED ITEMS", "Crunchy Masala", "Crunchy Masala", "FRIED ITEM", "1", "", "10", "pc", "", "", "50"],
    ["FRIED ITEMS", "Krusty Bites", "Krusty Bites", "FRIED ITEM", "1", "", "", "pc", "0", "", "90"],
    ["FRIED ITEMS", "Peri Peri Chwings", "Peri Peri Chwings", "FRIED ITEM", "1", "", "", "pc", "0", "", "99"],
    ["FRIED ITEMS", "Thai Crispy", "Thai Crispy", "FRIED ITEM", "1", "", "10", "pc", "0", "", "80"],
    ["ROLLS", "Tandoori roll", "chicken 65", "COMBO", "1", "", "4", "pc", "0", "", "85"],
    ["ROLLS", "Panner roll", "panner patty", "COMBO", "1", "", "14", "pc", "0", "", "90"],
    ["ROLLS", "Chicken Roll", "chicken roll", "COMBO", "1", "", "", "pc", "0", "", ""],
    ["ROLLS", "KRISPER Roll", "Krisper Roll", "COMBO", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "Paratha Sauce", "Paratha Sauce", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "Tandoori Mayonnaise", "Tandoori Mayonnaise", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "BBQ Seasoning", "BBQ Seasoning", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "CP Marinade", "CP Marinade", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "Eggless Mayonnaise", "Eggless Mayonnaise", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "PACKING COVER", "PACKING COVER", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SAUCES", "SNACK BOX", "SNACK BOX", "SAUCE/DRY STOCK", "1", "", "", "pc", "0", "", ""],
    ["SNACKS", "French Fries", "French Fries Small", "SNACKS", "80", "", "", "g", "0", "", "50"],
    ["SNACKS", "CHICKEN STRIPS", "CHICKEN STRIPS", "COMBO", "1", "", "50", "pc", "0", "", "85"],
    ["SNACKS", "Chicken 65", "Chicken 65", "SNACKS", "1", "", "", "pc", "0", "", "85"],
    ["SNACKS", "Chicken Cheese Shotz", "Chicken Cheese Shotz", "SNACKS", "1", "", "50", "pc", "0", "", "90"],
    ["SNACKS", "Chicken Fingers", "Chicken Fingers", "SNACKS", "3", "", "39", "pc", "0", "", "60"],
    ["SNACKS", "Chicken Momos", "Chicken Momos", "SNACKS", "4", "", "40", "pc", "0", "", ""],
    ["SNACKS", "Chicken Nuggets", "Chicken Nuggets", "SNACKS", "4", "", "60", "pc", "0", "", "55"],
    ["SNACKS", "Pizza Pocket", "Pizza Pocket", "SNACKS", "4", "", "28", "pc", "0", "", "59"],
    ["SNACKS", "Veg Finger", "Veg Finger", "SNACKS", "3", "", "33", "pc", "0", "", "55"],
    ["SNACKS", "chicken popcorn large", "Chicken Popcorn Large", "SNACKS", "120", "", "", "g", "0", "", "120"],
    ["SNACKS", "masala fries Large", "French Fries Large", "SNACKS", "120", "", "", "g", "0", "", "99"],
    ["STOCK", "Burger Bun With Sesame", "Bun", "STOCK", "1", "", "6", "pc", "0", "", ""],
    ["STOCK", "Paratha", "Paratha", "STOCK", "1", "", "1", "pc", "0", "", ""],
]

LOCATIONS = [
    "Gt world mall",
    "Magadi road",
    "Subbanna garden",
]


def write_xlsx(path: Path) -> None:
    wb = Workbook()
    ws = wb.active
    ws.title = "Menu"
    ws.append(HEADERS)
    for row in MENU_ROWS:
        ws.append(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(path)


def write_csv(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADERS)
        writer.writerows(MENU_ROWS)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    out_dir = root / "assets" / "templates" / "locations"
    for location in LOCATIONS:
        write_xlsx(out_dir / f"{location}.xlsx")
        print(f"Wrote {out_dir / f'{location}.xlsx'}")

    # Keep the shared master CSV in sync with the PDF.
    write_csv(root / "assets" / "templates" / "menu_items_import.csv")
    write_xlsx(root / "assets" / "templates" / "menu_items_import_v2.xlsx")
    print("Updated shared menu_items_import.csv and menu_items_import_v2.xlsx")


if __name__ == "__main__":
    main()
