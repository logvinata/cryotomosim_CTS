# CTS Prompt 1 — Entry points and call graph

## Codex output, lightly annotated

### Main entry points

- **GUI entry point:** `ctsgui.mlapp`  
  Brief comment: this is the MATLAB App Designer GUI. It is a convenience front end, not the scientific core.

- **Main CLI/API entry point (model):** `cts_model.m`  
  Brief comment: top-level function that builds the specimen/model volume.

- **Main CLI/API entry point (simulate):** `cts_simulate.m`  
  Brief comment: top-level function that generates projections, applies imaging effects, reconstructs the tomogram, and optionally builds the atlas.

- **Main CLI script driver:** `scripts/cts_demo_script.m`  
  Brief comment: this is probably the best non-GUI place to start if the goal is to understand the real scripted workflow.

---

## GUI path

```text
ctsgui
  -> ImportLayersButtonPushed -> param_model
      -> helper_input -> helper_pdb2vol / ReadMRC
  -> GenerateModelButtonPushed -> cts_model
      -> gen_carbon (optional)
      -> gen_memvol (optional)
      -> helper_constraints
      -> helper_randomfill  (core model population)
      -> gen_beads (optional)
      -> gen_ice (optional)
      -> WriteMRC + save(.mat)

ctsgui
  -> ImportModelFileButtonPushed (sets app.path)
  -> GenerateFilesButtonPushed -> param_simulate -> cts_simulate(app.path,...)
      -> internal_sim
          -> system('xyzproj ...')                [tilt projection]
          -> (ctford==1) helper_electrondetect -> helper_ctf
          -> (ctford==2) helper_ctf -> helper_electrondetect
          -> system('tilt ...') + system('trimvol ...')   [reconstruction]
      -> helper_particleatlas (if input is CTS struct .mat)
          -> helper_watershed (only when dynamotable=1)
```
### Brief comments

- `helper_randomfill` looks like the key model-population routine.
- `xyzproj` is the IMOD projection step, so the tilt series is being generated from the **model**, not from a tomogram.
- `tilt` + `trimvol` are the IMOD reconstruction/orientation steps.
- The `ctford` switch suggests CTS can apply **dose then CTF** or **CTF then dose**, depending on settings. That should be checked later in code, because it may matter for reimplementation.

---

## CLI path

```text
scripts/cts_demo_script
  -> param_model -> cts_model
  -> param_simulate -> cts_simulate
```

### Brief comment

This is the clean path for reverse-engineering. If the goal is to understand the pipeline and later build a smaller simulator, this path matters more than the GUI path.

---

## Function table with comments

| Function | File | Role | Called by | Calls next | Brief comment |
|---|---|---|---|---|---|
| `ctsgui` | `ctsgui.mlapp` | GUI app entry | MATLAB command `ctsgui` | UI callbacks (`ImportLayersButtonPushed`, `GenerateModelButtonPushed`, `GenerateFilesButtonPushed`) | Convenience layer only |
| `cts_model` | `cts_model.m` | Top-level model generation | CLI users, GUI `GenerateModelButtonPushed`, scripts | `gen_carbon`, `gen_memvol`, `helper_constraints`, `helper_randomfill`, `gen_beads`, `gen_ice` | Core model builder |
| `cts_simulate` | `cts_simulate.m` | Top-level simulation/reconstruction | CLI users, GUI `GenerateFilesButtonPushed`, scripts | `internal_sim`, then `helper_particleatlas` (conditional) | Core simulation driver |
| `internal_sim` | `cts_simulate.m` | Core tilt/projection + dose/CTF + reconstruction | `cts_simulate` | `xyzproj` command, `helper_electrondetect`, `helper_ctf`, `tilt` command, `trimvol` command | Most important function for acquisition simulation |
| `helper_electrondetect` | `helper_electrondetect.m` | Dose/noise simulation | `internal_sim` | `helper_surf`/`helper_surfmill`, `helper_thickfromsurf`, `helper_radiation`, Poisson sampling | Imaging/noise model |
| `helper_ctf` | `helper_ctf.m` | CTF application per tilt/strip | `internal_sim` | `math_ctf` | Key for the 2.5D CTF approximation |
| `math_ctf` | `math_ctf.m` | CTF math kernel (FFT-domain modulation) | `helper_ctf` | returns convolved strip | Mathematical kernel |
| `helper_particleatlas` | `helper_particleatlas.m` | Atlas/label volume generation | `cts_simulate` | writes atlas `.mrc`/`.txt`; optional `generatetable` | Ground-truth output path |
| `helper_watershed` | `helper_watershed.m` | Particle-instance labeling for Dynamo tables | `helper_particleatlas` (optional path) | `regionprops3` table generation | Optional downstream labeling |
| `scripts/cts_demo_script` | `scripts/cts_demo_script.m` | Command-line orchestration example | user/script invocation | `param_model`, `cts_model`, `param_simulate`, `cts_simulate` | Best first file to read |

---

## Short take

For your use case, the order of importance is probably:

1. `scripts/cts_demo_script.m`
2. `cts_model.m`
3. `cts_simulate.m`
4. `helper_randomfill.m`
5. `helper_electrondetect.m`
6. `helper_ctf.m`
7. `helper_particleatlas.m`

The GUI exists because the papers describe CTS as usable through either a graphical interface or the MATLAB command line, not because the method itself requires a GUI. CTS is described as MATLAB-based software that can be controlled from either the MATLAB command line or a dedicated graphical interface, while the 2025 paper again says users have control through either graphical or command-line interfaces. fileciteturn8file0 fileciteturn8file2

---

```text
Inspect the repo and explain the .fil format used in structures_filaments/.

I need:
1) which functions read .fil files
2) the exact schema / fields of the format
3) whether .fil wraps a PDB/CIF or defines filament placement metadata
4) how .fil differs from ordinary structure inputs
5) a minimal example parsed line by line from actin.fil
```
