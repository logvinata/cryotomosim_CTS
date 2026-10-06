# Atlas Labels in the Actin/Cofilactin/MT Simulations

This covers the ground-truth atlas written by `scripts/cts_batch_actin_cofilactin_mt.m` (atomic pipeline) under:

```text
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/<run>/sim/Atlas_sim.mrc
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/<run>/sim/Atlas_sim.txt
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/<run>/zero_dose_pair/Atlas_zero_dose_pair.{mrc,txt}
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/<run>/zcoords_<label>.csv
```

Tools and lists that go with it:

- `scripts/cts_atlas_to_labels.sh` and `scripts/cts_atlas_to_labels.m`: turn the atlases into named labels for Dragonfly, IMOD or segmentation networks.
- `scripts/dragonfly_import_training_runs.py`: loads runs into Dragonfly as tomogram + Multi-ROI training pairs.
- `scripts/run_lists/actin_cofilactin_mt/`: runs grouped by which classes they contain.
- `cts_atomic_pipeline_issues.md`: the code problems behind several quirks below, with suggested fixes.

Confidence words used below:

- **confirmed**: read from the code and the model files, and checked against the simulated data.
- **from name**: the identity is taken from the file name or PDB ID only and was not looked up.
- **unverified**: a guess, stated as such.

## Reading the Atlas

- The value `v` of a voxel in `Atlas_*.mrc` means the label on line `v+1` of `Atlas_*.txt`. Line 1 is `background`, which is value 0. (confirmed)
- `Atlas_*.mrc` is float32 (MRC mode 2) with integer values only. Every row of the `.txt` occurs in the volume.
- The `sim` and `zero_dose_pair` atlases of a run are identical (same atoms). (confirmed)
- The atlas has the same size and pixel size as `5_recon_*.mrc` and overlays it with no shift or flip. This was tested by correlating the atlas mask with the reconstruction on runs 00297 and 00300; the best match is at zero shift. (confirmed)

### The numbering is different in every run

A label exists only if at least one particle of that kind was placed. Labels with no placements are dropped from the list, so all later values shift. Across the 336 runs the `.txt` has between 21 and 66 rows:

| Rows | Runs |
| --- | --- |
| 66 (full membrane-layer list) | 109 |
| 44 (full list without membrane layer) | 124 |
| 52–65 | 59 |
| 21–43 | 44 |

Example: in run 00297 value 23 is `neuroMT`. Run 00300 has no microtubule, and value 23 there is `fix_1EXR`.

**Always map labels by name, never by number.** In 53 runs there is no `neuroMT`; 18 have no `actin_long`, 17 no `cofilactin_long`, 26 no `ribo_4ujd`.

## How the Atlas Is Made

Code path: `cts_batch_actin_cofilactin_mt.m` → `WIP/cts_model_atomic.m` → `WIP/helper_randfill_atom_mem.m` (membrane proteins) and `WIP/helper_randfill_atom.m` (everything else) → `WIP/cts_simulate_atomic.m` → `helper_atoms2vol.m`.

- **Each label is one field of the atomic model's `split` struct.** The field holds all atoms placed under that name. `helper_atoms2vol` bins every label's atoms into voxels, weighted by scattering. Each voxel then gets the label with the largest summed weight. A voxel that contains no atom is 0.
  - The labels are tight: only voxels that contain atoms. Nothing is dilated or smoothed.
  - Unlabelled holes enclosed inside particles amount to about 1–2 % of the labelled volume.
  - On a tie, the label listed first wins.
- **The order of the rows is the order in which fields were created:**
  1. Membrane-protein layer, when present: files from `synthetic_cytoplasm_models/layer 1` whose name contains `membrane`, in ASCII order (so `GABAar…` comes first), then the submodels of each file in file order.
  2. `vesicle`, the lipid bilayer.
  3. The soluble layers in batch order: `neuroMT…`, `actin_long…`, `cofilactin_long…`, `ribo_4ujd…`, then the `layer 3` and `layer 4` `.mat` files in ASCII order.
  4. A name that already exists is merged into the existing label.
- **Label names come from the structure file** (`helper_input.m`, `WIP/helper_pdb2dat.m`):
  - a `.cif` data-block name (`data_…`, with dots removed) if there is one;
  - otherwise the i-th dot-separated part of the file name for submodel i, or the last part when there are more submodels than parts;
  - `fix_` is prefixed to names starting with a digit, and `-` becomes `_`.
- **Flags stay in the name.** Because of the file-name rule, flags such as `.membrane.`, `.cytosol.`, `.complex.` and `.assembly.` can become label names of later submodels. This is where the generic labels `membrane`, `complex`, `cytosol` and `assembly` come from.
- **Most placement flags are ignored.** The atomic fill only uses two flags:
  - `membrane`: the file goes to the membrane-embedding fill.
  - `complex`: all submodels are placed together.
  - `bundle`, `cluster`, `assembly`, `cytosol` and `vesicle` are ignored. Each placement puts ONE random submodel at a random position and rotation. For example, actin filaments are not bundled.

## Label Table (run 00297, 66 rows)

Model files are in `synthetic_cytoplasm_models/`. A run without the membrane layer has the rows from `neuroMT` on, with values lower by 22 (44 rows), unless some labels are missing.

| Value | Name | Source file (submodel) | Meaning | Confidence |
| --- | --- | --- | --- | --- |
| 0 | background | — | voxels with no atoms (solvent/ice) | confirmed |
| 1 | A_5soa | layer 1/GABAar.membrane.complex (block 1 = `origin_OPM`) | **not a protein**: 1946 OPM membrane-boundary dummy atoms (N/O), see Known Artifacts | confirmed |
| 2–5 | B_5soa … E_5soa | GABAar.membrane.complex (blocks A_5soa … D_5soa) | subunits 1–4 of the GABAar pentamer (labels shifted by one; subunit E_5soa is never placed) | confirmed (shift); GABA-A receptor from name |
| 6 | atp_dimer_6rd4 | layer 1/atp_dimer_6rd4.membrane | ATP synthase dimer, PDB 6RD4 | from name |
| 7 | atp_monomer_6rd4 | layer 1/atp_monomer_6rd4.membrane | ATP synthase monomer, PDB 6RD4 | from name |
| 8 | atp_synthase_2x | layer 1/atp_synthase_2x.membrane.complex.pdb (model 1) | 12 identical Gly/Ala-rich chains, probably the c-ring | model content confirmed; c-ring unverified |
| 9 | membrane | atp_synthase_2x (model 2) **and** gprotein.membrane.comlex (model 2) | merged label: the 10-chain second part of atp_synthase_2x (identity unverified) plus the G-protein heterotrimer (Gα/Gβ/Gγ N-terminal sequences) | confirmed (merge); parts' identity partly unverified |
| 10 | complex | atp_synthase_2x (models 3+4) | exact duplicates of models 1+2 at the same coordinates, so almost always hidden behind labels 8/9 (145 voxels in 00297) | confirmed |
| 11 | atp_synthase_dimer_6tmkmembranecif | layer 1/atp_synthase_dimer_6tmk.membrane | ATP synthase dimer, PDB 6TMK | from name |
| 12 | atp_synthase_2xmembranecomplexpdb | layer 1/atp_synthase_dimer_gen.membrane (8 blocks, same name) | generated ATP synthase dimer (blocks named after atp_synthase_2x…pdb) | from name |
| 13 | complex3_5xte | layer 1/complex3_5xte.membrane | respiratory complex III?, PDB 5XTE | from name |
| 14 | fix_6his_5HTpdb | layer 1/fixed_6his_5HT.membrane.complex | 5-HT (serotonin) receptor? | from name, unverified |
| 15 | fix_6lfm_gprotienpdb | layer 1/fixed_6lfm_gprotein.membrane.complex | receptor–G-protein complex, PDB 6LFM | from name |
| 16 | fix_8g2ypdb | layer 1/glob_8g2y.membrane | PDB 8G2Y | from name |
| 17 | glun1 | layer 1/glun1.membrane.complex | NMDA receptor (GluN1) | from name |
| 18 | gprotein | layer 1/gprotein.membrane.comlex (model 1) | 7-TM receptor chain plus small fragments, placed **without** its G protein (the `comlex` typo means it is not treated as a complex) | confirmed |
| 19–21 | state1_8h9s_…, state2_8h9t_…, state3a_8h9u_membrane_y_inverted | layer 1/state*_y_inverted.membrane | PDB 8H9S/8H9T/8H9U, probably ATP synthase rotary states | from name, unverified |
| 22 | vesicle | generated membranes (`WIP/gen_mem_atom.m`, class `vesicle`) | lipid-bilayer pseudo-atoms of the vesicles; lipid within 4 Å of a membrane protein is removed | confirmed |
| 23 | neuroMT | layer 2/neuroMT.cytosol.assembly.pdb (model 1) | microtubule lattice (α-tubulin sequence, 712k atoms) without inner proteins | confirmed |
| 24 | cytosol | neuroMT…pdb (model 2) | 4-chain non-tubulin protein (N-terminus MAWPCITRACCIARFW…, possibly MAP6). Placed as a free particle, not inside microtubules | content confirmed; MAP6 unverified |
| 25 | assembly | neuroMT…pdb (models 3+4) | same protein as `cytosol` | confirmed |
| 26 | actin_long | layer 2/actin_long.bundle.mat | straight actin filament segment (single filaments, no bundles) | confirmed |
| 27 | cofilactin_long | layer 2/cofilactin_long.bundle.pdb | cofilin-decorated actin filament segment | from name |
| 28 | ribo_4ujd | layer 2/ribo_4ujd.cytosol.cluster.mat | ribosome, PDB 4UJD (no clusters) | from name |
| 29 | XXXX | layer 3/ck2_3soa.mat and ck2_3soa.cytosol.mat (cif block `data_XXXX`) | CaMKII holoenzyme, PDB 3SOA | from name |
| 30–45 | fix_1QVR, fix_2DFS, fix_3ULV, fix_5O32, fix_6CNJ, fix_6IGC, fix_6KSP, fix_6M04, fix_6TA5, fix_6U8Q, fix_6XF8, fix_6ZQJ, fix_7BKC, fix_7ETM, fix_7NHS, fix_7SFW | layer 3/fixed_<id>.mat | large cytosolic proteins with these PDB IDs | from name (not looked up) |
| 46 | proteosome_5fmg | layer 3/proteosome_5fmg.cytosol.mat | proteasome, PDB 5FMG | from name |
| 47 | tric_6ks8 | layer 3/tric_6ks8.cytosol.cluster.mat | TRiC/CCT chaperonin, PDB 6KS8 | from name |
| 48 | actin_monomer | layer 4/actin_monomer.vesicle.mat | G-actin | from name |
| 49 | actin_monomer_2q0u | layer 4/actin_monomer_2q0u.cytosol.mat | G-actin, PDB 2Q0U | from name |
| 50 | actinin | layer 4/actinin.cytosol.mat | α-actinin | from name |
| 51 | actinin_1sjj | layer 4/actinin_1sjj.cytosol.mat | α-actinin, PDB 1SJJ | from name |
| 52 | camcytosolcif | layer 4/cam.cytosol.mat **and** cam.vesicle.mat (both blocks `cam.cytosol.cif`) | calmodulin, two files merged into one label | confirmed (merge) |
| 53 | fix_1EXR | layer 4/cam_1exr.cytosol.mat | calmodulin, PDB 1EXR | from name |
| 54–65 | fix_12GS, fix_1QTX, fix_1S3X, fix_2CG9, fix_3GL1, fix_4UIC, fix_5CSA, fix_6VGR, fix_7B5S, fix_7E6G, fix_7SGM, fix_7WBT | layer 4/fixed_<id>.mat | small cytosolic proteins with these PDB IDs | from name (not looked up) |

The PDB IDs can be looked up at `https://www.rcsb.org/structure/<ID>`.

## Coordinate Files

- **`zcoords_<label>.csv`** has one row per placement: x, y, z in Å.
  - Voxel in the atlas/`5_recon` MRC (0-based x, y, z) = `round(c / pixel_size + 0.5) - 1`.
  - Column 1 is MRC x (fastest axis) and column 3 is MRC z (slice). (confirmed)
- **The point is the placement centre**, which is the unweighted mean of the submodel's atom coordinates.
  - Compact proteins: the voxel at the point carries the particle's own label in about 100 % of cases.
  - Hollow or ring-shaped particles (`neuroMT`, `XXXX`, `proteosome_5fmg`, `tric_6ks8`, `fix_6KSP`): the point falls in the cavity, but the label is within about 60 Å (checked for every point in 00297 and 00300).
  - Filaments get one point at the middle of each straight segment, with no direction.
- **Merged labels** (`assembly`, `membrane`, `camcytosolcif`) contain rows from all of their submodels or files.
- **No CSV is written for membrane proteins or for `vesicle`.** (confirmed)
  - **Membrane proteins:** the CSVs are written from `cts.list`, which only holds what the soluble fill returns (`WIP/cts_model_atomic.m:98`, `:146-155`). The membrane fill records every placement too (`WIP/helper_randfill_atom_mem.m:139`, `:148`), but the function returns only `[split,dx,dyn]`, so the list is discarded. This looks like unfinished WIP code. The recording lines were copied from the soluble fill, but the output was never added. (issue 7 in `cts_atomic_pipeline_issues.md`)
  - **Vesicles** are not placed like particles. `WIP/gen_mem_atom.m` grows random blobs and fills a bilayer shell around each one with lipid pseudo-atoms. The blob seeds are not saved.
  - **The positions can be recovered.** `<run>.atom.mat` (about 1 GB, MATLAB v7.3/HDF5) stores every label's atoms in placement order, one consecutive block per placed particle. For a label with a single source model, cutting its atom list into blocks of that model's atom count gives one centre per particle. Vesicles separate as connected components of the `vesicle` label.
- **`zdtable_<label>.tbl`** (Dynamo-style tables) have the same Å coordinates in columns 24–26 and no orientations. Dynamo expects pixels, so divide by the pixel size first.

## Membranes and Vesicles

In these simulations every lipid membrane is a vesicle. `WIP/gen_mem_atom.m:25` defines only that type: closed, nearly round blobs with a bilayer 25 ± 6 Å thick, made of lipid pseudo-atoms. The ER, flat-membrane and mitochondria types are commented out. The word "membrane" is also used for several other things:

| Term | What it is | Class in `labels.mrc` |
| --- | --- | --- |
| `vesicle` (atlas label) | the lipid bilayers | 5 membrane |
| membrane proteins | files with `.membrane` in the name (layer 1: GABA-A receptor, ATP synthases, G protein, GluN1, …). They are inserted into the vesicle surfaces along the surface normal, and lipid within 4 Å of them is removed | background |
| atlas label `membrane` | **protein, not lipid**: the second part of `atp_synthase_2x` plus the G protein of `gprotein`, placed without its receptor. It gets this name from the file-name rule above | background |
| `.vesicle` in a file name (`actin_monomer.vesicle`, `cam.vesicle`) | meant as "place inside vesicles", but the flag is ignored, so these proteins go anywhere; they have nothing to do with the `vesicle` label | background |
| `param.mem`, `actual_membrane_count` | number of vesicles requested or generated, not necessarily present (see below) | — |

- **Vesicles exist only in runs with membrane proteins (168 runs).**
  - Every run asks for vesicles. But the lipids are added to the model at the end of the membrane-protein fill, and that function returns early when no membrane-protein file was chosen (`WIP/helper_randfill_atom_mem.m:20`).
  - So the other 168 runs have no membrane in the tomogram and no `vesicle` label, although `metadata.json` reports `actual_membrane_count` = 6. (confirmed; issue 4)
- In the membrane runs, each vesicle has a 20 % chance of carrying no proteins.
- **To include the embedded proteins in class 5,** add their atlas names to the class definition (`CLASS_ATLAS` in the bash converter, `'classes'` in MATLAB, `CLASSES` in the Dragonfly script). Add the label `membrane` only if you want protein too; it contains no lipid.

## Known Artifacts and Quirks

Their causes in the code, with suggested fixes, are in `cts_atomic_pipeline_issues.md`.

### A_5soa … E_5soa are shifted by one

- `GABAar.membrane.complex` has 6 blocks: `origin_OPM`, then `A_5soa` … `E_5soa`, one per subunit (about 2,560 atoms each).
- **`origin_OPM` is not protein.** It holds 1,946 dummy atoms that mark the two membrane surfaces, as OPM files do. They form two flat sheets on a 2 Å grid, about 70 Å across: 973 "N" at z = −16.5 Å and 973 "O" at z = +14.5 Å.
- **Two loaders read the file and disagree** (`helper_input.m:91-95`):
  - `helper_pdb2vol` supplies the names. It drops blocks whose name contains "origin", leaving 5 names.
  - `helper_pdb2dat` supplies the atoms. It keeps all 6 blocks.
- **The placement pairs them by position**, name u with atom block u (`WIP/helper_randfill_atom_mem.m:129-140`). So:
  - `A_5soa` gets the dummy atoms;
  - `B_5soa` … `E_5soa` get subunits A … D;
  - block 6, the real subunit E, has no name and is never placed.
- **Result:** every simulated receptor is missing a subunit and carries two sheets of N/O atoms that add density to the tomogram. `A_5soa` covers far fewer voxels than a real subunit (668 vs about 1,400 in 00297). (confirmed)
- Only GABAar is affected in this batch. `vatpase.membrane.cif` has the same kind of block but is not used.

### Near-duplicate labels

There are two causes.

**1. Unnamed models get file-name parts as names, and equal names merge.** PDB models have no names of their own, so model i takes the i-th part of the file name (split on `.` and `__`), and extra models reuse the last part. Flags are parts too:

| File | Its models are named |
| --- | --- |
| `neuroMT.cytosol.assembly.pdb` | neuroMT, cytosol, assembly, assembly |
| `atp_synthase_2x.membrane.complex.pdb` | atp_synthase_2x, membrane, complex, complex |
| `gprotein.membrane.comlex.pdb` | gprotein, membrane |

Models with the same name go into one label, so `membrane` mixes parts of two unrelated files. `camcytosolcif` merges two calmodulin files whose cif blocks have the same name.

**2. Some model files contain copies of the same structure.**

- **Microtubule file:**
  - Models 2–4 are three copies of one 35,319-atom protein at different points along the tube, presumably meant to decorate it.
  - The `assembly` flag is ignored, so each placement picks one of the 4 models at random. Three times out of four it places a lone copy of that protein, named `cytosol` or `assembly`.
  - In 00297: 17 microtubules, 138 lone copies (40 `cytosol` + 98 `assembly`). These copies are background in `labels.mrc`.
- **atp_synthase_2x:**
  - Models 3+4 are exact copies of models 1+2. It is probably a dimer whose second half was never moved into position.
  - It is flagged `complex`, so all four models are placed on top of each other, and this particle is simulated at **double density**.
  - `complex` only wins the atlas where the two halves touch (145 voxels in 00297), because ties go to the label listed first.
- **Different structures of the same protein** (`actinin`/`actinin_1sjj`, `camcytosolcif`/`fix_1EXR`, several ATP synthases) are separate input files. That is not a code effect.

### Three runs are broken

- Runs 00008, 00013 and 00015 are 256×256×64 voxels at 1.02–1.47 Å, so the box is only 26–38 nm wide and 6.5–9.4 nm thick.
- Every one of their 17,000 placement attempts succeeded (for example 2,000 ribosomes), and the atlas is 100 % labelled. All other runs are 15–35 % labelled.
- Collision checking is switched off in boxes thinner than about 104 Å (64 slices at less than about 1.62 Å per pixel): the collision index never subdivides its cubes, and the search only looks inside subdivided cubes. So the particles overlap freely. (confirmed by running the collision code; issue 1)
- These are the only runs with pixels below 3.2 Å. The first version of the batch script allowed 0.76–20 Å; the current one allows 3.5–20 Å, so it cannot happen again with the current settings.
- **Do not use these runs.** They are in `overfilled.txt`.

### Missing classes follow the pixel size

- The box is always 64 slices thick, so a small pixel size means a thin box.
- All 55 runs that lack a microtubule, actin, cofilactin or ribosome class have pixel sizes of 3.2–7.4 Å (box 21–47 nm thick), and 53 of them lack the microtubule. Runs with all five classes have 5.5–19.8 Å.
- Large particles probably rarely fit into thin boxes. (unverified)
- A missing class is still valid ground truth: that structure is simply not in the tomogram, so all of its voxels are correctly background.

### Run size varies

15 early runs are 256×256×64 voxels; the rest are 512×512×64. Pixel size is random: 3.2–19.8 Å, or down to 1.0 Å counting the three broken runs. It is stored in `metadata.json` and the MRC headers.

## Run Lists

The lists are in `scripts/run_lists/actin_cofilactin_mt/`. Runs are grouped by which of the five classes their `Atlas_sim.txt` contains:

| File | Runs | Content | Pixel size |
| --- | --- | --- | --- |
| `all5.txt` | 137 | all five classes | 5.5–19.8 Å, all 512×512×64 |
| `no_membrane.txt` | 141 | all except membrane | 4.9–19.8 Å, 9 of them 256×256×64 |
| `middle_missing.txt` | 55 | lacks microtubule, actin, cofilactin or ribosome (and often membrane) | 3.2–7.4 Å |
| `overfilled.txt` | 3 | broken runs 00008, 00013, 00015; do not use | 1.0–1.5 Å |

- `classes_per_run.csv` has one row per run: size, pixel size, number of atlas rows, labelled percentage, 0/1 for each class, group, and missing classes.
- Earlier counts said 144 runs lack only the membrane. That number included the 3 broken runs.

## Making Named Labels Programmatically

The tutorial's Dragonfly route (Extract ROIs → Create Multi-ROI → rename → merge everything else into background) has to be done by hand, run by run, and the numbering differs per run. The two converters below do the same thing by name, with the same class ids in every run:

| id | class | atlas names merged into it |
| --- | --- | --- |
| 0 | background | everything not listed below |
| 1 | microtubule | `neuroMT` |
| 2 | actin | `actin_long` |
| 3 | cofilactin | `cofilactin_long` |
| 4 | ribosome | `ribo_4ujd` |
| 5 | membrane | `vesicle` |

To change the classes, edit `CLASS_ATLAS` (bash) or pass `'classes'` (MATLAB). A class can list several atlas names to merge them, for example `"cytosol assembly"`.

### Outputs (per run, in `<run>/labels/`)

| File | Content |
| --- | --- |
| `labels.mrc` | label volume, unsigned bytes 0–5, same size, pixel size and origin as `Atlas_sim.mrc` / `5_recon_sim.mrc` |
| `mask_<class>.mrc` | 0/1 mask per class (all zeros when the class is absent from the run) |
| `labels.json` | per class: id, name, atlas names and values used, `present`, voxel count, colour, number of CSV points, mask file |
| `particles.mod` | IMOD scattered-point model from the CSVs. Object k = class k, named and coloured, sphere sizes in pixels, coordinates matched to `5_recon_sim.mrc`. The membrane has no points |

The labels apply to both `sim/5_recon_sim.mrc` and `zero_dose_pair/5_recon_zero_dose_pair.mrc`.

### Running

Bash, IMOD only (needs `clip`, `header`, `point2model`):

```bash
scripts/cts_atlas_to_labels.sh /mnt/big_data/CTS_actin_cofilactin_MT_simulation        # all runs
scripts/cts_atlas_to_labels.sh --out /some/dir RUN_DIR [RUN_DIR ...]                    # elsewhere
# --force redo existing, --no-masks, --no-model
```

MATLAB (needs `ReadMRC`/`WriteMRC` on the path; IMOD on the path for `particles.mod`):

```matlab
addpath('/home/nataliya/cryotomosim_CTS/scripts')
cts_atlas_to_labels('/mnt/big_data/CTS_actin_cofilactin_MT_simulation')            % all runs
cts_atlas_to_labels(root,'runs',{'00297','00300'},'outroot','/some/dir','overwrite',1)
```

Both give identical label volumes, masks, JSON content and model points; this was checked on 00297 and 00300 against an independent remap of the atlas.

- **Speed:** about 1.3 s per run in MATLAB (one read and a lookup table) and about 5.4 s per run in bash. Bash needs three `clip` passes per class, but no MATLAB licence.
- **Disk:** about 100 MB per 512×512×64 run with masks, about 17 MB without (`--no-masks` / `'masks',0`).

## Dragonfly

### What Dragonfly's training needs

- The output Multi-ROI must label every voxel. Unlabelled voxels are left out of training, and background counts as one of the classes.
- All training Multi-ROIs need the same classes in the same order, and each must match the size and spacing of its input dataset.
- In Dragonfly 2025.1, Multi-ROI classes are numbered from 1 (taken from Dragonfly's own Python code).

### Import script (recommended)

`scripts/dragonfly_import_training_runs.py` runs in Dragonfly's Python console:

```python
exec(open('/home/nataliya/cryotomosim_CTS/scripts/dragonfly_import_training_runs.py').read())
```

**Settings** at the top of the file:

- `RUN_LISTS`: list files to read, for example `['all5.txt', 'no_membrane.txt']`.
- `FIRST`, `COUNT`: which part of the combined list to load.
- `MODE`: `'pairs'` or `'stack'`.
- `SUB`: `sim` (noisy tomogram) or `zero_dose_pair` (noise-free).
- `MIN_FREE_GB`: RAM to leave free, in GiB.

**How it builds the labels:**

- Labels come straight from the atlas, matched by name, so the converters need not be run first.
- Every Multi-ROI has all six classes in the same order: 1 background, 2 microtubule, 3 actin, 4 cofilactin, 5 ribosome, 6 membrane.
- A class that is absent from a run stays as an empty class in its usual place, so any run list works, including `middle_missing.txt`.

**The two modes:**

- **`pairs`** makes `<run>_tomo` and `<run>_labels` for each run, with the grey values unchanged. Runs already loaded are skipped, so a long list can be loaded in parts.
- **`stack`** puts the listed runs one after another along Z into one tomogram and one Multi-ROI. Use it to avoid adding hundreds of input/output pairs in the Deep Learning Tool.
  - Only runs with the X/Y size of the first run are used.
  - Each run is scaled to mean 0, SD 1, because grey levels differ between runs.
  - The slice range of each run is written to `<STACK_TITLE>_slices.csv` in the list folder.
  - The stack's spacing is that of the first run, because the pixel sizes differ. Training does not use the spacing.
  - With 2.5D/3D models, patches at a junction between runs mix two runs, which affects a few slices out of every 64.
  - Use a second stack built from other runs as validation data.

**Safety checks:**

- After each Multi-ROI is built, the voxel count of every class in Dragonfly is compared with the atlas, and the script stops on a mismatch.
- Runs in `overfilled.txt` are skipped.
- Loading stops before the RAM still available would drop below `MIN_FREE_GB`.

**Status:**

- The Dragonfly calls are the same ones Dragonfly 2025.1's own code uses (Create Multi-ROI from ROIs, its MRC reader, its watershed helper). They were checked against `python/ORSModel/ors.pyi` on this machine.
- The script was run with Dragonfly's Python and a stand-in for those calls on runs 00297 and 00300:
  - class voxel counts were identical to the converters';
  - the tomogram was identical to the MRC;
  - the Multi-ROI and tomogram were on the same grid.
- It has **not** been run inside Dragonfly yet, so start with `COUNT = 2`.

### By hand (for a few runs)

1. Import `5_recon_sim.mrc` and `labels/labels.mrc` (from the converters). Dragonfly reads byte MRCs as signed and may show shifted values, but each class stays one value.
2. Right-click the labels → **Create ROIs from Intensities** (one ROI per value present) → select the ROIs → **Create Multi-ROI from ROIs**. Dragonfly's 2021.3 help also lists **New Greylevel Multi-ROI** for this; I did not confirm it in 2025.1.
3. The class order follows the selected ROIs. Identify classes by the voxel counts in `labels.json`.
4. A class that is missing from a run gets no ROI, so add an empty class at its position.

### Memory and disk

The workstation has 502 GB RAM. Once loaded, a 512×512×64 run takes 64 MiB (tomogram) + 16 MiB (Multi-ROI):

| Runs loaded | Tomograms | Multi-ROIs | Total |
| --- | --- | --- | --- |
| `all5` (137) | 8.6 GiB | 2.1 GiB | about 11 GiB |
| `all5` + `no_membrane` (278) | 17.0 GiB | 4.2 GiB | about 21 GiB |
| all usable (333) | 20.3 GiB | 5.0 GiB | about 25 GiB |

- Building a stack needs about 7 bytes per voxel for a while: about 30 GiB for `all5` + `no_membrane`.
- **Loading is not the problem.** Training needs more, because Dragonfly copies the training data and builds patch stacks in memory. That code is compiled, so I could not measure how much. Expect several times the loaded size, more with overlapping patches and augmentation.
- **If training runs out of memory**, these are the options, simplest first:
  1. Start with 20–40 runs, watch memory while Dragonfly generates the patches, then scale up.
  2. Use a training mask. Dragonfly crops training data to the mask's bounding box, so covering part of each run (for example half the slices) cuts memory accordingly.
  3. Reduce patch overlap and the number of augmented copies in the training settings.
  4. Train in rounds: load part of the list (`FIRST`/`COUNT`), train, delete it, load the next part and continue training the same model.
  5. Train outside Dragonfly with a tool that streams from disk (for example nnU-Net) on the converters' `labels.mrc`.
- **Disk:** `/home` has only 28 GB free. Save Dragonfly sessions containing these datasets on `/mnt/big_data`.
- **Pixel size:** the lists mix pixel sizes from 3.2 to 19.8 Å, which makes a model tolerant to scale. To match a real dataset, pick runs near its pixel size from `classes_per_run.csv`.

## IMOD

- `3dmod sim/5_recon_sim.mrc labels/labels.mrc` shows the labels next to the tomogram.
- `3dmod sim/5_recon_sim.mrc labels/particles.mod` shows the particle positions with class names and colours.
- `imodauto -E <id> -u labels/labels.mrc out.mod` makes contour models of a class, if needed.

## Segmentation Networks

`labels.mrc` + `5_recon_*.mrc` is the usual image/label pair. The id → name table in `labels.json` corresponds to an nnU-Net `dataset.json` `labels` entry. Because the ids are fixed, runs can be pooled directly. A class that is absent from a run is simply missing in that run (`present: false`). The CSVs (or `particles.mod`) serve particle-picking methods that need coordinates instead of masks.
