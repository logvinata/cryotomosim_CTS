# Batch Actin/Cofilactin/MT Script Explanation

Script: `/home/nataliya/cryotomosim_CTS/scripts/cts_batch_actin_cofilactin_mt.m`

## What It Produces

The script creates primary atomic CTS models, then runs two simulations from each model:

1. A randomized nonzero-dose simulation in `sim/`.
2. A matched zero-dose simulation pair from the same `.atom.mat` model in `zero_dose_pair/`.

Outputs are written under:

```text
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/
```

Each primary run uses a numeric folder and file stem such as `00001/00001.mat` and `00001/00001.atom.mat`. Parameter details are stored in `metadata.json` and `batch_manifest.csv`, not encoded into the folder name.

The active atomic reconstruction path writes final reconstructions as MRC mode `2`, which is `float32`. The atomic atlas writer in `WIP/cts_simulate_atomic.m` has also been changed to mode `2`.

## Model Layers

The base model has six requested biological layers:

1. Microtubules from `synthetic_cytoplasm_models/layer 2/neuroMT.cytosol.assembly.*`
2. Actin from `synthetic_cytoplasm_models/layer 2/actin_long.bundle.*`
3. Cofilactin from `synthetic_cytoplasm_models/layer 2/cofilactin_long.bundle.*`
4. Ribosomes from `synthetic_cytoplasm_models/layer 2/ribo_4ujd.cytosol.cluster.*`
5. Large macromolecules from all `.mat` files in `synthetic_cytoplasm_models/layer 3`
6. Small macromolecules from all `.mat` files in `synthetic_cytoplasm_models/layer 4`

For 70% of newly generated models, the script prepends an additional membrane-protein layer from `.mat` files in `synthetic_cytoplasm_models/layer 1` whose filenames contain the `membrane` flag. This makes those runs seven-layer models. The membrane-protein layer is needed by atomic CTS membrane embedding; `param.mem` alone requests membrane geometry but does not supply any `.membrane`-flagged atomic structures to embed.

This probability is controlled by:

```matlab
membraneProbability = 0.7;
```

For each new model, the chosen result is stored in `metadata.json` as:

```json
"has_membrane_layer": true,
"membrane_probability": 0.7
```

## Line-By-Line / Block Explanation

Lines 1-3 describe the purpose of the script: batch tomogram generation with a paired zero-dose simulation for every primary simulation.

Line 5 clears existing MATLAB workspace variables so previous runs do not leak settings into this batch.

Line 6 seeds MATLAB's random-number generator from the current clock so separate MATLAB sessions do not repeat the same randomized parameters.

Lines 9-11 define the CTS code root, the synthetic model folder, and the output folder.

Lines 13-14 add the main CTS folder and `WIP` folder to the MATLAB path. This is required because `cts_model_atomic` and `cts_simulate_atomic` live in `WIP`.

Lines 16-18 stop immediately if the requested output folder does not exist.

Lines 21-26 define the core parameter grids: tomogram size `512 x 512 x 64`, tilt range `-60:1:60`, defocus choices `-7:-2`, dose choices `50:10:150`, and the assumption of 20 pixel-size grid points for default-count estimation.

Lines 28-33 ask for the number of primary tomograms. Press Enter to use the default. Each primary tomogram creates two simulation folders because the zero-dose pair is also generated.

Lines 36-46 define `baseLayerFiles`, the six non-membrane biological layers requested for every newly generated model.

Lines 48-49 load membrane-tagged `.mat` files from `synthetic_cytoplasm_models/layer 1` and set the membrane-protein inclusion probability to `0.7`.

Lines 51-53 set particle density to `0.8`, base-layer placement iterations to `[300, 1000, 1000, 500, 4000, 4000]`, and membrane-layer iterations to `500`.

Lines 54-55 point to `batch_manifest.csv` and create it only if it does not already exist. Existing completed-run rows are preserved.

Lines 58-135 are the main batch loop. Each loop checks one numeric run, skipping complete runs and processing incomplete or missing runs.

Lines 59-62 define a simple numeric run name such as `00001`, its output folder, and the expected final reconstruction files for the nonzero-dose and zero-dose simulations.

Lines 64-69 identify complete runs. A complete run must have `metadata.json`, the model `.mat`, the `.atom.mat`, `sim/5_recon_sim.mrc`, and `zero_dose_pair/5_recon_zero_dose_pair.mrc`. Complete runs are skipped and added to the manifest if the row is missing.

Lines 70-82 resume an existing but incomplete run folder if it already contains both `metadata.json` and the matching `.atom.mat` model file. This allows a failed simulation step to be rerun without regenerating the model.

Lines 84-86 choose randomized per-run parameters: pixel size from `3.5` to `20.000` Angstroms with `0.001` precision, one defocus value from `-7:-2`, and one total dose from `50:10:150`.

Lines 88-90 print the run parameters to the MATLAB console.

Lines 91-100 decide whether this new model gets the membrane-protein layer. If yes, the membrane layer is prepended to the six base layers and receives its own iteration count.

Lines 102-104 build the atomic model parameter struct and call `cts_model_atomic` with tomogram size `[512 512 64]`, the generated model parameters, the output directory, and the numeric basename.

Lines 106-112 convert the returned `.mat` model path to the matching `.atom.mat` path, record the actual membrane count, and write `metadata.json`.

Lines 115-120 build the simulation parameters and run the nonzero-dose simulation in `sim/` only if `sim/5_recon_sim.mrc` is missing.

Lines 122-128 copy the same simulation parameters, set dose to `0`, and run the paired zero-dose simulation in `zero_dose_pair/` only if `zero_dose_pair/5_recon_zero_dose_pair.mrc` is missing.

Lines 130-134 append the run to `batch_manifest.csv` only after the run passes the completion check. If it is still incomplete, the manifest is not updated for that run.

Lines 137-138 print a completion message and report total simulation count including pairs.

Lines 141-157 define `makeModelParam`. It loads each selected layer with `helper_input`, applies particle density `0.8`, disables carbon grid, enables vitreous ice, and sets `param.mem = 6` so CTS requests membrane geometry.

Lines 159-174 define `makeSimParam`. This encodes the microscope and acquisition settings: `300 kV`, `Cs = 2.7`, envelope `sigma = 1`, tilt range, dose, dose-symmetric scheme, pixel size, radiation damage `1`, tilt error `0.3`, and ice enabled.

Lines 176-183 define `allModelMats`, which returns all `.mat` files in a folder sorted by filename.

Lines 185-197 define `allMembraneModelMats`, which returns only `.mat` files whose filenames contain `membrane`. This is the key selection that gives atomic CTS structures with the `.membrane` functional flag.

Lines 199-208 define `firstExisting`, which lets the script use the requested `.pdb` when present and fall back to `.mat` when the `.pdb` is missing.

Lines 210-216 define `ensureManifest`, which creates the manifest header only when the manifest does not already exist.

Lines 218-224 define `isRunComplete`, the run-completion check used for skipping and manifest updates.

Lines 226-253 define helpers that append manifest rows only when the manifest does not already contain that run index.

Lines 255-282 define `makeMetadata`, which writes a JSON sidecar with the run index, numeric run name, model paths, tomogram size, pixel size, defocus, total dose, tilt list, microscope settings, membrane counts, membrane-layer decision, density, iteration counts, and layer file lists.

Lines 284-287 define `writeJson`, which writes the metadata sidecar.

## Important Notes

Defocus is randomized once per tomogram, not once per tilt. The current atomic simulation code treats `param.defocus` as a scalar, then adjusts it internally by slab depth.

The default primary tomogram count is large: `6 defocus values * 11 dose values * 20 pixel-size bins * 2 = 2640`. Because each primary also gets a zero-dose pair, that default creates `5280` simulation folders.

The membrane count is set to `6` because the request specified that membrane should be present but did not specify how many vesicles or membranes to generate.

The console message `no membrane structs to embed, skipping` comes from `helper_randfill_atom_mem`. In atomic mode it means no selected input layer contained structures with a filename flag containing `membrane`, so the membrane-embedding step had no membrane-tagged atomic structures to place. The 70% membrane-protein branch is intended to avoid that message for most newly generated models.
