# CFD

CFD results are organized by Reynolds number. Keep the same structure for each Reynolds-number case.

- `CASE/` — CFD/OpenFOAM setup files such as `constant/`, `system/`, and the `.foam` launcher file.
- `VTK/` — selected VTK exports used for inspection or comparison.
- `VTK_GIF/` — GIF animations generated from VTK or field data.
- `POSTPROCESSING/` — compact post-processing outputs such as force coefficients, probes, y+, and derived quantities.
- `SCRIPTS/` — Python, shell, or other helper scripts used to prepare, convert, or package data.
- `LOGS/` — solver and utility logs such as `log.blockMesh`, `log.checkMesh`, and `log.foamToVTK`.

Current CFD cases:

- `RE100/`
- `RE200/`
- `RE3900/`

PINN-ready datasets should be stored separately under `DATA/REXXX/PINN_READY/` so the CFD setup and the machine-learning input data remain clearly separated.

Do not commit very large raw transient flow fields, full time-step VTK datasets, or large archive duplicates. Keep those on local/HPC/cloud storage and commit only selected or processed outputs needed for reproducibility.
