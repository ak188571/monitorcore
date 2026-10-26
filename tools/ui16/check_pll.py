"""Check the three Gowin PLL representations and their output frequencies."""

from __future__ import annotations

import argparse
import configparser
import re
from pathlib import Path


FIELDS = {
    "IDIV_SEL": ("ClkinDividerFactorStaticValue", "idiv_sel"),
    "FBDIV_SEL": ("ClkfbDivideFactorStaticValue", "fbdiv_sel"),
    "MDIV_SEL": ("ClkfboutVCODivideFactorStaticValue", "mdiv_sel"),
    "MDIV_FRAC_SEL": ("ClkfboutVCOFractionalDivideFactorStaticValue", "mdiv_frac_sel"),
    "ODIV0_SEL": ("Clkout0VCODivideFactorStaticValue", "odiv0_sel"),
    "ODIV0_FRAC_SEL": ("Clkout0VCOFractionalDivideFactorStaticValue", "odiv0_frac_sel"),
    "ODIV1_SEL": ("Clkout1VCODivideFactorStaticValue", "odiv1_sel"),
}


def check(root: Path, name: str, outputs: tuple[float, ...]) -> list[str]:
    directory = root / "src" / "pll"
    verilog = (directory / f"{name}.v").read_text(encoding="utf-8")
    config = configparser.ConfigParser()
    config.optionxform = str
    config.read(directory / f"{name}.ipc", encoding="utf-8")
    mod = (directory / f"{name}.mod").read_text(encoding="utf-8")
    errors: list[str] = []
    values: dict[str, int] = {}
    fields = {k: v for k, v in FIELDS.items() if k != "ODIV1_SEL" or len(outputs) > 1}
    for field, (ipc_key, mod_key) in fields.items():
        match = re.search(rf"defparam PLL_inst\.{field} = (\d+);", verilog)
        mod_match = re.search(rf"(?m)^-{mod_key} (\d+)\s*$", mod)
        if not match or not mod_match or ipc_key not in config["Config"]:
            errors.append(f"{name}: {field} is missing")
            continue
        v, i, m = int(match.group(1)), int(config["Config"][ipc_key]), int(mod_match.group(1))
        values[field] = v
        if v != i or v != m:
            errors.append(f"{name}: {field}: Verilog={v}, IPC={i}, MOD={m}")

    match = re.search(r'defparam PLL_inst\.FCLKIN = "([\d.]+)";', verilog)
    mod_match = re.search(r"(?m)^-fclkin ([\d.]+)\s*$", mod)
    if not match or not mod_match:
        errors.append(f"{name}: input frequency is missing")
        return errors
    fclkin = float(match.group(1))
    if fclkin != float(config["Config"]["ClkinClockFrequency"]) or fclkin != float(mod_match.group(1)):
        errors.append(f"{name}: FCLKIN differs across Verilog, IPC, MOD")
    if len(values) != len(fields):
        return errors

    vco = fclkin * values["FBDIV_SEL"] * (values["MDIV_SEL"] + values["MDIV_FRAC_SEL"] / 8) / values["IDIV_SEL"]
    print(f"{name}: VCO={vco:.3f} MHz", end="")
    if not 650 <= vco <= 1300:
        errors.append(f"{name}: VCO outside 650..1300 MHz")
    for index, expected in enumerate(outputs):
        divider = values[f"ODIV{index}_SEL"]
        if index == 0:
            divider += values["ODIV0_FRAC_SEL"] / 8
        output = vco / divider
        print(f", OUT{index}={output:.3f} MHz", end="")
        if abs(output - expected) > 0.0001:
            errors.append(f"{name}: OUT{index} is {output:.3f}, expected {expected:.3f} MHz")
    print()
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("monitor", type=Path)
    args = parser.parse_args()
    errors = check(args.monitor, "pll_27", (27.0,))
    errors += check(args.monitor, "pll_74", (74.25, 371.25))
    for error in errors:
        print("ERROR:", error)
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
