"""Validator unit tests using synthetic data; these are not hardware evidence."""

import csv
import importlib.util
import io
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "check_capture", Path(__file__).resolve().parents[1] / "scripts/check_capture.py")
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)
HEADERS = ("Sample in Buffer,Sample in Window,TRIGGER,core_start,active_mode,"
           "source_read_enable,weight_register_load,sample_request,core_x[15:0],"
           "product_valid,product[31:0],busy_1,done,core_write,rst").split(",")
START_SAMPLE = 8


class MemoryCapture:
    def __init__(self, rows):
        stream = io.StringIO()
        csv.writer(stream).writerows(rows)
        self.text = stream.getvalue()

    def open(self, **kwargs):
        return io.StringIO(self.text)

    def read_bytes(self):
        return self.text.encode()

    def __str__(self):
        return "synthetic-validator-fixture.csv"


def capture_rows(mode=1, weight=3):
    """Match Vivado's observed HEX/no-radix-row CSV shape, including busy_1."""
    rows = [HEADERS.copy()]
    for sample in range(32):
        edge = sample - START_SAMPLE
        value = {name: 0 for name in HEADERS[3:]}
        value.update(core_start=int(edge == 0), active_mode=mode if edge >= 1 else 0,
                     source_read_enable=int(edge in ([1, 4, 7, 10] if mode == 0 else [1])),
                     weight_register_load=int(edge in ([2, 5, 8, 11] if mode == 0 else [2])),
                     sample_request=int(edge in [1, 4, 7, 10]),
                     product_valid=int(edge in [4, 7, 10, 13]),
                     busy_1=int(1 <= edge <= 12), done=int(edge == 13))
        if value["sample_request"]:
            value["core_x[15:0]"] = [1, 2, -3, 4][[1, 4, 7, 10].index(edge)] & 0xffff
        if value["product_valid"]:
            value["product[31:0]"] = ([1, 2, -3, 4][[4, 7, 10, 13].index(edge)] * weight) & 0xffffffff
        rows.append([str(sample), str(sample), str(int(edge == 0))] +
                    [format(value[name], "x") for name in HEADERS[3:]])
    return rows


class CaptureCheckerTests(unittest.TestCase):
    def check(self, rows, mode=1, weight=3, radix="HEX"):
        return CHECKER.check_capture(MemoryCapture(rows), mode, weight, radix)

    def test_four_valid_captures(self):
        for mode in (0, 1):
            for weight in (3, -2):
                with self.subTest(mode=mode, weight=weight):
                    result = self.check(capture_rows(mode, weight), mode, weight)
                    self.assertEqual(result["products"], [weight, 2 * weight, -3 * weight, 4 * weight])
                    self.assertEqual(len(result["read_edges"]), 4 if mode == 0 else 1)
                    self.assertEqual(len(result["load_edges"]), 4 if mode == 0 else 1)
                    self.assertEqual(result["processing_periods"], 12)
                    self.assertEqual(result["done_edge"], 13)

    def test_reject_invalid_signals(self):
        cases = [
            (4, "source_read_enable", "1", "source_read_enable"),
            (4, "product[31:0]", "123", "Expected signed products"),
            (2, "active_mode", "0", "Incorrect latched mode"),
            (4, "product[31:0]", "xxxxxxxx", "Invalid or unknown"),
        ]
        for edge, probe, value, reason in cases:
            with self.subTest(probe=probe, value=value):
                rows = capture_rows()
                rows[1 + START_SAMPLE + edge][HEADERS.index(probe)] = value
                with self.assertRaisesRegex(CHECKER.CaptureError, reason):
                    self.check(rows)

    def test_reject_missing_sample(self):
        rows = capture_rows()
        del rows[1 + START_SAMPLE + 2]
        with self.assertRaisesRegex(CHECKER.CaptureError, "Missing, duplicated or reordered"):
            self.check(rows)

    def test_reject_unverified_probe_alias(self):
        rows = capture_rows()
        rows[0][HEADERS.index("busy_1")] = "busy_2"
        with self.assertRaisesRegex(CHECKER.CaptureError, "Expected exactly one column for busy"):
            self.check(rows)

    def test_require_explicit_radix_when_absent(self):
        with self.assertRaisesRegex(CHECKER.CaptureError, "Missing or unsupported radix"):
            self.check(capture_rows(), radix=None)


if __name__ == "__main__":
    unittest.main()
