#!/usr/bin/env python3
"""Validate full-board activity coverage and report the implemented PL estimate."""
import hashlib
import csv
import json
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_activity(path, wanted, design_nets):
    depth = 0
    instances = []
    duration = None
    selected = {}
    exact_design_names = set()
    unknown = []
    with path.open() as source:
        for line in source:
            match = re.search(r"\(DURATION\s+(\d+)\)", line)
            if match:
                duration = int(match[1])
            match = re.search(r"\(TIMESCALE\s+(\d+)\s+(\w+)\)", line)
            if match and match.groups() != ("1", "ps"):
                raise ValueError("Expected 1 ps SAIF units")
            match = re.search(r"\(INSTANCE\s+(\S+)", line)
            if match:
                instances.append((match[1].replace("\\", ""), depth + 1))
            match = re.match(r"\s*\((\S+)\s+\(T0\s", line)
            if match:
                name = "/".join([item[0] for item in instances][2:] + [match[1].replace("\\", "")])
                if name in wanted or name in design_nets:
                    stats = {key: int(value) for key, value in re.findall(r"\((T0|T1|TX|TZ|TB|TC)\s+(\d+)\)", line)}
                    if sum(stats.get(key, 0) for key in ("T0", "T1", "TX", "TZ", "TB")) != duration:
                        raise ValueError(f"Incomplete SAIF dwell duration for {name}")
                    if name in wanted:
                        selected[name] = stats
                    if name in design_nets:
                        exact_design_names.add(name)
                        if stats.get("TX", 0) + stats.get("TZ", 0) + stats.get("TB", 0):
                            unknown.append({"net": name, "activity": stats})
            depth += line.count("(") - line.count(")")
            while instances and depth < instances[-1][1]:
                instances.pop()
    if not duration or depth:
        raise ValueError("Incomplete SAIF")
    return duration, selected, exact_design_names, unknown


def xml_rows(document, title):
    section = next(section for section in document.iter("section") if section.get("title") == title)
    return [[cell.get("contents").strip() for cell in row.findall("tablecell")] for row in section.find("table").findall("tablerow") if row.findall("tablecell")]


def unique_row(rows, name):
    matches = [row for row in rows if row[0] == name]
    if len(matches) != 1:
        raise ValueError(f"Expected one power row {name}: {matches}")
    return matches[0]


def ram32m_vector_alias(name):
    match = re.fullmatch(r"(.*?/RAM_reg_\d+_\d+_\d+_\d+/)(ADDR[A-D]|DI[A-D]|DO[A-D])(\d)", name)
    return f"{match[1]}{match[2]}[{match[3]}]" if match else None


def unused_vector_holes():
    prefix = "capture_ila/U0/ila_core_inst/"
    return ({f"{prefix}u_ila_cap_ctrl/u_cap_addrgen/cfg_data_vec_sync{stage}[{bit}]"
             for stage in (1, 2) for bit in [0] + list(range(11, 33))}
            | {f"{prefix}u_ila_regs/s_daddr[{bit}]" for bit in range(13, 17)}
            | {"repeater/core/in0[1]", "repeater/core/in0[2]"})


def power_values(path, mapping):
    document = ET.parse(path).getroot()
    summary = dict((row[0], row[1]) for row in xml_rows(document, "Summary"))
    hierarchy = xml_rows(document, "By Hierarchy")
    if "Dynamic (uW)" not in summary:
        raise ValueError("Expected microwatt report")
    values = {
        "full_implemented_pl_dynamic": float(summary["Dynamic (uW)"]) * 1e-6,
        "device_static": float(summary["Device Static (uW)"]) * 1e-6,
        "full_implemented_pl_device_total": float(summary["Total On-Chip Power (uW)"]) * 1e-6,
        "core_hierarchy_dynamic": float(unique_row(hierarchy, "core")[1]) * 1e-6,
        "repeater_including_core_dynamic": float(unique_row(hierarchy, "repeater")[1]) * 1e-6,
        "source_bram_primitive": float(unique_row(xml_rows(document, "Block RAM"), mapping["ram_cell"])[1]) * 1e-6,
    }
    values["repeater_excluding_core_dynamic"] = values["repeater_including_core_dynamic"] - values["core_hierarchy_dynamic"]
    return values, summary, xml_rows(document, "By Clock Domain"), xml_rows(document, "Environment")


def main():
    root = Path(sys.argv[1]).resolve()
    mapping = dict(line.split("\t", 1) for line in (root / "export/mapping.tsv").read_text().splitlines())
    design_nets = set((root / "export/design_nets.txt").read_text().splitlines())
    ram_pin = mapping["ram_read_pin"]
    dsp_pin = mapping["weight_load_pin"]
    bscan = mapping["bscan_cell"]
    fixed_names = ["source_read_enable", "weight_register_load", "clk_out1", "sys_clk", "rst", "clock_locked", "sample_request", "core_start", "core_done", "product_valid", "run_busy", "run_done", ram_pin, dsp_pin, mapping["ram_cell"] + "/CLKBWRCLK", mapping["dsp_cell"] + "/CLK"]
    jtag_names = [bscan + "/" + name for name in ("TCK", "SEL", "SHIFT", "CAPTURE", "UPDATE", "RESET", "DRCK", "TDI", "TMS", "RUNTEST")]
    data_names = ["core_x[{}]".format(bit) for bit in range(16)] + ["last_product[{}]".format(bit) for bit in range(32)]
    aliases = {name: ram32m_vector_alias(name) for name in design_nets if ram32m_vector_alias(name)}
    wanted = set(fixed_names + jtag_names + data_names) | set(aliases.values())
    result = {
        "scope": "Complete implemented energy_board_top PL design; no PS7/ARM workload, external regulators or off-chip loads",
        "checkpoint_sha256": mapping["checkpoint_sha256"],
        "netlist_sha256": digest(root / "export/board_funcsim.v"),
        "mapping": {key: value for key, value in mapping.items() if key != "checkpoint"},
        "tool": "Vivado/XSim 2018.1",
        "activity_model": "Post-route mapped functional simulation; routing-delay glitches are not simulated",
        "capture_method": "Native XSim SAIF from direct mapped hierarchy scopes plus explicit primitive pins; no recursive unisim-array enumeration or VCD conversion",
        "stimulus": "All eleven top cfg_* nets forced to documented VIO values; JTAG model boundary initialized during GSR then held idle; no internal datapath state forced",
        "force_manifest": (root / "forces_manifest.txt").read_text().splitlines(),
        "junction_temperature_c": 25,
        "requested_ambient_temperature_c": 25,
        "process": "typical",
        "power_report_resolution_w": 1e-9,
        "cases": [],
        "limitations": [
            "Vendor model estimate, not a rail-power or board-energy measurement.",
            "Repeater counters, VIO, ILA, debug hub, MMCM and clock routing are included; their mode-dependent activity contributes to the full-design delta.",
            "Vivado 2018.1 rejects the requested zero TCK activity and retains its 33 ns timing-clock model despite constant TCK in simulation; clock power is not a measured idle-JTAG value.",
            "Power annotation is partial: unused debug FIFO output nets retain tool inference. Unused mapped vector holes with high-Z activity are preserved and separately audited; identical limitations do not prove error cancellation.",
            "Core hierarchy power is Vivado-attributed power inside the instrumented design, including routed load attribution, not an electrically isolated core estimate.",
            "Numeric resolution and Vivado confidence are not model-accuracy claims.",
        ],
    }
    for mode in (0, 1):
        folder = root / f"mode{mode}"
        log = (folder / "simulate.log").read_text()
        marker = re.search(r"BOARD_POWER_SIMULATION_PASS ([^\n]+)", log)
        if not marker or "BOARD_POWER_SAIF_PASS" not in log:
            raise ValueError("Missing simulation pass")
        work = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", marker[1])}
        expected = work["batches"] * (4 if mode == 0 else 1)
        assert work["mode"] == mode and work["weight"] == 7
        assert work["reads"] == work["loads"] == expected
        assert work["products"] == work["captures"] == 4 * work["batches"]
        assert work["launches"] == work["completions"] == work["batches"]
        assert work["cycles"] == 14 * work["batches"]
        assert work["window_ns"] == 140 * work["batches"]
        duration, activity, exact_names, unknown = read_activity(folder / "activity.saif", wanted, design_nets)
        with (folder / "mapped_unknown_activity.json").open("x") as stream:
            json.dump(unknown, stream, indent=2)
        missing_exact_names = sorted(design_nets - exact_names)
        with (folder / "mapped_without_exact_saif_name.json").open("x") as stream:
            json.dump(missing_exact_names, stream, indent=2)
        assert duration == 1000 * work["window_ns"]
        for name in wanted:
            assert name in activity, f"Missing activity: {name}"
            assert activity[name]["TX"] == activity[name]["TZ"] == activity[name]["TB"] == 0, name
        for name in (ram_pin, dsp_pin):
            assert activity[name]["TC"] == 2 * expected
            assert activity[name]["T1"] == 10000 * expected
        assert activity[ram_pin] == activity["source_read_enable"]
        assert activity[dsp_pin] == activity["weight_register_load"]
        assert activity["clk_out1"]["TC"] == 28 * work["batches"]
        for name in jtag_names:
            assert activity[name]["TC"] == 0, name
            assert activity[name]["T1"] == (duration if name.endswith("/RUNTEST") else 0), name
        report_log = (folder / "report.log").read_text()
        assert "BOARD_POWER_REPORT_PASS" in report_log
        matched = re.search(r"Design nets matched = (\d+) of (\d+)", report_log)
        assert matched
        unmatched = [line.strip() for line in (folder / "annotation.rpt").read_text().split("--- Unmatched design nets ---\n", 1)[1].splitlines() if line.strip()]
        assert len(unmatched) == int(matched[2]) - int(matched[1])
        assert all(re.fullmatch(r"dbg_hub/.*/RAM_reg_\d+_\d+_\d+_\d+/DO[CD][01]", name) for name in unmatched), "New unmatched power nets require review"
        assert {item["net"] for item in unknown} == unused_vector_holes(), "New unknown mapped nets require review"
        assert all(item["activity"]["TZ"] == duration and item["activity"]["TC"] == 0 for item in unknown)
        connectivity = list(csv.DictReader((folder / "connectivity.tsv").open(), delimiter="\t"))
        assert {row["net"] for row in connectivity} == unused_vector_holes() | set(unmatched)
        assert all(int(row["leaf_loads"]) == 0 for row in connectivity)
        assert all(int(row["leaf_drivers"]) == 0 for row in connectivity if row["category"] == "floating_vector_hole")
        missing_classes = {"constant_nets": [], "ram32m_vector_aliases": [], "bram_regce_ground_aliases": []}
        for name in missing_exact_names:
            if re.search(r"(^|/)(<const[01]>|GND_\d+|VCC_\d+)$", name):
                missing_classes["constant_nets"].append(name)
            elif name in aliases and aliases[name] in activity:
                missing_classes["ram32m_vector_aliases"].append(name)
            elif re.search(r"/DEVICE_7SERIES\.NO_BMM_INFO\.SDP\.SIMPLE_PRIM36\.ram_REGCEAREGCE_cooolgate_en_sig_[12]_1$", name):
                missing_classes["bram_regce_ground_aliases"].append(name)
            else:
                raise ValueError(f"Unclassified missing exact SAIF record: {name}")
        identity = (folder / "analysis_identity.tsv").read_text()
        assert mapping["checkpoint_sha256"] in identity
        power, general, clocks, environment = power_values(folder / "power.xml", mapping)
        case = {
            "mode": mode, "work": work, "power_w": power,
            "energy_per_product_pj": {name: value * work["window_ns"] / work["products"] * 1000 for name, value in power.items()},
            "measurement_start_ns": int(re.search(r"BOARD_POWER_WINDOW_START_NS=(\d+)", log)[1]),
            "saif_duration_ps": duration, "saif_sha256": digest(folder / "activity.saif"),
            "matched_design_nets": int(matched[1]), "total_design_nets": int(matched[2]),
            "matched_design_nets_percent": 100 * int(matched[1]) / int(matched[2]),
            "unmatched_power_design_nets": unmatched,
            "exact_name_saif_design_nets": len(exact_names), "mapped_unknown_net_count": len(unknown),
            "mapped_without_exact_saif_name_count": len(missing_exact_names),
            "missing_exact_record_classes": {name: len(values) for name, values in missing_classes.items()},
            "unused_vector_hole_activity": unknown,
            "unused_net_physical_connectivity": connectivity,
            "activity": activity, "clock_power_rows": clocks, "reported_environment": environment,
            "vivado_confidence": general["Confidence Level"],
            "primitive_power_activity": (folder / "primitive_switching.rpt").read_text().splitlines(),
        }
        result["cases"].append(case)
    first, second = result["cases"]
    assert first["measurement_start_ns"] == second["measurement_start_ns"]
    assert first["saif_duration_ps"] == second["saif_duration_ps"]
    for name in ("clk_out1", "sys_clk") + tuple(data_names):
        assert first["activity"][name] == second["activity"][name], name
    result["a_minus_b_power_w"] = {name: first["power_w"][name] - second["power_w"][name] for name in first["power_w"]}
    with (root / "summary.json").open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    lines = ["# Complete implemented PL: qualified matched estimate", "", "Same routed board checkpoint, runtime weight 7 and signed inputs `[1, 2, -3, 4]`. These are partially annotated vendor-model estimates, not measured board power.", "", "| Mode | Source BRAM (mW) | Attributed core (mW) | Repeater incl. core (mW) | Full PL dynamic (mW) | Device total (mW) |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for case in result["cases"]:
        power = case["power_w"]
        lines.append("| " + ("A" if case["mode"] == 0 else "B") + " | " + " | ".join(f"{power[name] * 1000:.6f}" for name in ("source_bram_primitive", "core_hierarchy_dynamic", "repeater_including_core_dynamic", "full_implemented_pl_dynamic", "full_implemented_pl_device_total")) + " |")
    work = first["work"]
    lines += ["", f"Each run processes {work['products']} products in {work['batches']} batches over {work['window_ns']} ns. A/B physical read and load counts are {first['work']['reads']}/{second['work']['reads']}. All products, hardware counters, checksum and completion checks pass. The first fetch of every B batch is included.", "", f"SAIF matches {first['matched_design_nets']}/{first['total_design_nets']} physical design nets ({first['matched_design_nets_percent']:.6f}%) in each run. The unmatched nets are unused debug FIFO outputs. The separate DCP-name audit preserves {first['mapped_unknown_net_count']} high-Z records in unused vector holes and classifies {first['mapped_without_exact_saif_name_count']} absent exact-name records. Raw activity, classifications and primitive/JTAG checks are in `summary.json` and the adjacent audit files. These limitations are not silently zeroed or assumed to cancel.", "", "The full-design estimate includes the repeater, VIO, unarmed ILA, debug hub, MMCM and FPGA clock routing. Counter and debug-input switching contribute to the mode delta. Core hierarchy power is Vivado-attributed power inside this instrumented design, not an electrically isolated core measurement. No PS7/ARM workload is instantiated. Regulators and off-chip board power are excluded.", "", "The JTAG simulation boundary is initialized before measurement then held idle. Vivado 2018.1 rejects the requested zero-TCK override and retains the original 33 ns timing-clock model (30.30 MHz). Its JTAG clock power therefore does not represent the constant TCK waveform. Other clocks also use the original routed timing constraints.", "", "Junction temperature is fixed at 25 C, typical process and nominal voltages. Requested ambient is 25 C; the effective reported environment is preserved per case. Activity is mapped functional simulation without routing-delay glitches. Display resolution is 1 nW and is not model accuracy.", "", f"Checkpoint SHA-256: `{result['checkpoint_sha256']}`", ""]
    with (root / "summary.md").open("x") as stream:
        stream.write("\n".join(lines))
    print(f"BOARD_POWER_SUMMARY_PASS {root / 'summary.json'}")


if __name__ == "__main__":
    main()
