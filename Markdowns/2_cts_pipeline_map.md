# CTS Pipeline Map (code-derived)

## 1) ASCII pipeline diagram

```text
input structures
  (.pdb/.pdb1/.cif/.mmcif/.mat/.mrc)
        |
        v
voxel model (model-space)
  cts.vol + cts.splitmodel + model .mrc/.mat
        |
        v
tilt projections (projection-space)
  xyzproj -> 1_tilt*.mrc
        |
        v
dose / CTF modulation (projection-space)
  helper_electrondetect + helper_ctf -> 2_*/3_*/4_*.mrc
        |
        v
reconstructed tomogram (reconstruction-space)
  tilt + trimvol -> 5_recon*.mrc
        |
        v
atlas / labels (label-space)
  helper_particleatlas -> Atlas*.mrc + Atlas*.txt (+optional ind*.mrc/.tbl)
```

## 2) Arrow-by-arrow mapping (functions, inputs, outputs, formats)

### Arrow A: input structures -> voxel model
- Functions:
  - `param_model` (`/home/nataliya/cryotomosim_CTS/param_model.m`)
  - `helper_input` (`/home/nataliya/cryotomosim_CTS/helper_input.m`)
  - `helper_pdb2vol` (`/home/nataliya/cryotomosim_CTS/helper_pdb2vol.m`)
  - `cts_model` (`/home/nataliya/cryotomosim_CTS/cts_model.m`)
  - inside `cts_model`: `gen_carbon`, `gen_memvol`, `helper_constraints`, `helper_randomfill`, `gen_beads`, `gen_ice`
- Main inputs:
  - Structure files (`.pdb/.pdb1/.cif/.mmcif/.mat/.mrc`) selected via `helper_input`
  - Model box array `vol` (typically `zeros(x,y,z)`)
  - Model params struct (`pix`, `layers`, `density`, `iters`, `grid`, `mem`, `beads`, `ice`, `constraint`, etc.)
- Main outputs (in memory):
  - `cts` struct with `cts.vol`, `cts.model`, `cts.splitmodel`, `cts.list`, `cts.param`
- File formats used:
  - Inputs: `.pdb`, `.pdb1`, `.cif`, `.mmcif`, `.mat`, `.mrc`
  - Intermediate optional cache: `.mat` (from `helper_pdb2vol`, saved next to structure file)
  - Model outputs: `.mrc`, `.mat`, `.log`, `.csv`

### Arrow B: voxel model -> tilt projections
- Functions:
  - `cts_simulate` -> `internal_sim` (`/home/nataliya/cryotomosim_CTS/cts_simulate.m`)
  - external IMOD command: `xyzproj`
- Main inputs:
  - Model file path `sampleMRC` (`.mat` with `cts` preferred, or `.mrc`)
  - Simulation params from `param_simulate` (`tilt`, `tiltax`, `pix`, etc.)
  - `0_model*.mrc`
- Main outputs:
  - `1_tilt*.mrc` (tilt-series projection stack)
  - `tiltanglesT.txt`, `tiltanglesR.txt`
- File formats used:
  - Inputs: `.mat`/`.mrc` model
  - Outputs: `.mrc`, `.txt`

### Arrow C: tilt projections -> dose/CTF
- Functions:
  - `helper_electrondetect` (`/home/nataliya/cryotomosim_CTS/helper_electrondetect.m`)
  - `helper_ctf` -> `math_ctf` (`/home/nataliya/cryotomosim_CTS/helper_ctf.m`, `/home/nataliya/cryotomosim_CTS/math_ctf.m`)
  - Execution order controlled by `opt.ctford` in `cts_simulate`
- Main inputs:
  - `tilt` stack from `1_tilt*.mrc`
  - `dose`, `raddamage`, `scatter`, `defocus`, `voltage`, `aberration`, `sigma`, `ctfoverlap`, `phase`, `tilt` angles
- Main outputs:
  - If `ctford==1`: `2_dosetilt*.mrc` then `3_ctf*.mrc`
  - If `ctford==2`: `3_ctf*.mrc` then `4_dose*.mrc`
  - Always: `2_rad*.mrc` (radiation map)
  - In-memory: `detected`, `convolved`, `ctf`
- File formats used:
  - Input/output: `.mrc`

### Arrow D: dose/CTF -> reconstructed tomogram
- Functions:
  - external IMOD commands in `internal_sim`: `tilt`, then `trimvol`
- Main inputs:
  - Previous projection stack (`3_ctf*.mrc` or `4_dose*.mrc`, depending on `ctford`)
  - `tiltanglesR.txt`
  - Reconstruction geometry (`width`, `thickness` from `param.size`)
- Main outputs:
  - `5_recon*.mrc`
  - temporary `temp.mrc` (deleted after use)
  - in-memory `rec`
- File formats used:
  - Input/output: `.mrc`, `.txt`

### Arrow E: reconstructed tomogram -> atlas / labels
- Functions:
  - `cts_simulate` -> `helper_particleatlas` (`/home/nataliya/cryotomosim_CTS/helper_particleatlas.m`)
  - optional: `generatetable` -> `helper_watershed`
- Main inputs:
  - `cts` struct (from input `.mat` model path), especially `cts.splitmodel`, `cts.model`, `cts.vol`
- Main outputs:
  - `Atlas<suffix>.mrc` (label map)
  - `Atlas<suffix>.txt` (class-name list)
  - Optional: `ind<i>_<name>.mrc` (binary class volumes), `ind<i>_<name>.tbl` (Dynamo tables)
- File formats used:
  - Outputs: `.mrc`, `.txt`, `.tbl`
- `inference`:
  - In the required conceptual diagram this is drawn after reconstruction, but code computes atlas from the model struct (`cts`) and not from `5_recon*.mrc` intensities.

## 3) Exact on-disk outputs by stage and save locations

## Input/conversion stage (pre-model)
- Optional cache written by `helper_pdb2vol`:
  - `<structure_dir>/<structure_basename>.mat`
  - Trigger: `savemat==1` (default through `helper_input`)
  - Space: model preparation

## Model-space outputs (`cts_model`)
- Base output directory:
  - Default: `$HOME/tomosim/`
  - Or `opt.outdir` if provided; or chosen via `uigetdir` when `opt.outdir='gui'`
- Model run folder:
  - `model_<yyyy-MM-ddtHH.mm>_<ident>_pixelsize_<pix><suffix>/`
- Files written in that folder:
  - `<ident><suffix>.mrc` (final voxel model)
  - `<ident><suffix>.mat` (serialized `cts` struct)
  - `cts_param_model.log` (JSON-encoded params)
  - `zcoords_<class>.csv` (one per non-empty class list)
- `inference`:
  - Returned `outfile` path in code is always constructed under `$HOME/tomosim/...` even when `opt.outdir` is custom.

## Projection-space outputs (`cts_simulate` / `internal_sim`)
- Simulation working folder location:
  - Created under directory of input sample file (`path` from `sampleMRC`):
  - `sim_dose_<sum(param.dose)><suffix>/`
- Files:
  - `0_model<suffix>.mrc`
  - `tiltanglesT.txt`
  - `tiltanglesR.txt`
  - `1_tilt<suffix>.mrc`
  - `2_dosetilt<suffix>.mrc` (if `ctford==1`)
  - `2_rad<suffix>.mrc`
  - `3_ctf<suffix>.mrc`
  - `4_dose<suffix>.mrc` (if `ctford==2`)
  - `cts_param_simulate.log`
- Behavior note (directly from code):
  - `delete *.mrc` is executed immediately after entering the run folder.

## Reconstruction-space outputs (`cts_simulate` / IMOD)
- Same simulation folder as above:
  - `5_recon<suffix>.mrc`
  - `temp.mrc` is created then deleted

## Label-space outputs (`helper_particleatlas`)
- Same simulation folder as above (called before `cd(userpath)`):
  - `Atlas<suffix>.mrc`
  - `Atlas<suffix>.txt`
  - Optional when flags enabled:
    - `ind<i>_<roi>.mrc` (`atlasindividual==1`)
    - `ind<i>_<roi>.tbl` (`dynamotable==1`)

## Space separation summary
- Model-space:
  - `cts_model` outputs (`<ident>.mrc/.mat`, `cts_param_model.log`, `zcoords_*.csv`)
- Projection-space:
  - `0_model`, `1_tilt`, `2_*`, `3_ctf`, `4_dose`, `tiltangles*.txt`
- Reconstruction-space:
  - `5_recon*.mrc` (and transient `temp.mrc`)
- Label-space:
  - `Atlas*.mrc/.txt` (+optional `ind*.mrc/.tbl`)

## 4) Scripts close to this task
- `/home/nataliya/cryotomosim_CTS/scripts/cts_demo_script.m`
  - Closest end-to-end single-run driver.
  - Explicitly runs: `param_model` -> `cts_model` -> `param_simulate` -> `cts_simulate`.
  - Comments describe where outputs are saved and atlas behavior for `.mat` vs `.mrc` input.

- `/home/nataliya/cryotomosim_CTS/scripts/trainscript_growthconesegment.m`
  - Practical dataset-generation loop that repeatedly calls `cts_model` and `cts_simulate`.
  - Uses atlas class count (`numel(unique(atlas))`) as a quality check.

- `/home/nataliya/cryotomosim_CTS/scripts/cts_batch_example.m`
  - Batch example invoking `cts_batch`/`param_batch`.
  - `inference`: `cts_batch` and `param_batch` implementations are in `/home/nataliya/cryotomosim_CTS/WIP/`, so running this script may require adding `WIP` to MATLAB path.

## Primary function chain (confirmed from code)
- Model chain:
  - `param_model` -> `helper_input` -> `helper_pdb2vol` -> `cts_model` -> (`gen_carbon`, `gen_memvol`, `helper_constraints`, `helper_randomfill`, `gen_beads`, `gen_ice`) -> model files
- Simulation/reconstruction chain:
  - `param_simulate` -> `cts_simulate` -> `internal_sim` -> `xyzproj` -> (`helper_electrondetect` <-> `helper_ctf`) -> `tilt` -> `trimvol` -> reconstruction files
- Atlas chain:
  - `cts_simulate` -> `helper_particleatlas` -> optional `helper_watershed`/`regionprops3` for `.tbl`
