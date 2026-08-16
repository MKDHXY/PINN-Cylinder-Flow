from pathlib import Path
import csv
import re
import sys
import json
import random
import shutil
from datetime import datetime

PACKAGE_DIR = Path.cwd()
VTK_DIR = PACKAGE_DIR / "VTK"
READY_DIR = PACKAGE_DIR / "PINN_READY_Re200"

FULL_DIR = READY_DIR / "01_full_field_csv"
TRAIN_DIR = READY_DIR / "02_train"
VAL_DIR = READY_DIR / "03_validation"
TEST_DIR = READY_DIR / "04_test"
META_DIR = READY_DIR / "05_metadata"
CODE_DIR = READY_DIR / "06_code"

CASE_NAME = "cylinderKarmanRe200_trueD_20260815_0216"

TRAIN_RATIO = 0.10
VAL_RATIO = 0.10
TEST_RATIO = 0.80
SEED = 1234

RE = 200
U_INLET = 0.015
D = 0.1
NU = 7.5e-06


def is_number(s):
    try:
        float(s)
        return True
    except Exception:
        return False


def extract_time(path):
    stem = path.stem

    m = re.search(r"_([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$", stem)
    if m:
        return float(m.group(1))

    for part in reversed(path.parts):
        if is_number(part):
            return float(part)

    nums = re.findall(r"[0-9]+(?:\.[0-9]+)?", stem)
    if nums:
        return float(nums[-1])

    raise ValueError("Cannot extract time from " + str(path))


def read_tuples(tokens, i, n_tuple, n_comp):
    total = n_tuple * n_comp
    vals = tokens[i:i + total]

    if len(vals) < total:
        raise ValueError("Unexpected end of VTK file")

    if n_comp == 1:
        data = [float(v) for v in vals]
    else:
        data = []
        for k in range(n_tuple):
            start = k * n_comp
            data.append(tuple(float(v) for v in vals[start:start + n_comp]))

    return data, i + total


def cell_centres(points, cells):
    centres = []

    for cell in cells:
        sx = 0.0
        sy = 0.0
        sz = 0.0
        n = len(cell)

        for pid in cell:
            x, y, z = points[pid]
            sx += x
            sy += y
            sz += z

        centres.append((sx / n, sy / n, sz / n))

    return centres


def parse_vtk(path):
    text = path.read_text(errors="ignore")
    tokens = text.split()

    points = None
    cells = None
    cell_fields = {}
    point_fields = {}

    active_section = None
    active_count = None

    i = 0
    n_tokens = len(tokens)

    while i < n_tokens:
        tok = tokens[i]

        if tok == "POINTS":
            n_points = int(tokens[i + 1])
            i += 3

            pts = []
            for _ in range(n_points):
                pts.append((float(tokens[i]), float(tokens[i + 1]), float(tokens[i + 2])))
                i += 3

            points = pts
            continue

        if tok == "CELLS":
            n_cells = int(tokens[i + 1])
            i += 3

            cls = []
            for _ in range(n_cells):
                k = int(tokens[i])
                ids = [int(v) for v in tokens[i + 1:i + 1 + k]]
                cls.append(ids)
                i += 1 + k

            cells = cls
            continue

        if tok == "CELL_TYPES":
            n_types = int(tokens[i + 1])
            i += 2 + n_types
            continue

        if tok == "CELL_DATA":
            active_section = "CELL_DATA"
            active_count = int(tokens[i + 1])
            i += 2
            continue

        if tok == "POINT_DATA":
            active_section = "POINT_DATA"
            active_count = int(tokens[i + 1])
            i += 2
            continue

        if tok == "VECTORS":
            name = tokens[i + 1]
            i += 3
            data, i = read_tuples(tokens, i, active_count, 3)

            if active_section == "CELL_DATA":
                cell_fields[name] = data
            elif active_section == "POINT_DATA":
                point_fields[name] = data

            continue

        if tok == "SCALARS":
            name = tokens[i + 1]

            if i + 3 < n_tokens and tokens[i + 3].isdigit():
                n_comp = int(tokens[i + 3])
                i += 4
            else:
                n_comp = 1
                i += 3

            if i < n_tokens and tokens[i] == "LOOKUP_TABLE":
                i += 2

            data, i = read_tuples(tokens, i, active_count, n_comp)

            if active_section == "CELL_DATA":
                cell_fields[name] = data
            elif active_section == "POINT_DATA":
                point_fields[name] = data

            continue

        if tok == "FIELD":
            n_arrays = int(tokens[i + 2])
            i += 3

            for _ in range(n_arrays):
                name = tokens[i]
                n_comp = int(tokens[i + 1])
                n_tuple = int(tokens[i + 2])
                i += 4

                data, i = read_tuples(tokens, i, n_tuple, n_comp)

                if active_section == "CELL_DATA":
                    cell_fields[name] = data
                elif active_section == "POINT_DATA":
                    point_fields[name] = data

            continue

        i += 1

    if points is None:
        raise ValueError("No POINTS found in " + str(path))

    if "U" in cell_fields and "p" in cell_fields:
        if cells is None:
            raise ValueError("CELL_DATA exists but CELLS missing in " + str(path))

        coords = cell_centres(points, cells)
        U = cell_fields["U"]
        p = cell_fields["p"]
        location = "cell"

    elif "U" in point_fields and "p" in point_fields:
        coords = points
        U = point_fields["U"]
        p = point_fields["p"]
        location = "point"

    else:
        raise ValueError("Cannot find U and p in " + str(path))

    if len(coords) != len(U) or len(coords) != len(p):
        raise ValueError("Length mismatch in " + str(path))

    return coords, U, p, location


def main():
    if not VTK_DIR.exists():
        print("ERROR: VTK folder not found:")
        print(VTK_DIR)
        sys.exit(1)

    if READY_DIR.exists():
        shutil.rmtree(READY_DIR)

    for d in [FULL_DIR, TRAIN_DIR, VAL_DIR, TEST_DIR, META_DIR, CODE_DIR]:
        d.mkdir(parents=True, exist_ok=True)

    vtk_files = []
    for p in VTK_DIR.glob("*.vtk"):
        lower_parts = [x.lower() for x in p.parts]
        if "boundary" in lower_parts:
            continue
        vtk_files.append(p)

    vtk_files = sorted(vtk_files, key=lambda f: (extract_time(f), str(f)))

    if not vtk_files:
        print("ERROR: no internal vtk files found")
        sys.exit(1)

    full_csv = FULL_DIR / "Re200_full_xyt_uvp.csv"
    train_csv = TRAIN_DIR / "train_sparse_10_Re200.csv"
    val_csv = VAL_DIR / "val_sparse_10_Re200.csv"
    test_csv = TEST_DIR / "test_remaining_80_Re200.csv"

    random.seed(SEED)

    total_rows = 0
    train_rows = 0
    val_rows = 0
    test_rows = 0
    time_summary = []

    print("==========================================")
    print("Converting VTK to PINN-ready CSV")
    print("==========================================")
    print("Package:", PACKAGE_DIR)
    print("VTK files:", len(vtk_files))
    print()

    with full_csv.open("w", newline="") as f_full, \
         train_csv.open("w", newline="") as f_train, \
         val_csv.open("w", newline="") as f_val, \
         test_csv.open("w", newline="") as f_test:

        writer_full = csv.writer(f_full)
        writer_train = csv.writer(f_train)
        writer_val = csv.writer(f_val)
        writer_test = csv.writer(f_test)

        header = ["x", "y", "t", "u", "v", "p"]

        writer_full.writerow(header)
        writer_train.writerow(header)
        writer_val.writerow(header)
        writer_test.writerow(header)

        for vtk_file in vtk_files:
            try:
                t_value = extract_time(vtk_file)
                coords, U, p, location = parse_vtk(vtk_file)

                rows = []
                for xyz, uvw, pp in zip(coords, U, p):
                    x, y, z = xyz
                    u, v, w = uvw
                    rows.append([x, y, t_value, u, v, pp])

                random.shuffle(rows)

                n = len(rows)
                n_train = int(TRAIN_RATIO * n)
                n_val = int(VAL_RATIO * n)

                train_part = rows[:n_train]
                val_part = rows[n_train:n_train + n_val]
                test_part = rows[n_train + n_val:]

                writer_full.writerows(rows)
                writer_train.writerows(train_part)
                writer_val.writerows(val_part)
                writer_test.writerows(test_part)

                total_rows += n
                train_rows += len(train_part)
                val_rows += len(val_part)
                test_rows += len(test_part)

                time_summary.append({
                    "time": t_value,
                    "rows_total": n,
                    "rows_train": len(train_part),
                    "rows_validation": len(val_part),
                    "rows_test": len(test_part),
                    "field_location": location,
                    "vtk_file": str(vtk_file.relative_to(PACKAGE_DIR))
                })

                print(
                    "time=", t_value,
                    " total=", n,
                    " train=", len(train_part),
                    " val=", len(val_part),
                    " test=", len(test_part),
                    " field=", location
                )

            except Exception as e:
                print("SKIP:", vtk_file)
                print("REASON:", e)

    for name in ["log.checkMesh", "log.yPlus", "log.foamToVTK", "log.vorticity", "README_PINN.txt"]:
        src = PACKAGE_DIR / name
        if src.exists():
            shutil.copy2(src, META_DIR / name)

    for folder_name in ["constant", "system", "postProcessing"]:
        src = PACKAGE_DIR / folder_name
        dst = META_DIR / folder_name
        if src.exists():
            shutil.copytree(src, dst, dirs_exist_ok=True)

    shutil.copy2(Path(__file__), CODE_DIR / "make_pinn_ready_dataset_simple.py")

    time_values = [item["time"] for item in time_summary]

    manifest = {
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "case_name": CASE_NAME,
        "description": "PINN-ready OpenFOAM Re200 cylinder-flow dataset",
        "physical_problem": "2D unsteady incompressible flow over a circular cylinder",
        "reynolds_number": RE,
        "u_inlet": U_INLET,
        "cylinder_diameter": D,
        "kinematic_viscosity": NU,
        "reynolds_number_formula": "Re = U_inlet * D / nu",
        "data_format": "CSV space-time point cloud",
        "columns": ["x", "y", "t", "u", "v", "p"],
        "pinn_input": ["x", "y", "t"],
        "pinn_output": ["u", "v", "p"],
        "split_strategy": "For every time step, randomly split spatial points into train, validation and test.",
        "train_ratio": TRAIN_RATIO,
        "validation_ratio": VAL_RATIO,
        "test_ratio": TEST_RATIO,
        "random_seed": SEED,
        "time_min": min(time_values) if time_values else None,
        "time_max": max(time_values) if time_values else None,
        "number_of_time_steps": len(time_values),
        "total_rows": total_rows,
        "train_rows": train_rows,
        "validation_rows": val_rows,
        "test_rows": test_rows,
        "files": {
            "full_csv": "01_full_field_csv/Re200_full_xyt_uvp.csv",
            "train_csv": "02_train/train_sparse_10_Re200.csv",
            "validation_csv": "03_validation/val_sparse_10_Re200.csv",
            "test_csv": "04_test/test_remaining_80_Re200.csv",
            "metadata": "05_metadata",
            "code": "06_code/make_pinn_ready_dataset_simple.py"
        },
        "time_summary": time_summary
    }

    (META_DIR / "dataset_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    with (META_DIR / "split_summary.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["set", "rows", "ratio", "description"])
        writer.writerow(["full", total_rows, 1.0, "Full OpenFOAM CFD point-cloud data"])
        writer.writerow(["train", train_rows, TRAIN_RATIO, "Sparse CFD observations used for PINN data loss"])
        writer.writerow(["validation", val_rows, VAL_RATIO, "Unseen points used for validation during model selection"])
        writer.writerow(["test", test_rows, TEST_RATIO, "Hidden remaining points used for final OpenFOAM comparison"])

    readme_lines = [
        "# PINN-ready Re200 cylinder-flow dataset",
        "",
        "This folder is prepared for another computer or another AI assistant.",
        "",
        "Original OpenFOAM case:",
        CASE_NAME,
        "",
        "Physical problem:",
        "2D unsteady incompressible flow over a circular cylinder.",
        "",
        "Parameters:",
        "Re = " + str(RE),
        "U_inlet = " + str(U_INLET) + " m/s",
        "D = " + str(D) + " m",
        "nu = " + str(NU) + " m^2/s",
        "Re = U_inlet * D / nu",
        "",
        "Main data format:",
        "Each CSV row is:",
        "x, y, t, u, v, p",
        "",
        "PINN input:",
        "x, y, t",
        "",
        "PINN output:",
        "u, v, p",
        "",
        "Neural network mapping:",
        "NN(x, y, t) = [u, v, p]",
        "",
        "Folder structure:",
        "01_full_field_csv/Re200_full_xyt_uvp.csv",
        "02_train/train_sparse_10_Re200.csv",
        "03_validation/val_sparse_10_Re200.csv",
        "04_test/test_remaining_80_Re200.csv",
        "05_metadata/dataset_manifest.json",
        "05_metadata/split_summary.csv",
        "05_metadata/constant",
        "05_metadata/system",
        "05_metadata/postProcessing",
        "06_code/make_pinn_ready_dataset_simple.py",
        "",
        "Dataset split:",
        "For each OpenFOAM time value:",
        "10 percent spatial points -> training set",
        "10 percent spatial points -> validation set",
        "80 percent spatial points -> test set",
        "",
        "This is a sparse full-field reconstruction split, not a time-extrapolation split.",
        "",
        "Training set:",
        "02_train/train_sparse_10_Re200.csv",
        "Used in PINN data loss.",
        "",
        "Validation set:",
        "03_validation/val_sparse_10_Re200.csv",
        "Not used for gradient-based training. Used for model selection.",
        "",
        "Test set:",
        "04_test/test_remaining_80_Re200.csv",
        "Not used during training. Used for final comparison with OpenFOAM.",
        "",
        "Full field:",
        "01_full_field_csv/Re200_full_xyt_uvp.csv",
        "Complete OpenFOAM exported field.",
        "",
        "Python loading example:",
        "import pandas as pd",
        "train_df = pd.read_csv('02_train/train_sparse_10_Re200.csv')",
        "val_df = pd.read_csv('03_validation/val_sparse_10_Re200.csv')",
        "test_df = pd.read_csv('04_test/test_remaining_80_Re200.csv')",
        "X_train = train_df[['x','y','t']].values",
        "Y_train = train_df[['u','v','p']].values",
        "",
        "Dataset size:",
        "Time range: " + str(min(time_values) if time_values else None) + " to " + str(max(time_values) if time_values else None),
        "Number of time steps: " + str(len(time_values)),
        "Full rows: " + str(total_rows),
        "Train rows: " + str(train_rows),
        "Validation rows: " + str(val_rows),
        "Test rows: " + str(test_rows),
        "",
        "Important note:",
        "The main PINN data are x, y, t, u, v, p.",
        "postProcessing/forceCoeffs.dat is not the main training data.",
        "It is only used for checking Cd, Cl and vortex-shedding behaviour.",
        "",
        "Caveat:",
        "If the time range is short, this dataset is suitable for testing the data-processing and PINN pipeline.",
        "For final Karman vortex reconstruction, a longer OpenFOAM simulation with several shedding cycles is recommended.",
        ""
    ]

    (READY_DIR / "README_FOR_OTHER_AI.md").write_text("\n".join(readme_lines), encoding="utf-8")

    zip_path = shutil.make_archive(
        str(PACKAGE_DIR / "PINN_READY_Re200"),
        "zip",
        root_dir=PACKAGE_DIR,
        base_dir="PINN_READY_Re200"
    )

    print()
    print("==========================================")
    print("DONE")
    print("==========================================")
    print("PINN-ready folder:")
    print(READY_DIR)
    print()
    print("ZIP package:")
    print(zip_path)
    print()
    print("Summary:")
    print("Full rows:      ", total_rows)
    print("Train rows:     ", train_rows)
    print("Validation rows:", val_rows)
    print("Test rows:      ", test_rows)
    print("Time steps:     ", len(time_values))
    print("Time range:     ", min(time_values) if time_values else None, "to", max(time_values) if time_values else None)
    print("==========================================")


if __name__ == "__main__":
    main()
