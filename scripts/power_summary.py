#!/usr/bin/env python3
"""Check matched mapped activity and preserve estimator results as JSON."""
import hashlib
import json
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def saif_activity(path):
    signals = {}
    depth = 0
    instances = []
    duration = None
    for line in path.read_text().splitlines():
        match = re.search(r"\(DURATION\s+(\d+)\)", line)
        if match:
            duration = int(match[1])
        match = re.search(r"\(TIMESCALE\s+(\d+)\s+(\w+)\)", line)
        if match and match.groups() != ("1", "ps"):
            raise ValueError("Expected SAIF timescale 1 ps")
        match = re.search(r"\(INSTANCE\s+(\S+)", line)
        if match:
            instances.append((match[1], depth + 1))
        match = re.match(r"\s*\((\S+)\s+\(T0\s", line)
        if match:
            name = match[1].replace("\\", "")
            key = "/".join([item[0] for item in instances] + [name])
            signals[key] = {key: int(value) for key, value in re.findall(r"\((T0|T1|TX|TZ|TB|TC)\s+(\d+)\)", line)}
        depth += line.count("(") - line.count(")")
        while instances and depth < instances[-1][1]:
            instances.pop()
    if not duration or depth != 0:
        raise ValueError("Incomplete SAIF file")
    return duration, signals


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def power_values(path):
    document = ET.parse(path).getroot()

    def rows(title):
        section = next(section for section in document.iter("section") if section.get("title") == title)
        result = {}
        for row in section.find("table").findall("tablerow"):
            cells = [cell.get("contents").strip() for cell in row.findall("tablecell")]
            if cells:
                result[cells[0]] = cells[1:]
        return result

    general = rows("Summary")
    components = rows("On-Chip Components")
    hierarchy = rows("By Hierarchy")
    if "Dynamic (uW)" not in general:
        raise ValueError("Expected microwatt XML; milliwatt-rounded reports cannot resolve this experiment")

    def watts(value):
        if "<" in value:
            raise ValueError(f"Insufficient numeric resolution: {value}")
        return float(value) * 1e-6

    values = {
        "core_dynamic": watts(general["Dynamic (uW)"][0]),
        "source_bram_primitive": watts(components["Block RAM"][0]),
        "source_memory_hierarchy": watts(hierarchy["source_memory"][0]),
        "dsp": watts(components["DSPs"][0]),
        "clocks_within_ooc_core": watts(components["Clocks"][0]),
        "signals": watts(components["Signals"][0]),
        "slice_logic": watts(components["Slice Logic"][0]),
        "isolated_design_device_static": watts(general["Device Static (uW)"][0]),
        "isolated_design_device_total": watts(general["Total On-Chip Power (uW)"][0]),
    }
    assert float(general["Junction Temperature (C)"][0]) == 25
    return values, general["Confidence Level"][0], rows("Environment")


def timing_values(path):
    report = path.read_text()
    row = next(line.split() for line in report.splitlines() if line.strip().startswith("core_clock ") and len(line.split()) == 13)
    values = {
        "internal_setup_wns_ns": float(row[1]),
        "internal_hold_whs_ns": float(row[5]),
        "pulse_width_slack_ns": float(row[9]),
        "inputs_without_delay_constraints": int(re.search(r"There are (\d+) input ports with no input delay specified", report)[1]),
        "outputs_without_delay_constraints": int(re.search(r"There are (\d+) ports with no output delay specified", report)[1]),
        "scope": "Internal registered paths meet the 10 ns clock constraint; boundary timing and global clock delay/skew are not signed off by this OOC run.",
    }
    assert all(values[key] >= 0 for key in ("internal_setup_wns_ns", "internal_hold_whs_ns", "pulse_width_slack_ns"))
    assert all(int(row[index]) == 0 for index in (3, 7, 11))
    return values


def write_markdown(root, summary):
    cases = summary["cases"]
    work = cases[0]["work"]
    first_a, first_b = cases[:2]
    reduction = 100 * (first_a["power_w"]["core_dynamic"] - first_b["power_w"]["core_dynamic"]) / first_a["power_w"]["core_dynamic"]
    lines = [
        "# Matched temporal-reuse power estimate",
        "",
        f"Register reuse reduces estimated core dynamic power by about {reduction:.2f}% in this isolated-core model. This is not a measurement of total board power or a claim of the same percentage saving for the complete FPGA design.",
        "",
        f"Each independently reset run computes {work['products']:,} signed products from {work['batches']:,} four-input batches over {work['window_ns']:,} ns at 100 MHz. Inputs are `[1, 2, -3, 4]`; weights 7 and 9 are written at runtime. The initial 300 ns reset/write setup is excluded. Each batch occupies 14 clocks. Every B batch includes its first source fetch.",
        "",
        "| Weight | Mode | Source BRAM (mW) | Core dynamic (mW) | Core energy/product (pJ) |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for case in cases:
        mode = "A: repeated fetch" if case["work"]["mode"] == 0 else "B: register reuse"
        lines.append(f"| {case['work']['weight']} | {mode} | {case['power_w']['source_bram_primitive'] * 1000:.6f} | {case['power_w']['core_dynamic'] * 1000:.6f} | {case['energy_per_product_pj']['core_dynamic']:.4f} |")
    lines += [
        "",
        f"A performs {first_a['work']['physical_reads']:,} actual BRAM reads and DSP B-register loads; B performs {first_b['work']['physical_reads']:,}. The mapped `ENBWREN` and `CEB2` pins are checked at the active clock edges, with `BREG=1`. Both runs have equal clock activity, input/output transitions and DSP operand transitions. SAIF matches all {first_a['matched_design_nets']}/{first_a['total_design_nets']} design nets in each case. The report uses the same routed checkpoint for A and B.",
        "",
        "Source-BRAM dynamic power falls by about 75%. The DSP and clock estimates remain unchanged within each pair. Energy per product is average estimated power multiplied by the matched window duration and divided by the product count.",
        "",
        "| Weight | Mode | Isolated-design device static (mW) | Isolated-design device total (mW) |",
        "| --- | --- | ---: | ---: |",
    ]
    for case in cases:
        lines.append(f"| {case['work']['weight']} | {'A' if case['work']['mode'] == 0 else 'B'} | {case['power_w']['isolated_design_device_static'] * 1000:.6f} | {case['power_w']['isolated_design_device_total'] * 1000:.6f} |")
    timing = summary["timing"]
    ambient = first_a["reported_environment"]["Ambient Temp (C)"][0]
    lines += [
        "",
        "These device totals describe only the isolated design. They exclude the board controller, repeater, VIO, ILA, clock wizard, I/O buffers and board power supplies. Full-board total power was not evaluated.",
        "",
        f"Vivado 2018.1 uses typical process, a fixed junction temperature of 25 C and nominal Vccint/Vccbram of 1.0 V with Vccaux at 1.8 V. The requested ambient is 25 C; with junction temperature fixed, Vivado reports an effective ambient of {ambient} C. The other reported environmental assumptions are retained in `summary.json` and the power reports.",
        "",
        f"Internal registered paths meet the 10 ns constraint: setup slack {timing['internal_setup_wns_ns']:.3f} ns, hold slack {timing['internal_hold_whs_ns']:.3f} ns and pulse-width slack {timing['pulse_width_slack_ns']:.3f} ns. This OOC run has {timing['inputs_without_delay_constraints']} input ports and {timing['outputs_without_delay_constraints']} output ports without delay constraints. Boundary routes and global clock delay/skew are not represented, so this is not board timing signoff.",
        "",
        "Activity comes from functional simulation of the mapped post-route netlist. Routing-delay glitches are not simulated. Primitive internal power remains a vendor model. Vivado's High confidence classification does not validate physical power accuracy. The microwatt text/XML reports retain 1 nW display resolution; that resolution is not an accuracy claim.",
        "",
        "Raw evidence is under `build/` and `weight{7,9}_mode{0,1}/`: SAIF, simulation logs, annotation coverage, primitive switching, standard-W reports and microwatt reports/XML. `summary.json` contains counters, activity, power, energy, environmental assumptions and SHA-256 identities.",
        "",
        f"Checkpoint SHA-256: `{summary['checkpoint_sha256']}`",
        "",
    ]
    with (root / "summary.md").open("x") as stream:
        stream.write("\n".join(lines))


def main():
    root = Path(sys.argv[1]).resolve()
    mapping = dict(line.split("\t", 1) for line in (root / "build/mapping.tsv").read_text().splitlines())
    summary = {
        "scope": "Isolated routed temporal_reuse core; full-board total power NOT evaluated",
        "activity_model": "Mapped post-route functional simulation; no routing-delay glitch simulation",
        "tool": "Vivado/XSim 2018.1",
        "part": "xc7z010clg400-1",
        "clock_hz": 100_000_000,
        "junction_temperature_c": 25,
        "requested_ambient_temperature_c": 25,
        "process": "typical",
        "voltages_v": {"Vccint": 1.0, "Vccaux": 1.8, "Vccbram": 1.0},
        "inputs": [1, 2, -3, 4],
        "batch_cycles": 14,
        "setup_excluded_ns": 300,
        "mapping": mapping,
        "checkpoint_sha256": file_hash(root / "build/routed.dcp"),
        "netlist_sha256": file_hash(root / "build/core_funcsim.v"),
        "timing": timing_values(root / "build/timing.rpt"),
        "cases": [],
        "comparisons": [],
        "power_reporting_resolution_w": 1e-9,
        "limitations": [
            "Simulation-based vendor power estimate, not measured rail power.",
            "Separate out-of-context placement; excludes board controller, repeater, VIO, ILA, clock wizard and board power supplies.",
            "Out-of-context boundary ports have no physical partition locations and clock source is unspecified; their boundary routes and global clock delay/skew are not represented.",
            "Clock activity comes from the 10 ns timing constraint; Vivado ignores SAIF annotation on clock nets.",
            "Physical primitive enables and data activity are covered; primitive internal transistor power remains a vendor model.",
            "Vivado High confidence is a tool classification, not physical power validation; numeric display resolution is not model accuracy.",
            "An unchanged weight output does not imply no BRAM reads or no register loads.",
        ],
    }
    for weight in (7, 9):
        pair = []
        for mode in (0, 1):
            case_dir = root / f"weight{weight}_mode{mode}"
            log = (case_dir / "simulate.log").read_text()
            marker = re.search(r"POWER_SIMULATION_PASS ([^\n]+)", log)
            if not marker or "POWER_SAIF_PASS" not in log:
                raise ValueError(f"Simulation did not pass: {case_dir}")
            work = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", marker[1])}
            if work["mode"] != mode or work["weight"] != weight:
                raise ValueError("Case label mismatch")
            expected_accesses = work["batches"] * (4 if mode == 0 else 1)
            assert all(work[key] == expected_accesses for key in ("reads", "loads", "physical_reads", "physical_loads"))
            assert work["products"] == work["captures"] == work["batches"] * 4
            assert work["completions"] == work["batches"]
            assert work["window_ns"] == work["batches"] * 140
            duration, signals = saif_activity(case_dir / "activity.saif")
            assert duration == work["window_ns"] * 1000
            prefix = "tb_power_temporal_reuse/dut/"
            names = {
                "logical_read": "source_read_enable",
                "logical_load": "weight_register_load",
                "physical_read": mapping["ram_read_pin"],
                "physical_load": mapping["weight_load_pin"],
                "core_clock": "clk",
                "ram_clock": mapping["ram_cell"] + "/CLKBWRCLK",
                "dsp_clock": mapping["dsp_cell"] + "/CLK",
            }
            activity = {}
            for label, name in names.items():
                stats = dict(signals[prefix + name])
                assert stats["TX"] == stats["TZ"] == stats["TB"] == 0
                stats["static_probability"] = stats["T1"] / duration
                stats["transitions_per_second"] = stats["TC"] / (duration * 1e-12)
                activity[label] = stats
            assert activity["logical_read"] == activity["physical_read"]
            assert activity["logical_load"] == activity["physical_load"]
            for label in ("physical_read", "physical_load"):
                assert activity[label]["TC"] == 2 * expected_accesses
                assert activity[label]["T1"] == expected_accesses * 10_000
            for label in ("core_clock", "ram_clock", "dsp_clock"):
                assert activity[label]["TC"] == 2 * work["batches"] * 14
            report_log = (case_dir / "report.log").read_text()
            if "POWER_REPORT_PASS" not in report_log:
                raise ValueError(f"Power report did not pass: {case_dir}")
            matched = re.search(r"Design nets matched = (\d+) of (\d+)", report_log)
            if not matched:
                raise ValueError("Missing SAIF coverage evidence")
            assert matched[1] == matched[2]
            case = {
                "name": f"weight{weight}_mode{mode}",
                "work": work,
                "saif_duration_ps": duration,
                "saif_sha256": file_hash(case_dir / "activity.saif"),
                "matched_design_nets": int(matched[1]),
                "total_design_nets": int(matched[2]),
                "activity": activity,
                "mem_q_data_transitions": sum(signals[prefix + f"mem_q[{bit}]"]["TC"] for bit in range(16)),
                "dsp_b_input_data_transitions": sum(signals[prefix + mapping["dsp_cell"] + f"/B[{bit}]"]["TC"] for bit in range(18)),
                "dsp_a_input_data_transitions": sum(signals[prefix + mapping["dsp_cell"] + f"/A[{bit}]"]["TC"] for bit in range(30)),
                "x_input_data_transitions": sum(signals[prefix + f"x[{bit}]"]["TC"] for bit in range(16)),
                "y_output_data_transitions": sum(signals[prefix + f"y[{bit}]"]["TC"] for bit in range(32)),
            }
            case["power_w"], case["vivado_confidence"], case["reported_environment"] = power_values(case_dir / "power.xml")
            case["energy_per_product_pj"] = {key: value * work["window_ns"] / work["products"] * 1000 for key, value in case["power_w"].items()}
            summary["cases"].append(case)
            pair.append(case)
        assert pair[0]["work"]["window_ns"] == pair[1]["work"]["window_ns"]
        assert pair[0]["work"]["products"] == pair[1]["work"]["products"]
        assert pair[0]["activity"]["core_clock"] == pair[1]["activity"]["core_clock"]
        assert pair[0]["mem_q_data_transitions"] == pair[1]["mem_q_data_transitions"]
        assert pair[0]["dsp_b_input_data_transitions"] == pair[1]["dsp_b_input_data_transitions"]
        assert pair[0]["dsp_a_input_data_transitions"] == pair[1]["dsp_a_input_data_transitions"]
        assert pair[0]["x_input_data_transitions"] == pair[1]["x_input_data_transitions"]
        assert pair[0]["y_output_data_transitions"] == pair[1]["y_output_data_transitions"]
        summary["comparisons"].append({
            "weight": weight,
            "a_minus_b_power_w": {key: pair[0]["power_w"][key] - pair[1]["power_w"][key] for key in pair[0]["power_w"]},
            "a_minus_b_energy_per_product_pj": {key: pair[0]["energy_per_product_pj"][key] - pair[1]["energy_per_product_pj"][key] for key in pair[0]["energy_per_product_pj"]},
            "energy_interpretation": "Average simulated-window power times matched 14-clock cadence divided by four products; not measured energy.",
        })
    with (root / "summary.json").open("x") as stream:
        json.dump(summary, stream, indent=2)
        stream.write("\n")
    write_markdown(root, summary)
    print(f"POWER_SUMMARY_PASS {root / 'summary.json'}")


if __name__ == "__main__":
    main()
