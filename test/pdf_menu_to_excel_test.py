#!/usr/bin/env python3
"""Tests for scripts/pdf_menu_to_excel.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/pdf_menu_to_excel.py"
PDF = Path(
    "/home/ubuntu/.cursor/projects/workspace/uploads/"
    "Shilpa_Enterprise_menu_items2-1__2__3d36.pdf"
)

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


def load_module():
    spec = importlib.util.spec_from_file_location("pdf_menu_to_excel", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class PdfMenuToExcelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = load_module()

    def test_extracts_expected_row_count(self) -> None:
        rows = self.module.parse_menu_pdf(PDF)
        self.assertEqual(len(rows), 45)

    def test_headers_and_key_rows(self) -> None:
        rows = self.module.parse_menu_pdf(PDF)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "menu.xlsx"
            self.module.write_xlsx(output, rows)

            workbook = openpyxl.load_workbook(output)
            worksheet = workbook.active
            self.assertEqual(
                [worksheet.cell(1, column).value for column in range(1, 12)],
                HEADERS,
            )

            by_name = {row[1]: row for row in rows}
            self.assertEqual(by_name["French Fries"][0], "SNACKS")
            self.assertEqual(by_name["French Fries"][4], "70")
            self.assertEqual(by_name["French Fries"][6], "2500")
            self.assertEqual(by_name["French Fries"][7], "g")
            self.assertEqual(by_name["French Fries"][10], "50")

            self.assertEqual(by_name["star burger"][0], "BURGERS")
            self.assertEqual(by_name["star burger"][2], "Crispy Chicken Patty")

            self.assertEqual(by_name["Krisper roll"][0], "ROLLS")
            self.assertEqual(by_name["Krisper roll"][4], "1.5")
            self.assertEqual(by_name["Krisper roll"][6], "27")
            self.assertEqual(by_name["Krisper roll"][10], "109")

            fried_popcorn = by_name["Chicken popcorn large"]
            self.assertEqual(fried_popcorn[0], "FRIED ITEMS")
            self.assertEqual(fried_popcorn[4], "130")
            self.assertEqual(fried_popcorn[10], "129")

            snacks_popcorn = by_name["chicken popcorn large"]
            self.assertEqual(snacks_popcorn[0], "SNACKS")
            self.assertEqual(snacks_popcorn[4], "140")
            self.assertEqual(snacks_popcorn[10], "120")


if __name__ == "__main__":
    unittest.main()
