#!/usr/bin/env bash
# Offline checks only: no Vivado, hardware connection or new FPGA execution.
set -euo pipefail
if (( $# )); then
    printf 'Usage: bash scripts/verify_saved.sh\n'
    [[ $# == 1 && $1 == --help ]] && exit 0
    exit 2
fi
reuse_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$reuse_repo"
printf 'Checking recorded source and capture hashes...\n'
sha256sum --quiet -c results/source.sha256
sha256sum --quiet -c results/energy/source.sha256
sha256sum --quiet -c results/interactive/captures.sha256
python3 -B scripts/check_capture.py --radix HEX \
    --run A 3 results/hardware/A_w3.csv --run B 3 results/hardware/B_w3.csv \
    --run A -2 results/hardware/A_wminus2.csv --run B -2 results/hardware/B_wminus2.csv
for weight in 7 9; do
    python3 -B scripts/check_capture.py --radix HEX \
        --run A "$weight" "results/interactive/A_w${weight}.csv" \
        --run B "$weight" "results/interactive/B_w${weight}.csv"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tb -p 'test_*.py'
printf 'SAVED_EVIDENCE_PASS: hashes, eight saved captures and validator tests; no fresh hardware run.\n'
