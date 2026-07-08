# Batch Actin/Cofilactin/MT Script Explanation

Script: `/home/nataliya/cryotomosim_CTS/scripts/cts_batch_actin_cofilactin_mt.m`

## What It Produces

The script creates primary atomic CTS models with six biological layers, then runs two simulations from each model:

1. A randomized nonzero-dose simulation.
2. A matched zero-dose simulation pair from the same `.atom.mat` model.

Outputs are written under:

```text
/mnt/big_data/CTS_actin_cofilactin_MT_simulation/
```

The active atomic reconstruction path writes final reconstructions as MRC mode `2`, which is `float32`. The atlas writer in `WIP/cts_simulate_atomic.m` has also been changed to mode `2`.

Each primary run now uses a simple numeric folder and file stem such as `00001/00001.mat` and `00001/00001.atom.mat`. Simulation folders inside each run are named `sim` and `zero_dose_pair`. Parameter details are stored in `metadata.json` and `batch_manifest.csv`, not encoded into the run folder name.

## Line-By-Line / Block Explanation

Lines 1-3 describe the purpose of the script: batch tomogram generation with a paired zero-dose simulation for every primary simulation.

Line 5 clears existing MATLAB workspace variables so previous runs do not leak settings into this batch.

Line 6 seeds MATLAB's random-number generator from the current clock so separate MATLAB sessions do not repeat the same randomized parameters.

Lines 9-11 define the CTS code root, the synthetic model folder, and the requested output folder.

Lines 12-13 add the main CTS folder and `WIP` folder to the MATLAB path. This is required because `cts_model_atomic`, `cts_simulate_atomic`, and `param_batch`-style batch utilities live in `WIP`.

Lines 15-17 stop immediately if the requested output folder does not exist.

Lines 20-24 define the core parameter grids: tomogram size `256 x 256 x 64`, tilt range `-60:1:60`, defocus choices `-7:-2`, dose choices `50:10:150`, and the requested assumption of 20 pixel-size grid points for default-count estimation.

Line 25 computes the default number of primary tomograms as `defocus_count * dose_count * 20 * 2`.

Lines 27-32 ask for the number of primary tomograms. Press Enter to use the default. Each primary tomogram creates two simulation folders because the zero-dose pair is also generated.

Lines 35-45 define the six requested model layers. Layers 1-4 use the named files from `synthetic_cytoplasm_models/layer 2` when present. `actin_long.bundle.pdb` and `ribo_4ujd.cytosol.cluster.pdb` were not present, so the script falls back to `actin_long.bundle.mat` and `ribo_4ujd.cytosol.cluster.mat`.

Lines 46-47 load all `.mat` models from `layer 3` and `layer 4` for the large and small macromolecule layers. `.mat` is preferred to avoid duplicating the same molecule from both source `.cif/.pdb` and cached `.mat` files.

Lines 48-49 set particle density to `0.8` for every layer and placement iterations to `[1000, 1000, 1000, 2000, 4000, 8000]`.

Lines 50-51 create or overwrite a CSV manifest in the output folder.

Lines 54-87 are the main batch loop. Each loop creates one model, one nonzero-dose simulation, and one matched zero-dose simulation.

Lines 55-59 define a simple numeric run name such as `00001` and stop if that folder already exists, to avoid mixing old and new outputs.

Line 61 draws a random pixel size uniformly from `0.76` to `20.000` Angstroms and rounds it to `0.001`.

Lines 62-63 choose one defocus value and one total dose value randomly from the requested step grids.

Lines 65-66 print run parameters to the MATLAB console.

Line 68 builds the model parameter struct, including all six loaded layers, membrane, and ice settings.

Lines 69-70 call `cts_model_atomic` with tomogram size `[256 256 64]`, the generated model parameters, the requested output directory, and the simple numeric basename.

Lines 72-73 convert the returned `.mat` model path to the matching `.atom.mat` path used by `cts_simulate_atomic`.

Lines 74-76 write `metadata.json` inside the numeric run folder.

Lines 78-79 build the simulation parameters and run the nonzero-dose simulation in the `sim` subfolder.

Lines 81-83 copy the same simulation parameters, set dose to `0`, and run the paired zero-dose simulation in the `zero_dose_pair` subfolder.

Line 85 appends the run metadata to `batch_manifest.csv`.

Lines 84-86 print a completion message and report total simulation count including pairs.

Lines 89-107 define `makeModelParam`. It loads each layer with `helper_input`, applies particle density `0.8`, disables carbon grid, enables vitreous ice, and sets `param.mem = 6` so membranes are present.

Lines 109-129 define `makeSimParam`. This encodes the requested microscope and acquisition settings: `300 kV`, `Cs = 2.7`, envelope `sigma = 1`, tilt range, dose, dose-symmetric scheme, pixel size, radiation damage `1`, tilt error `0.3`, and ice enabled.

Lines 131-138 define `allModelMats`, which returns all `.mat` files in a folder sorted by filename.

Lines 140-149 define `firstExisting`, which lets the script use the requested `.pdb` when present and fall back to `.mat` when the `.pdb` is missing.

Lines 151-155 write the manifest CSV header.

Lines 157-161 append one row to the manifest after each completed primary tomogram.

The `makeMetadata` helper writes a JSON sidecar with the run index, numeric run name, model paths, tomogram size, pixel size, defocus, total dose, tilt list, microscope settings, membrane counts, density, iteration counts, and layer file lists.

## Important Notes

Defocus is randomized once per tomogram, not once per tilt. The current atomic simulation code treats `param.defocus` as a scalar, then adjusts it internally by slab depth.

The default primary tomogram count is large: `6 defocus values * 11 dose values * 20 pixel-size bins * 2 = 2640`. Because each primary also gets a zero-dose pair, that default creates `5280` simulation folders.

The membrane count is set to `6` because the request specified that membrane should be present but did not specify how many vesicles/membranes to generate.

The console message `no membrane structs to embed, skipping` comes from `helper_randfill_atom_mem`. It means none of the input particle structures had a filename flag containing `membrane`, so CTS did not embed membrane proteins into the generated membrane surfaces. It does not mean membranes were absent; membrane geometry is generated separately from `param.mem`.
