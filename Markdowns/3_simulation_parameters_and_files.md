# CTS simulation parameters and required files (code-derived)

Scope: parameters that change tilt-series simulation and/or the reconstructed tomogram, traced from `param_simulate.m`, `cts_simulate.m`, `helper_ctf.m`, `helper_electrondetect.m`, `WIP/helper_radiation.m`, plus upstream `param_model.m`/`cts_model.m` parameters that indirectly affect reconstruction by changing the input model volume.

Key code paths (absolute):
- `/home/nataliya/cryotomosim_CTS/param_simulate.m` (`param_simulate`)
- `/home/nataliya/cryotomosim_CTS/cts_simulate.m` (`cts_simulate`, `internal_sim`)
- `/home/nataliya/cryotomosim_CTS/helper_ctf.m` (`helper_ctf`)
- `/home/nataliya/cryotomosim_CTS/helper_electrondetect.m` (`helper_electrondetect`)
- `/home/nataliya/cryotomosim_CTS/WIP/helper_radiation.m` (`helper_radiation`)
- `/home/nataliya/cryotomosim_CTS/param_model.m` (`param_model`)
- `/home/nataliya/cryotomosim_CTS/cts_model.m` (`cts_model`)

## A) Direct simulation/reconstruction parameters

| Parameter | Variable name in code | File(s) | Valid values (and meaning) | Default | Where used | Physical meaning | Stage of pipeline |
|---|---|---|---|---|---|---|---|
| Tilt axis | `param.tiltax` | `param_simulate.m`, `cts_simulate.m`, `helper_electrondetect.m` | `'X'` or `'Y'`; non-`'X'` effectively treated as `'Y'` in `cts_simulate` | `'Y'` | `cts_simulate`: `imrotate3` if `'X'`; `xyzproj -axis`; detect geometry adjusts `box` orientation | Projection axis relative to specimen | Projection geometry + dose/CTF geometry |
| Tilt angle list | `param.tilt` | `param_simulate.m`, `cts_simulate.m`, `helper_ctf.m`, `helper_electrondetect.m` | Numeric vector of angles in degrees; either explicit list or triplet `[min inc max]` | `[-60 2 60]` (then expanded) | Written to `tiltanglesR/T`; iterated in CTF and dose simulation | Acquisition angle set | Projection + CTF + dose |
| Tilt increment (triplet input mode) | `param.tilt(2)` then expansion `param.tilt(1):param.tilt(2):param.tilt(3)` | `param_simulate.m` | Numeric increment in degrees (typically non-zero) | `2` deg (from default triplet) | Expansion block (`numel(param.tilt)==3`) | Angular step between projections | Input parsing for projection schedule |
| Tilt range min/max (triplet mode) | `param.tilt(1)`, `param.tilt(3)` | `param_simulate.m` | Numeric min/max angles in degrees | `-60`, `60` deg | Same expansion block | Endpoints of tilt sweep | Input parsing for projection schedule |
| Arbitrary angle schedule | Explicit vector in `param.tilt` (non-triplet) | `param_simulate.m`, downstream same as above | Any numeric angle vector (order preserved) | User-defined | Used directly if not triplet | Fully custom angle schedule | Projection + CTF + dose |
| Tilt ordering scheme | `param.tiltscheme` | `param_simulate.m`, `helper_electrondetect.m` | `'symmetric'` or numeric split angle (bidirectional ordering pivot) | `0` (numeric split angle) | `helper_electrondetect` sorts tilt order: `'symmetric'` or split-angle metric | Acquisition order used for dose accumulation | Dose simulation |
| Tilt error | `param.tilterr` | `param_simulate.m`, `cts_simulate.m` | Numeric scalar; `0` disables random perturbation, non-zero scales random error range | `0` | Random error vector generated, then `tiltanglesT = param.tilt + param.tilterr` | Stage/angle perturbation | Projection geometry |
| Pixel size override | `param.pix` | `param_simulate.m`, `cts_simulate.m`, `helper_ctf.m`, `helper_electrondetect.m` | `0` means inherit model pixel size; otherwise numeric override (for `.dat` pathway code enforces `>=0.5`) | `0` (inherit model pixel size) | `if param.pix==0` use input model pix; used in CTF unit conversion and detection geometry/path length | Sampling/resolution and geometry scaling | CTF + dose + reconstruction geometry |
| Simulation volume size | `param.size = size(vol)` | `cts_simulate.m`, `helper_electrondetect.m` | Derived 3-vector `[nx ny nz]` in voxels (not user-entered directly) | Derived from input model | Used for `xyzproj/tilt` width, reconstruction thickness, and electron path geometry | Field-of-view dimensions | Projection + dose + reconstruction |
| Dose | `param.dose` | `param_simulate.m`, `helper_electrondetect.m`, `cts_simulate.m` | Numeric scalar (series-total) or numeric vector (per-tilt); `<=0` disables detection noise branch | `100` e/A^2 | If `<=0`, detection returns perfect tilt; otherwise sets shot noise/exposure | Electron exposure budget | Dose simulation |
| Per-series vs per-tilt dose handling | Scalar/vector semantics of `param.dose` | `helper_electrondetect.m` | Scalar: auto-divided across tilts; vector: length should match number of tilts (warning otherwise) | Scalar by default | Scalar: divided by #tilts; vector: reordered by acquisition sort index | Dose distribution rule | Dose simulation |
| Defocus | `param.defocus` | `param_simulate.m`, `helper_ctf.m` | Numeric value in um; negative typically used for underfocus | `-5` um | Converted to `Dz`; strip defocus adjusted by tilt and strip position | Mean defocus setting | CTF simulation |
| Voltage | `param.voltage` | `param_simulate.m`, `helper_ctf.m` | Positive numeric (`mustBePositive`) in kV | `300` kV | Converted to eV; used for relativistic electron wavelength | Beam energy | CTF simulation |
| Spherical aberration | `param.aberration` | `param_simulate.m`, `helper_ctf.m` | Numeric in mm | `2.7` mm | Converted to `cs` in CTF phase term | Objective lens spherical aberration | CTF simulation |
| Envelope parameter | `param.sigma` | `param_simulate.m`, `helper_ctf.m` | Numeric scalar; larger value gives broader envelope | `0.9` | `B = param.sigma * Ny`, controls CTF envelope decay | Envelope/MTF-like damping strength | CTF simulation |
| Phase shift | `param.phase` | `param_simulate.m`, `helper_ctf.m`, `helper_electrondetect.m` | Numeric in radians; affects CTF phase term and DQE branch threshold at `pi/4` | `0.07` rad | Used in CTF phase term `sin(phi+eq-A)` and in DQE scaling branch | Phase plate / phase offset proxy | CTF + dose |
| Amplitude contrast assumption | local `q` passed as `A` in CTF kernel | `helper_ctf.m` | Fixed `0.00` in current code (hardcoded) | `0.00` (hardcoded) | `q = 0.00` passed to `math_ctf` | Fixed amplitude-contrast offset term | CTF simulation |
| CTF overlap / CTF enable | `param.ctfoverlap` | `param_simulate.m`, `helper_ctf.m` | Nonnegative integer (`mustBeNonnegative`, `mustBeInteger`); `0` disables CTF | `2` | If `0`, CTF skipped; otherwise controls strip width/weight overlap | Defocus strip blending in pseudo-3D CTF | CTF simulation |
| CTF padding | `pad` arg to `helper_ctf` | `helper_ctf.m` | Numeric scalar padding value; default path uses `10` | `10` | Padding/cropping around FFT convolution | Numerical artifact control | CTF simulation |
| DQE assumption | local `DQE = .84 * phi` | `helper_electrondetect.m` | Effective values `{0.84, 0.672}` depending on `param.phase` threshold (`pi/4`) | Base `0.84` scaled by phase condition | `dw = dose * DQE` | Detector quantum efficiency assumption | Dose simulation |
| Inelastic scattering scale | `param.scatter` | `param_simulate.m`, `helper_electrondetect.m` | Numeric scalar; `0` removes inelastic attenuation term | `1` | Scales exponent in `exp(-(path*scatter)/IMFP)` | Strength of inelastic-loss attenuation | Dose simulation |
| IMFP constant | local `IMFP` | `helper_electrondetect.m` | Fixed `3100` A in current code | `3100` A (hardcoded) | Used in inelastic attenuation equations | Inelastic mean free path assumption | Dose simulation |
| Radiation damage scale | `param.raddamage` | `param_simulate.m`, `helper_electrondetect.m`, `WIP/helper_radiation.m` | Numeric scalar; `<=0` bypasses `helper_radiation`, `>0` enables | `1` | If `>0`, calls `helper_radiation`; scales damage/noise strength | Beam damage severity proxy | Dose simulation |
| Radiation model constants | local `rads`, `H` | `WIP/helper_radiation.m` | Fixed formula/constants in code: `rads=.02*rad*dose`, `H=8e2` | `rads=.02*rad*dose`, `H=8e2` (hardcoded) | Used in blur/noise/decay equations | Damage calibration constants | Dose simulation |
| Milling/thickness artifact | `param.mill` | `param_simulate.m`, `helper_electrondetect.m` | Numeric scalar; `>0` enables milling surface model, `<=0` uses default smooth surface model | `0` | `>0` uses `helper_surfmill`; else `helper_surf` | Lamella/surface thickness-variation artifacts | Dose simulation |
| Dose-vs-CTF order | `opt.ctford` | `cts_simulate.m` | Intended values `1` or `2` (`1`: dose then CTF, `2`: CTF then dose) | `1` | `1`: dose then CTF; `2`: CTF then dose | Processing-order choice affecting image statistics | Dose+CTF pipeline orchestration |
| Reconstruction width | local `w = round(param.size(tmpax)*1)` | `cts_simulate.m` | Derived positive integer from input volume size and tilt axis | Derived | Used in `xyzproj -width` and `tilt -width` | Projection/reconstruction lateral extent | Projection + reconstruction |
| Reconstruction thickness | local `thick = round(param.size(3)*1)` | `cts_simulate.m` | Derived positive integer from input volume z-size | Derived | Used in `tilt -thickness` | Reconstructed z-extent | Reconstruction |
| Reconstruction filter settings | hardcoded `-RADIAL 0.35,0.035` | `cts_simulate.m` | Fixed pair `(0.35, 0.035)` in current code | Fixed | Passed to IMOD `tilt` command | Fourier radial low-pass settings | Reconstruction |
| Post-recon normalization toggle | `opt.norm` | `cts_simulate.m` | `0` (skip normalization block) or `1` (enter normalization block) | `1` | Conditional normalization block before final write | Intended z-score normalization of output volume | Reconstruction output post-process |
| `inference`: normalization bug impact | local `normed` variable (computed but not written) | `cts_simulate.m` | unspecified | N/A | Code writes `vol` instead of `normed` | Intended normalization may currently be ineffective | Reconstruction output post-process |
| Legacy/unused sim knob | `param.ice` | `param_simulate.m` | unspecified (declared numeric; no active use in this sim path) | `1` | Declared in `param_simulate`; no active use in `cts_simulate/helper_ctf/helper_electrondetect` | No direct effect in active sim path (current code) | N/A (legacy) |

## B) Upstream model parameters that indirectly affect tilt-series and reconstruction

These parameters do not change microscope physics directly, but they change the voxelized specimen and therefore all downstream projections/reconstruction.

| Parameter | Variable name in code | File(s) | Valid values (and meaning) | Default | Where used | Physical meaning | Stage of pipeline |
|---|---|---|---|---|---|---|---|
| Model volume size | input `vol` to `cts_model` (e.g., `zeros(x,y,z)`) | `cts_model.m`, scripts (e.g., `scripts/cts_demo_script.m`) | 3D numeric array size `[nx ny nz]`; typically initialized with `zeros(x,y,z)` | No internal default (caller-provided) | Drives `cts.vol` dimensions; later becomes `param.size` in simulation | Simulated specimen box size | Model generation (upstream geometry) |
| Model pixel size | `param.pix` from `param_model` | `param_model.m`, `cts_model.m` | Numeric scalar in angstroms | Required (GUI or explicit) | Used to voxelize structures and write model MRC pixel size | Physical sampling of specimen model | Model generation |
| Particle layers/input set | `param.layers` | `param_model.m`, `cts_model.m` | Layer count (numeric), or structured/cell layer definitions with input particles | `1` | Passed into `helper_randomfill` | Which structures and classes are present | Model generation |
| Packing density cap | `param.density` | `param_model.m`, `cts_model.m` | Numeric scalar/vector (per-layer) | `0.4` | Used by `helper_randomfill` occupancy stopping criterion | Specimen crowding | Model generation |
| Placement iterations | `param.iters` | `param_model.m`, `cts_model.m` | Numeric scalar/vector; `0` triggers auto (`2500*density`) | `0` (auto to `2500*density`) | Used by `helper_randomfill` loop count | Number of insertion attempts | Model generation |
| Boundary constraints | `param.constraint` | `param_model.m`, `cts_model.m`, `helper_constraints.m` | 3-char code using `&`, `+`, `-`, or space per axis | `'  &'` | Creates forbidden border mask | Geometric exclusion at edges | Model generation |
| Carbon film/hole | `param.grid` | `param_model.m`, `cts_model.m`, `gen_carbon.m` | `0` (disable) or 2-vector `[thickness_A radius_A]` | `[150 1e4]` | Generates/adds carbon layer volume | Grid/carbon support geometry | Model generation |
| Membrane count/placement | `param.mem` | `param_model.m`, `cts_model.m`, `gen_memvol.m` | `0` (disable) or numeric count (rounded to integer) | `0` | Generates membrane volumes used in final model | Vesicle/membrane content | Model generation |
| Filament generation | `param.filaments` | `param_model.m`, `cts_model.m` | `0` (disable) or non-zero/struct via `helper_filinput` | `0` | Routes to filament placement logic | Filamentous structures in specimen | Model generation |
| Fiducial beads | `param.beads` | `param_model.m`, `cts_model.m`, `gen_beads.m` | `0` (disable) or vector `[count radius1 radius2 ...]` | `0` | Generates and places bead signal | Fiducials/extra scattering objects | Model generation |
| Model ice content | `param.ice` | `param_model.m`, `cts_model.m`, `gen_ice.m` | Numeric scalar; `0` disables model ice, non-zero scales ice intensity | `1` | Scales/generated vitreous-ice component in `cts.vol` | Background ice signal in specimen model | Model generation |
| Bare membrane fraction | `param.bare` | `param_model.m`, `cts_model.m`, `gen_memvol.m` | Numeric scalar proportion (intended 0..1); higher means more bare membranes | `0` | Affects membrane protein-association placement availability | Membrane occupancy behavior | Model generation |

## Which parameters are the right control knobs for different tilt-acquisition schemes?

If your goal is to emulate acquisition protocol differences (not specimen composition), prioritize these knobs:

1. `param.tilt` (primary): define exact angle schedule.
- Use explicit vectors for arbitrary schedules (e.g., dose-symmetric, grouped, missing angles, nonuniform increments).
- Use `[min inc max]` only for simple uniform schedules.

2. `param.tiltscheme` (ordering): control dose accumulation order.
- `'symmetric'`: order by increasing absolute tilt.
- Numeric split angle: bidirectional ordering around that angle.

3. `param.dose` (and vector semantics): control dose per tilt vs total.
- Scalar => automatically distributed across tilts.
- Vector => per-tilt weights; must match tilt count.

4. `param.tilterr`: add stochastic angle perturbations.
- Simulates stage/targeting errors around requested angles.

5. `param.tiltax`: switch acquisition axis (`'X'` vs `'Y'`).
- Affects projection orientation and geometry handling.

6. `param.defocus`, `param.ctfoverlap`, `param.voltage`, `param.aberration`, `param.sigma`, `param.phase`:
- Tune optical transfer behavior for different microscope/imaging conditions.

7. `param.raddamage`, `param.scatter`, `param.mill`:
- Tune degradation/attenuation artifacts coupled to acquisition.

8. `opt.ctford`:
- Chooses whether dose damage is applied before or after CTF.

9. Reconstruction settings (currently fixed in code):
- `-RADIAL 0.35,0.035`, reconstruction width/thickness logic.
- For true protocol sweeps, this is a key place to parameterize in code.

Practical acquisition-scheme minimum set: `tilt`, `tiltscheme`, `dose` (scalar/vector), `tilterr`, `tiltax`.

## User-provided files for simulation

| File_type | Function | Meaning | Stage of the pipeline |
|---|---|---|---|
| `.pdb`, `.pdb1` | `helper_input` -> `helper_pdb2vol` (via `param_model`/`cts_model`) | Atomic structure input for voxel model construction | Model generation |
| `.cif`, `.mmcif` | `helper_input` -> `helper_pdb2vol` | Atomic structure input (mmCIF/CIF) for voxel model construction | Model generation |
| `.mat` (structure cache with `data`, from `helper_pdb2vol`) | `helper_input` -> `helper_pdb2vol` | Preparsed structure file for faster model generation | Model generation |
| `.mrc` (particle volume map) | `helper_input` | Pre-voxelized particle map inserted into model (resampled to model pixel size) | Model generation |
| `.mat` (CTS model containing `cts` struct) | `cts_simulate` | Preferred simulation input model; supports atlas generation | Simulation input |
| `.mrc` (full model density volume) | `cts_simulate` | Alternative simulation input model volume | Simulation input |
| `.mat` (atomic dataset containing `dat.data` + `dat.box`) | `cts_simulate` -> `helper_atoms2vol` | Atomic-point representation converted to volume before simulation | Simulation input |

Notes:
- External runtime requirements (not user-supplied dataset files): IMOD executables (`xyzproj`, `tilt`, `trimvol`) and MATLAB MRC IO functions (`ReadMRC`/`WriteMRC`).
- `inference`: `helper_electrondetect` calls `helper_radiation`, but in this repo that function is located at `WIP/helper_radiation.m`; it must be on MATLAB path at runtime.
