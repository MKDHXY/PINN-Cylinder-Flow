# CFD

CFD results are organized primarily by Reynolds number. Each Reynolds-number case should keep its own simulation setup and lightweight visualization outputs together.

Suggested structure:

- `re100/`
  - `case/` — CFD setup files
  - `vtk/` — selected VTK exports
  - `gifs/` — animations generated from VTK/field data
  - `plots/` — drag/lift/pressure/velocity plots
  - `processed/` — compact CSV or probe data
- `re3900/`
  - `case/`
  - `vtk/`
  - `gifs/`
  - `plots/`
  - `processed/`

Do not commit very large raw transient CFD fields or every time-step VTK file. Keep only selected/processed outputs in GitHub and store full raw simulation data on local/HPC/cloud storage.
