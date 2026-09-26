#!/usr/bin/env python3
r"""Check exported ILA CSVs against the board_top probe and clock contracts.

Example:
  python3 scripts/check_capture.py --radix HEX --run A 3 A_w3.csv --run B 3 B_w3.csv \
      --run A -2 A_wminus2.csv --run B -2 B_wminus2.csv

The ILA samples the values present before each rising edge. Start is sample
zero. READ/LOAD enables retain the core's edge numbers; registered products
and done are visible one sample after their MUL edges.
"""

import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path


PROBES = (
    "core_start", "active_mode", "source_read_enable", "weight_register_load",
    "sample_request", "core_x", "product_valid", "product", "busy", "done",
    "core_write", "rst",
)
WIDTHS = {name: 1 for name in PROBES}
WIDTHS.update(core_x=16, product=32)
RADICES = {"BIN": 2, "BINARY": 2, "HEX": 16, "HEXADECIMAL": 16,
           "SIGNED": 10, "UNSIGNED": 10, "DEC": 10, "DECIMAL": 10}
REQUIRED_RUNS = {(0, 3), (1, 3), (0, -2), (1, -2)}
INPUTS = [1, 2, -3, 4]
# Vivado 2018.1 names the mapped board_top probe8 net busy_1.
PROBE_ALIASES = {"busy": ("busy_1",)}


class CaptureError(ValueError):
    """The capture cannot establish the required behavior."""


def require(condition, message):
    if not condition:
        raise CaptureError(message)


def leaf_name(header):
    return re.sub(r"\[\d+(?::\d+)?\]$", "", header.strip().split("/")[-1])


def decode(token, radix, width, signed=False):
    token = token.strip().replace("_", "")
    try:
        value = int(token, RADICES[radix])
    except (ValueError, KeyError) as exc:
        raise CaptureError(f"Invalid or unknown {radix} value: {token!r}") from exc
    minimum = -(1 << (width - 1)) if signed else 0
    require(minimum <= value < (1 << width), f"Value {token!r} does not fit {width} bits")
    if signed and value >= (1 << (width - 1)):
        value -= 1 << width
    return value


def read_capture(path, fallback_radix):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = [[cell.strip() for cell in row] for row in csv.reader(stream) if any(row)]
    header_index = next((index for index, row in enumerate(rows)
                         if "sample in buffer" in [cell.lower() for cell in row]), None)
    require(header_index is not None, "Missing 'Sample in Buffer' CSV header")
    headers = rows[header_index]
    sample_column = [cell.lower() for cell in headers].index("sample in buffer")
    columns = {}
    for probe_number, name in enumerate(PROBES):
        accepted_names = (name, f"probe{probe_number}") + PROBE_ALIASES.get(name, ())
        candidates = [index for index, header in enumerate(headers)
                      if leaf_name(header) in accepted_names]
        require(len(candidates) == 1,
                f"Expected exactly one column for {name} (probe{probe_number}); found {len(candidates)}")
        columns[name] = candidates[0]
    require(len(set(columns.values())) == len(PROBES), "Probe columns overlap")
    body = rows[header_index + 1:]
    require(body, "CSV contains no sample rows")
    radices = [fallback_radix] * len(headers)
    if body[0][0].upper().startswith("RADIX"):
        require(len(body[0]) == len(headers), "Radix row does not match header width")
        radices = [re.sub(r"^RADIX\s*-\s*", "", item.upper()) for item in body.pop(0)]
    for name, column in columns.items():
        require(radices[column] in RADICES,
                f"Missing or unsupported radix for {name}; pass --radix only if the CSV omits metadata")
    require(body, "CSV contains no sample rows")
    samples = []
    for line_number, row in enumerate(body, start=header_index + 2):
        require(len(row) == len(headers), f"Row {line_number} does not match header width")
        try:
            sample_number = int(row[sample_column], 10)
        except ValueError as exc:
            raise CaptureError(f"Invalid sample index on row {line_number}") from exc
        require(sample_number >= 0, f"Negative buffer sample index on row {line_number}")
        if samples:
            require(sample_number == samples[-1]["sample"] + 1,
                    f"Missing, duplicated or reordered buffer sample at {sample_number}")
        sample = {"sample": sample_number}
        for name, column in columns.items():
            # Invalid/stale datapath values outside capture/valid edges are irrelevant.
            if name in ("core_x", "product"):
                sample[name] = (row[column], radices[column])
            else:
                sample[name] = decode(row[column], radices[column], WIDTHS[name])
        samples.append(sample)
    return samples


def check_capture(path, mode, weight, fallback_radix=None):
    samples = read_capture(path, fallback_radix)
    starts = [sample["sample"] for sample in samples if sample["core_start"]]
    require(len(starts) == 1, f"Expected one accepted start pulse; found {len(starts)} samples high")
    start = starts[0]
    require(samples[-1]["sample"] >= start + 14,
            "Capture must include at least two edges after the final MUL (through relative edge 14)")
    by_edge = {sample["sample"] - start: sample for sample in samples}
    expected_edges = {
        "core_start": [0],
        "source_read_enable": [1, 4, 7, 10] if mode == 0 else [1],
        "weight_register_load": [2, 5, 8, 11] if mode == 0 else [2],
        "sample_request": [1, 4, 7, 10],
        "product_valid": [4, 7, 10, 13],
        "done": [13],
        "busy": list(range(1, 13)),
    }
    actual_edges = {}
    for name, expected in expected_edges.items():
        actual = [edge for edge, sample in by_edge.items() if sample[name]]
        require(actual == expected, f"{name}: expected relative edges {expected}; observed {actual}")
        actual_edges[name] = actual
    for edge, sample in by_edge.items():
        if edge >= 0:
            require(sample["rst"] == 0 and sample["core_write"] == 0,
                    f"Reset or source write observed at relative edge {edge}")
        if 1 <= edge <= 13:
            require(sample["active_mode"] == mode, f"Incorrect latched mode at relative edge {edge}")
    inputs = [decode(*by_edge[edge]["core_x"], 16, signed=True)
              for edge in expected_edges["sample_request"]]
    require(inputs == INPUTS, f"Expected captured inputs {INPUTS}; observed {inputs}")
    products = [decode(*by_edge[edge]["product"], 32, signed=True)
                for edge in expected_edges["product_valid"]]
    expected_products = [value * weight for value in INPUTS]
    require(products == expected_products,
            f"Expected signed products {expected_products}; observed {products}")
    return {
        "csv": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "mode": "A" if mode == 0 else "B", "weight": weight,
        "sample_count": len(samples), "start_sample": start,
        "inputs": inputs, "products": products,
        "read_edges": actual_edges["source_read_enable"],
        "load_edges": actual_edges["weight_register_load"],
        "valid_edges": actual_edges["product_valid"], "done_edge": 13,
        "processing_periods": 12, "registered_output_observation_offset": 1,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", action="append", nargs=3, required=True,
                        metavar=("MODE", "WEIGHT", "CSV"),
                        help="one capture with mode A/B or 0/1 and runtime weight; repeat for all four runs")
    parser.add_argument("--radix", choices=sorted(RADICES),
                        help="explicit probe radix when the CSV has no radix row")
    parser.add_argument("--json", action="store_true", help="print the validation results as JSON")
    args = parser.parse_args()
    results = []
    seen = set()
    try:
        for mode_text, weight_text, path_text in args.run:
            require(mode_text.upper() in ("A", "B", "0", "1"), f"Unsupported mode: {mode_text}")
            mode = 0 if mode_text.upper() in ("A", "0") else 1
            weight = int(weight_text, 10)
            require(-32768 <= weight <= 32767, "Runtime weight must be signed 16-bit")
            require((mode, weight) not in seen, f"Duplicate mode/weight pair: {mode_text}, {weight}")
            seen.add((mode, weight))
            path = Path(path_text)
            try:
                results.append(check_capture(path, mode, weight, args.radix))
            except (CaptureError, OSError) as exc:
                raise CaptureError(f"{path}: {exc}") from exc
    except (CaptureError, ValueError) as exc:
        print(f"CAPTURE CHECK FAILED: {exc}", file=sys.stderr)
        return 1
    complete = seen == REQUIRED_RUNS
    marker = "FOUR_RUN_CAPTURE_CHECK_PASS" if complete else "CAPTURE_CHECK_PASS"
    if args.json:
        print(json.dumps({"result": marker, "four_required_runs_passed": complete, "runs": results}, indent=2))
    else:
        for result in results:
            print(f"PASS mode={result['mode']} weight={result['weight']} products={result['products']} "
                  f"reads={len(result['read_edges'])} loads={len(result['load_edges'])} "
                  f"processing_periods=12 observed_done_edge=13")
        print(marker)
        if not complete:
            print("This subset does not establish the four-run hardware acceptance criterion.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
