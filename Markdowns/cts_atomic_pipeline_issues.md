# Issues in the CTS Atomic Pipeline

These problems turned up while working out the atlas labels of the actin/cofilactin/MT batch: 336 runs made by `scripts/cts_batch_actin_cofilactin_mt.m`, stored in `/mnt/big_data/CTS_actin_cofilactin_MT_simulation`. **No code has been changed.** This file is a to-do list for fixing. What the problems mean for the existing data is described in `atlas_labels_actin_cofilactin_mt.md`.

Most issues are in the atomic pipeline, which the repository keeps under `WIP/`. The older volume-based pipeline (`cts_model.m`, `helper_randomfill.m`) handles some of these cases.

Confidence words: **confirmed** means seen in the code and in the data. **unverified** means a guess.

| # | Issue | Effect on the data | Where |
| --- | --- | --- | --- |
| 1 | Collision checks are off in boxes thinner than about 104 Å | 3 runs are solid blocks of overlapping particles | `WIP/mu_build.m`, `WIP/mu_search.m` |
| 2 | Most placement flags are ignored | microtubule layer mostly places a lone protein; no bundles, clusters or placement inside vesicles | `WIP/helper_randfill_atom.m`, `WIP/helper_randfill_atom_mem.m` |
| 3 | `origin` blocks shift names against atoms | GABA-A receptors lack a subunit and carry two sheets of dummy atoms | `helper_input.m`, `helper_pdb2vol.m`, `WIP/helper_pdb2dat.m` |
| 4 | Vesicles are dropped when no membrane protein is placed | half the runs have no membranes; the metadata says they do | `WIP/helper_randfill_atom_mem.m`, `WIP/cts_model_atomic.m` |
| 5 | File-name parts and flags become label names, and equal names merge | generic labels (`membrane`, `complex`, …) that mix unrelated parts | `helper_input.m`, `WIP/helper_pdb2dat.m` |
| 6 | Model files with duplicates and a typo | ATP synthase at double density; G protein placed without its receptor | `synthetic_cytoplasm_models/` |
| 7 | No coordinates for membrane proteins and vesicles | no CSV for them | `WIP/helper_randfill_atom_mem.m`, `WIP/gen_mem_atom.m` |
| 8 | Atlas numbering depends on what was placed | the same value means different labels in different runs | `WIP/cts_model_atomic.m` |
| 9 | Dynamo tables in Å | wrong positions if used as they are | `WIP/cts_model_atomic.m` |

## 1. Collision checks are off in boxes thinner than about 104 Å

- **Seen** (confirmed):
  - Runs 00008, 00013 and 00015 are 256×256×64 voxels at 1.02–1.47 Å, so the box is 26–38 nm wide and 6.5–9.4 nm thick.
  - All 17,000 placement attempts succeeded, for example 2,000 ribosomes in a 26 nm box.
  - The atlas is 100 % labelled, against 15–35 % in all other runs.
  - These are the only runs with pixels below 3.2 Å.
- **Cause** (confirmed by running `mu_build`/`mu_search` in MATLAB with the fills' settings):
  - `mu_build` makes root cubes half as long as the box's smallest side, rounded to 10 Å (`cubify`, `WIP/mu_build.m:226-243`). With 64 slices, that is half the box thickness.
  - A cube is only subdivided when it is longer than 50 Å (`2*leaflen`) and holds more than 1,000 points (`leafcheck`, `WIP/mu_build.m:168-175`).
  - `mu_search`, called with `'short',0` as both fills do, only measures distances for points that fall into subdivided cubes (`rsplit2` → `bincheck`, `WIP/mu_search.m:43-67`). Its per-point fallback is skipped when nothing was found (line 71), and it would only measure distances with `'short',1` anyway (line 85).
  - So when the box is thinner than about 104 Å (64 slices at less than about 1.62 Å per pixel), no cube is ever subdivided, and every search reports "no overlap".
  - Test: a copy of a particle placed exactly on top of it goes undetected at 1.02–1.60 Å and is detected from 1.65 Å up.
- **Why only these runs:**
  - The first version of the batch script (commit `c9be768`) drew pixel sizes from 0.76–20 Å for 256×256×64 boxes. The current script draws 3.5–20 Å, so this cannot happen again with the current settings.
  - In 512×512×64 boxes at 3.5–20 Å, the ice-border points already subdivide all 512 root cubes when the index is built (checked at 3.5, 5, 10.4 and 20 Å). So the other runs are not affected.
- **Fix:**
  - Make `mu_search` also check points in cubes that are not subdivided (the existing `prox` function does this).
  - Or base the cube size in `cubify` on something other than the box thickness.
  - Also reject boxes thinner than the largest particle.
  - The three broken runs are listed in `scripts/run_lists/actin_cofilactin_mt/overfilled.txt`, and the Dragonfly import script skips them.

## 2. Most placement flags are ignored by the atomic fill

- **Where** (confirmed):
  - `WIP/helper_randfill_atom.m:63-69` and `WIP/helper_randfill_atom_mem.m:85-91` only test for `complex`. A complex places all its models together; any other file places one random model.
  - `membrane` only sends a file to the membrane fill.
  - `assembly`, `bundle`, `cluster`, `cytosol`, `vesicle` and `group` (listed in `helper_input.m:29-33`) have no effect.
  - The volume pipeline implements several of them (`helper_randomfill.m:172-252`).
- **Effects here:**
  - `layer 2/neuroMT.cytosol.assembly.pdb` has 4 models: the microtubule (711,776 atoms) and three copies of one 35,319-atom protein at different points along it.
    - Each placement takes one model at random, so 3 of 4 draws place that protein on its own, under the labels `cytosol` and `assembly`.
    - Run 00297 has 17 microtubules and 138 lone copies.
  - `actin_long.bundle` and `cofilactin_long.bundle` give single filaments, not bundles. `ribo_4ujd.cytosol.cluster` gives no clusters.
  - `actin_monomer.vesicle` and `cam.vesicle` were meant to go inside vesicles but are placed anywhere.
- **Fix:**
  - Implement `assembly` (all models, or a random subset, placed together like a complex), `bundle`, `cluster` and the location flags in the atomic fill.
  - For the microtubule alone: flag the file `complex`, or remove models 2–4.

## 3. `origin` blocks shift label names against atom sets

- **Where** (confirmed): `helper_input.m` reads each structure twice, with two loaders that disagree.
  - The **names** come from `helper_pdb2vol` (`helper_input.m:91`). It drops any block whose name contains `origin` (`helper_pdb2vol.m:173-184`).
  - The **atoms** come from `helper_pdb2dat` (`helper_input.m:93-95`). It keeps every block (`WIP/helper_pdb2dat.m:68-109`). Its own origin handling, in `internal_volbuild` (lines 272-314), is never called.
  - The fills pair names and atom sets by position: name u gets atom set u (`WIP/helper_randfill_atom_mem.m:129-140`, `WIP/helper_randfill_atom.m:81-98`).
- **Effect here:**
  - Of the files this batch uses, only `layer 1/GABAar.membrane.complex` has an origin block. Its block 1, `origin_OPM`, holds 1,946 OPM dummy atoms that mark the membrane surfaces: 973 "N" at z = −16.5 Å and 973 "O" at z = +14.5 Å, on 2 Å grids about 70 Å across. Then come the subunits `A_5soa` … `E_5soa`.
  - `A_5soa` receives the dummy atoms. They are simulated as real N and O atoms, so every receptor carries two flat sheets of extra density.
  - `B_5soa` … `E_5soa` receive subunits A–D. Subunit E is never placed.
  - The dummy atoms also enlarge the receptor's collision outline (`WIP/helper_randfill_atom_mem.m:86`).
  - `vatpase.membrane.cif` also has an origin block, but this batch does not use it.
- **Fix:**
  - Drop `origin` blocks in `helper_pdb2dat` as `helper_pdb2vol` does, and use their centre when `centering = 1`.
  - Or take the names from `dat.modelname` after dropping them.
  - Add a check in `helper_input.m` that the number of names equals the number of atom sets.

## 4. Vesicles are dropped when no membrane protein is placed

- **Where** (confirmed):
  - `WIP/cts_model_atomic.m:67-72` generates vesicles (`gen_mem_atom`) whenever `param.mem > 0`, then calls `helper_randfill_atom_mem`.
  - That function returns early when no file has the `membrane` flag (`WIP/helper_randfill_atom_mem.m:20`). The lipid atoms are only added at its end (lines 169-184), so they are never added.
- **Effect here:**
  - Every run asked for vesicles: `"mem":6` in `cts_param_model.log`, or 2 in two of the broken runs of issue 1.
  - The current batch script adds the membrane-protein files to a run with probability 0.7 (`scripts/cts_batch_actin_cofilactin_mt.m:91`). The 95 older runs, which have no `has_membrane_layer` field, never had them.
  - The 168 runs without membrane-protein files have no membranes at all. Their `metadata.json` still reports `actual_membrane_count` 6, because it comes from `param.mem` (`WIP/cts_model_atomic.m:70`).
- **Also:** that count is the number of vesicle blobs, including blobs that `gen_mem_atom` skips; `WIP/gen_mem_atom.m:161` and `:189` leave their cells empty. So it can be higher than the number of vesicles actually built, even in membrane runs.
- **Fix:**
  - Add the lipids whether or not membrane proteins are placed: move lines 169-184 out of the function, or run them before the early return.
  - Count only the non-empty `memdat.memcell` entries.
  - If membrane-free runs are intended, skip `gen_mem_atom` and record 0.

## 5. File-name parts and flags become label names, and equal names merge

- **Where** (confirmed):
  - `helper_input.m:42` splits the file name on `.` and `__` into `id`, flags included. The removal of flags from `id` is commented out (`helper_input.m:49`).
  - A model without a name of its own (every PDB model) is named `id{min(j,end)}` (`helper_input.m:117-118`, `WIP/helper_pdb2dat.m:104-105`).
  - Models with the same name share one atlas label (`WIP/helper_randfill_atom.m:42-44`, `WIP/helper_randfill_atom_mem.m:30-33`).
- **Effects here:**

  | File | Its models are named |
  | --- | --- |
  | `atp_synthase_2x.membrane.complex.pdb` | atp_synthase_2x, membrane, complex, complex |
  | `gprotein.membrane.comlex.pdb` | gprotein, membrane |
  | `neuroMT.cytosol.assembly.pdb` | neuroMT, cytosol, assembly, assembly |

  - The label `membrane` therefore holds two unrelated proteins (part 2 of the ATP synthase and the G protein) and no lipid.
  - Cif block names collide as well:
    - `cam.cytosol` and `cam.vesicle` both contain the block `cam.cytosol.cif`, so they share one label, `camcytosolcif`.
    - The 8 blocks of `atp_synthase_dimer_gen` are named after `atp_synthase_2x…pdb`.
- **Fix:**
  - Remove flags from `id` before naming, and name extra models `<name>_<j>`.
  - Warn when a name is already used by another file, or prefix labels with the file name.

## 6. Model-file problems

- **`layer 1/atp_synthase_2x.membrane.complex.pdb`** (confirmed):
  - Models 3–4 are exact copies of models 1–2: same atoms, same coordinates. It is probably the second half of a dimer that was never moved into place.
  - As a complex, all four models are placed together, so this particle is simulated at double density.
  - `complex` shows in the atlas only where the two halves touch (145 voxels in 00297).
  - Fix: move or delete models 3–4.
- **`layer 1/gprotein.membrane.comlex.pdb`** (confirmed):
  - `comlex` is a typo for `complex`. So the receptor (model 1, 2,397 atoms) and the G protein (model 2, 7,784 atoms) are placed separately, and the G protein sits at the membrane without its receptor.
  - Fix: rename the file to `.complex.`.
- **`layer 2/neuroMT.cytosol.assembly.pdb`:** see issue 2.

## 7. No coordinates for membrane proteins and vesicles

- **Where** (confirmed):
  - `helper_randfill_atom_mem` records every placement (`WIP/helper_randfill_atom_mem.m:139`, `:148`) but returns only `[split,dx,dyn]` (line 1).
  - So `cts.list` and the `zcoords_*.csv` files cover only the soluble particles (`WIP/cts_model_atomic.m:98`, `:138`, `:146-155`).
  - Vesicles are grown from seeds stored in `memdat.table` (`WIP/gen_mem_atom.m:41-50`), which is not saved.
- **Fix:**
  - Return `list` and merge it into `cts.list`. Note that it stores the anchor point on the membrane (`memloc`), not the protein centre. For complexes it writes one row per model.
  - Save `memdat.table` (centroid, size factor, volume) as a CSV.
- **Workaround for existing runs:**
  - `<run>.atom.mat` (`dat.data`) holds each label's atoms in placement order, one block per placement. Centres can be recovered for labels that come from a single source model.
  - Vesicles can be separated as connected components of the `vesicle` label.

## 8. Atlas numbering depends on what was placed

- **Where** (confirmed): empty labels are removed (`WIP/cts_model_atomic.m:103-109`) before the atlas and its txt are written (`WIP/cts_simulate_atomic.m:59-62`). Every later value shifts, so across the 336 runs the txt has 21–66 rows.
- **Fix:** keep every label of the batch, empty ones included, so the values stay the same. Or write one batch-wide name → value table.

## 9. Dynamo tables in Å

- **Where** (confirmed):
  - `internal_dynamotable` (`WIP/cts_model_atomic.m:175-185`) writes the coordinates in Å to columns 24–26. Its code comment asks whether an x/y flip is needed.
  - Dynamo expects pixels.
  - No orientations are written.
- **Fix:** divide by the pixel size. Write the placement rotation if orientations are needed.
