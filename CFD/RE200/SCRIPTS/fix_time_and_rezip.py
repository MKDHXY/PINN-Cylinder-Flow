from pathlib import Path
import csv
import json
import shutil
from datetime import datetime

# ============================================================
# Paths
# ============================================================

BASE = Path.cwd()
READY = BASE / "PINN_READY_Re200"

FULL_CSV = READY / "01_full_field_csv" / "Re200_full_xyt_uvp.csv"
TRAIN_CSV = READY / "02_train" / "train_sparse_10_Re200.csv"
VAL_CSV = READY / "03_validation" / "val_sparse_10_Re200.csv"
TEST_CSV = READY / "04_test" / "test_remaining_80_Re200.csv"

META_DIR = READY / "05_metadata"
MANIFEST_PATH = META_DIR / "dataset_manifest.json"
SUMMARY_PATH = META_DIR / "split_summary.csv"
README_PATH = READY / "README_FOR_OTHER_AI.md"

ZIP_PATH = BASE / "PINN_READY_Re200.zip"

# foamToVTK filename encoding correction:
# 1000000 -> 10.0
# 995000  -> 9.95
# 5000    -> 0.05
TIME_SCALE = 100000.0


# ============================================================
# Helper functions
# ============================================================

def check_required_files():
    required = [FULL_CSV, TRAIN_CSV, VAL_CSV, TEST_CSV]

    missing = [str(p) for p in required if not p.exists()]

    if missing:
        print("ERROR: Missing required CSV files:")
        for m in missing:
            print("  " + m)
        raise SystemExit(1)

    if not READY.exists():
        print("ERROR: PINN_READY_Re200 folder not found:")
        print(READY)
        raise SystemExit(1)


def correct_time_value(t_old):
    """
    Correct foamToVTK encoded decimal time.

    Examples:
    1000000 -> 10.0
    995000  -> 9.95
    5000    -> 0.05

    If time is already normal, keep it.
    """
    t = float(t_old)

    if abs(t) >= 1000.0:
        return t / TIME_SCALE

    return t


def fix_csv_time(csv_path):
    """
    Read one CSV, correct column t, and overwrite safely.
    """
    tmp_path = csv_path.with_suffix(".tmp.csv")

    n_rows = 0
    t_min = None
    t_max = None

    with csv_path.open("r", newline="", encoding="utf-8") as f_in, \
         tmp_path.open("w", newline="", encoding="utf-8") as f_out:

        reader = csv.DictReader(f_in)
        fieldnames = reader.fieldnames

        if fieldnames is None:
            raise RuntimeError(f"No header found in {csv_path}")

        required_cols = ["x", "y", "t", "u", "v", "p"]
        missing_cols = [c for c in required_cols if c not in fieldnames]

        if missing_cols:
            raise RuntimeError(
                f"CSV {csv_path} is missing columns: {missing_cols}"
            )

        writer = csv.DictWriter(f_out, fieldnames=fieldnames)
        writer.writeheader()

        for row in reader:
            t_new = correct_time_value(row["t"])
            row["t"] = f"{t_new:.10g}"

            writer.writerow(row)

            n_rows += 1

            if t_min is None or t_new < t_min:
                t_min = t_new

            if t_max is None or t_new > t_max:
                t_max = t_new

    tmp_path.replace(csv_path)

    return {
        "path": csv_path,
        "rows": n_rows,
        "time_min": t_min,
        "time_max": t_max,
    }


def count_unique_times(csv_path):
    times = set()

    with csv_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        for row in reader:
            times.add(float(row["t"]))

    return len(times), min(times), max(times)


def update_manifest(results):
    META_DIR.mkdir(parents=True, exist_ok=True)

    full = results["full"]
    train = results["train"]
    val = results["validation"]
    test = results["test"]

    n_times, t_min, t_max = count_unique_times(FULL_CSV)

    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    else:
        manifest = {}

    manifest["updated_at"] = datetime.now().isoformat(timespec="seconds")
    manifest["case_name"] = "cylinderKarmanRe200_trueD_20260815_0216"
    manifest["description"] = "PINN-ready OpenFOAM Re200 cylinder-flow dataset"
    manifest["physical_problem"] = "2D unsteady incompressible flow over a circular cylinder"

    manifest["reynolds_number"] = 200
    manifest["u_inlet"] = 0.015
    manifest["cylinder_diameter"] = 0.1
    manifest["kinematic_viscosity"] = 7.5e-06
    manifest["reynolds_number_formula"] = "Re = U_inlet * D / nu"

    manifest["data_format"] = "CSV space-time point cloud"
    manifest["columns"] = ["x", "y", "t", "u", "v", "p"]
    manifest["pinn_input"] = ["x", "y", "t"]
    manifest["pinn_output"] = ["u", "v", "p"]

    manifest["split_strategy"] = (
        "For every time step, randomly split spatial points into "
        "train, validation and test."
    )

    manifest["train_ratio"] = 0.10
    manifest["validation_ratio"] = 0.10
    manifest["test_ratio"] = 0.80

    manifest["time_min"] = t_min
    manifest["time_max"] = t_max
    manifest["number_of_time_steps"] = n_times

    manifest["total_rows"] = full["rows"]
    manifest["train_rows"] = train["rows"]
    manifest["validation_rows"] = val["rows"]
    manifest["test_rows"] = test["rows"]

    manifest["time_correction_note"] = (
        "foamToVTK encoded decimal OpenFOAM time in filenames. "
        "Time values larger than or equal to 1000 were divided by 100000. "
        "Example: 1000000 -> 10.0, 995000 -> 9.95."
    )

    manifest["files"] = {
        "full_csv": "01_full_field_csv/Re200_full_xyt_uvp.csv",
        "train_csv": "02_train/train_sparse_10_Re200.csv",
        "validation_csv": "03_validation/val_sparse_10_Re200.csv",
        "test_csv": "04_test/test_remaining_80_Re200.csv",
        "metadata": "05_metadata",
    }

    # Also fix time_summary if it exists
    if "time_summary" in manifest and isinstance(manifest["time_summary"], list):
        for item in manifest["time_summary"]:
            if isinstance(item, dict) and "time" in item and item["time"] is not None:
                old_t = float(item["time"])
                item["time"] = correct_time_value(old_t)

    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )

    return manifest


def write_split_summary(results):
    full = results["full"]
    train = results["train"]
    val = results["validation"]
    test = results["test"]

    META_DIR.mkdir(parents=True, exist_ok=True)

    with SUMMARY_PATH.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)

        writer.writerow(["set", "rows", "ratio", "time_min", "time_max", "description"])

        writer.writerow([
            "full",
            full["rows"],
            1.0,
            full["time_min"],
            full["time_max"],
            "Full OpenFOAM CFD point-cloud data",
        ])

        writer.writerow([
            "train",
            train["rows"],
            0.10,
            train["time_min"],
            train["time_max"],
            "Sparse CFD observations used for PINN data loss",
        ])

        writer.writerow([
            "validation",
            val["rows"],
            0.10,
            val["time_min"],
            val["time_max"],
            "Unseen points used for validation during model selection",
        ])

        writer.writerow([
            "test",
            test["rows"],
            0.80,
            test["time_min"],
            test["time_max"],
            "Hidden remaining points used for final OpenFOAM comparison",
        ])


def write_readme(results, manifest):
    full = results["full"]
    train = results["train"]
    val = results["validation"]
    test = results["test"]

    readme = f"""# PINN-ready Re200 cylinder-flow dataset

This folder is prepared for another computer or another AI assistant.

Original OpenFOAM case:

cylinderKarmanRe200_trueD_20260815_0216

## 1. Physical problem

Two-dimensional unsteady incompressible flow over a circular cylinder.

Parameters:

Re = 200
U_inlet = 0.015 m/s
D = 0.1 m
nu = 7.5e-06 m^2/s
Re = U_inlet * D / nu

## 2. Main data format

All data are stored as CSV space-time point-cloud data.

Each row is:

x, y, t, u, v, p

Meaning:

x = x coordinate
y = y coordinate
t = physical OpenFOAM time
u = x velocity from OpenFOAM
v = y velocity from OpenFOAM
p = OpenFOAM incompressible pressure / kinematic pressure

PINN input:

x, y, t

PINN output:

u, v, p

Therefore the neural network represents:

NN(x, y, t) = [u, v, p]

## 3. Folder structure

PINN_READY_Re200
|
|-- 01_full_field_csv
|   |-- Re200_full_xyt_uvp.csv
|
|-- 02_train
|   |-- train_sparse_10_Re200.csv
|
|-- 03_validation
|   |-- val_sparse_10_Re200.csv
|
|-- 04_test
|   |-- test_remaining_80_Re200.csv
|
|-- 05_metadata
|   |-- dataset_manifest.json
|   |-- split_summary.csv
|   |-- constant
|   |-- system
|   |-- postProcessing
|
|-- 06_code
|   |-- make_pinn_ready_dataset_simple.py
|
|-- README_FOR_OTHER_AI.md

## 4. Dataset split

The split is performed inside every time step.

For each OpenFOAM time value:

10 percent spatial points -> training set
10 percent spatial points -> validation set
80 percent spatial points -> test set

This is a sparse full-field reconstruction split, not a time-extrapolation split.

Purpose:

sparse CFD observations + Navier-Stokes physics
-> reconstruct full velocity and pressure fields

## 5. Meaning of each set

Training set:

02_train/train_sparse_10_Re200.csv

Used in the PINN data loss. The model is allowed to see these sparse OpenFOAM observations.

Validation set:

03_validation/val_sparse_10_Re200.csv

Not used for gradient-based training. Used to monitor validation error and choose hyperparameters.

Test set:

04_test/test_remaining_80_Re200.csv

Not used during training or model selection. Used only for final comparison with the OpenFOAM reference field.

Full field:

01_full_field_csv/Re200_full_xyt_uvp.csv

Complete OpenFOAM exported field. Useful for plotting CFD reference and final full-field comparison.

## 6. Dataset size after time correction

Time range: {full["time_min"]} to {full["time_max"]}
Number of time steps: {manifest["number_of_time_steps"]}

Full rows: {full["rows"]}
Train rows: {train["rows"]}
Validation rows: {val["rows"]}
Test rows: {test["rows"]}

## 7. Time correction note

The original foamToVTK filenames encoded decimal OpenFOAM time using integer-like values.

Examples:

1000000 -> t = 10.0
995000  -> t = 9.95
5000    -> t = 0.05

Therefore, all CSV time values larger than or equal to 1000 were divided by 100000.

The corrected dataset time range is:

t = {full["time_min"]} to {full["time_max"]}

## 8. Python loading example

import pandas as pd

train_df = pd.read_csv("02_train/train_sparse_10_Re200.csv")
val_df = pd.read_csv("03_validation/val_sparse_10_Re200.csv")
test_df = pd.read_csv("04_test/test_remaining_80_Re200.csv")

X_train = train_df[["x", "y", "t"]].values
Y_train = train_df[["u", "v", "p"]].values

X_val = val_df[["x", "y", "t"]].values
Y_val = val_df[["u", "v", "p"]].values

X_test = test_df[["x", "y", "t"]].values
Y_test = test_df[["u", "v", "p"]].values

## 9. Important note

The main PINN data are:

x, y, t, u, v, p

The files in postProcessing, such as forceCoeffs.dat, are not the main PINN training data.
They are only used to check Cd, Cl and vortex-shedding behaviour.

## 10. Caveat

This dataset currently covers t = {full["time_min"]} to {full["time_max"]}.
It is suitable for testing the data-processing and PINN pipeline.

For final Karman-vortex reconstruction, a longer OpenFOAM simulation with several vortex-shedding cycles is recommended.
"""

    README_PATH.write_text(readme, encoding="utf-8")


def recreate_zip():
    if ZIP_PATH.exists():
        ZIP_PATH.unlink()

    zip_path = shutil.make_archive(
        str(BASE / "PINN_READY_Re200"),
        "zip",
        root_dir=BASE,
        base_dir="PINN_READY_Re200",
    )

    return zip_path


# ============================================================
# Main
# ============================================================

def main():
    print("==========================================")
    print("Fixing time column and recreating ZIP")
    print("==========================================")
    print("Base folder:")
    print(BASE)
    print()

    check_required_files()

    results = {}

    print("Correcting CSV time columns...")
    print()

    results["full"] = fix_csv_time(FULL_CSV)
    results["train"] = fix_csv_time(TRAIN_CSV)
    results["validation"] = fix_csv_time(VAL_CSV)
    results["test"] = fix_csv_time(TEST_CSV)

    for key, info in results.items():
        print(f"{key}:")
        print(f"  file = {info['path']}")
        print(f"  rows = {info['rows']}")
        print(f"  time = {info['time_min']} to {info['time_max']}")
        print()

    print("Updating metadata...")
    manifest = update_manifest(results)
    write_split_summary(results)
    write_readme(results, manifest)

    print("Recreating ZIP package...")
    zip_path = recreate_zip()

    print()
    print("==========================================")
    print("DONE")
    print("==========================================")
    print("Corrected PINN-ready folder:")
    print(READY)
    print()
    print("Corrected ZIP package:")
    print(zip_path)
    print()
    print("Final summary:")
    print(f"Full rows:       {results['full']['rows']}")
    print(f"Train rows:      {results['train']['rows']}")
    print(f"Validation rows: {results['validation']['rows']}")
    print(f"Test rows:       {results['test']['rows']}")
    print(f"Time steps:      {manifest['number_of_time_steps']}")
    print(f"Time range:      {manifest['time_min']} to {manifest['time_max']}")
    print("==========================================")


if __name__ == "__main__":
    main()
