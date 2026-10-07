"""Load CTS simulation runs into Dragonfly as deep-learning training data.

Run inside Dragonfly (2025.1), in its Python console, after editing the settings below:
    exec(open('/home/nataliya/cryotomosim_CTS/scripts/dragonfly_import_training_runs.py').read())
Start with COUNT = 2 and check the printed voxel counts before loading many runs.

MODE = 'pairs' makes two objects per run:
    <run>_tomo     the simulated tomogram (<run>/sim/5_recon_sim.mrc), grey values unchanged
    <run>_labels   Multi-ROI with 6 classes in a fixed order:
                   1 background, 2 microtubule, 3 actin, 4 cofilactin, 5 ribosome, 6 membrane
MODE = 'stack' puts the listed runs one after another along Z into ONE tomogram and ONE
Multi-ROI, so the Deep Learning Tool needs a single input/output pair. Only runs with the X/Y size
of the first run are used. Each run is scaled to mean 0, SD 1 first, because grey levels differ
between runs. The slice range of each run is written to <LIST_DIR>/<STACK_TITLE>_slices.csv.

Labels come from Atlas_<sub>.mrc + Atlas_<sub>.txt, matched by NAME, because the numbering differs
per run (Markdowns/atlas_labels_actin_cofilactin_mt.md). The converter scripts need not be run
first. Every voxel gets a class, background included, as Dragonfly's training requires. A class
that is missing from a run stays as an empty class in its usual place, so every Multi-ROI has the
same 6 classes in the same order, whatever run list is used. Runs in overfilled.txt are skipped.

Dragonfly calls used are those of Dragonfly's own code (Create Multi-ROI from ROIs, the MRC
reader, the watershed helper): Channel.setXSize..., setDataType, initializeData, getNDArray
(a view of the dataset's memory), getAsROIWithinRange; MultiROI.setLabelCount,
addVolumeROIToLabel (labels numbered from 1), setLabelName, setLabelColor, getLabelSize.
They were checked against the 2025.1 API (python/ORSModel/ors.pyi) but NOT run in Dragonfly:
the script was tested with Dragonfly's Python and a stand-in for these calls.

Memory: a 512x512x64 run needs about 64 MiB (tomogram) + 16 MiB (Multi-ROI) once loaded.
all5 = about 11 GiB, all5 + no_membrane = about 21 GiB. Loading stops when the RAM still
available would drop below MIN_FREE_GB. Training needs several times more, because Dragonfly
copies the training data and builds patch stacks.
"""
import csv
import os

import mrcfile
import numpy as np
from COMWrapper.ORS_def import CxvChannel_Data_Type
from ORSModel.ors import Channel, Color, MultiROI

## Settings
ROOT = '/mnt/big_data/CTS_actin_cofilactin_MT_simulation'
LIST_DIR = '/home/nataliya/cryotomosim_CTS/scripts/run_lists/actin_cofilactin_mt'
RUN_LISTS = ['all5.txt', 'no_membrane.txt']    # e.g. ['all5.txt', 'no_membrane.txt']
FIRST, COUNT = 0, None         # part of the combined list to load; COUNT = None loads to the end
MODE = 'pairs'              # 'pairs' or 'stack'
STACK_TITLE = 'cts_train'   # MODE 'stack': objects <STACK_TITLE>_tomo and <STACK_TITLE>_labels
SUB = 'sim'                 # 'sim' (noisy tomogram) or 'zero_dose_pair' (noise-free)
MIN_FREE_GB = 100           # RAM to leave free, in GiB

# Multi-ROI label k+1 = class k. Each class lists the atlas names merged into it, like the
# converters (scripts/cts_atlas_to_labels.sh/.m). Colours are 0-255.
CLASSES = [
    ('background', [], (128, 128, 128)),
    ('microtubule', ['neuroMT'], (0, 158, 115)),
    ('actin', ['actin_long'], (230, 159, 0)),
    ('cofilactin', ['cofilactin_long'], (213, 94, 0)),
    ('ribosome', ['ribo_4ujd'], (0, 114, 178)),
    ('membrane', ['vesicle'], (204, 121, 167)),
]


def read_list(name):
    path = os.path.join(LIST_DIR, name)
    if not os.path.isfile(path):
        return []
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def selected_runs():
    skip = set(read_list('overfilled.txt'))  # broken runs, 100 % labelled
    runs = []
    for name in RUN_LISTS:
        runs += [r for r in read_list(name) if r not in skip and r not in runs]
    return runs[FIRST:] if COUNT is None else runs[FIRST:FIRST + COUNT]


def available_gib():
    """RAM still available to the system (Linux /proc/meminfo), None if unknown."""
    try:
        with open('/proc/meminfo') as f:
            for line in f:
                if line.startswith('MemAvailable:'):
                    return int(line.split()[1]) / 2**20
    except OSError:
        pass
    return None


def run_shape(run):
    """(nz, ny, nx) and pixel size in A of a run's tomogram, from the header only."""
    path = os.path.join(ROOT, run, SUB, f'5_recon_{SUB}.mrc')
    with mrcfile.open(path, header_only=True, permissive=True) as m:
        return (int(m.header.nz), int(m.header.ny), int(m.header.nx)), float(m.voxel_size.x)


def read_run(run):
    """Tomogram (z, y, x float32) and class ids (z, y, x uint8) of one run."""
    folder = os.path.join(ROOT, run, SUB)
    with mrcfile.open(os.path.join(folder, f'5_recon_{SUB}.mrc'), permissive=True) as m:
        tomo = np.array(m.data, dtype=np.float32)
    with mrcfile.open(os.path.join(folder, f'Atlas_{SUB}.mrc'), permissive=True) as m:
        atlas = np.rint(m.data).astype(np.int32)
    with open(os.path.join(folder, f'Atlas_{SUB}.txt')) as f:
        names = [line.strip() for line in f if line.strip()]
    lut = np.zeros(len(names), np.uint8)  # atlas value v = line v+1 of the txt
    for k, (_, atlas_names, _) in enumerate(CLASSES):
        for name in atlas_names:
            if name in names:
                lut[names.index(name)] = k
    if atlas.shape != tomo.shape:
        raise ValueError(f'{run}: atlas {atlas.shape} and tomogram {tomo.shape} differ in size')
    return tomo, lut[atlas]


def new_channel(shape, pix, data_type, title):
    """Empty dataset of shape (nz, ny, nx); spacing in metres, as Dragonfly's MRC reader sets it."""
    nz, ny, nx = shape
    chan = Channel()
    chan.setXSize(nx)
    chan.setYSize(ny)
    chan.setZSize(nz)
    chan.setTSize(1)
    chan.setDataType(data_type)
    if not chan.initializeData():
        raise MemoryError(f'Dragonfly could not allocate {title} {shape}')
    chan.setXSpacing(pix * 1e-10)
    chan.setYSpacing(pix * 1e-10)
    chan.setZSpacing(pix * 1e-10)
    chan.setTitle(title)
    return chan


def new_multiroi(ids_chan, like, counts, title):
    """Multi-ROI on the grid of `like` with label k+1 = voxels of class k in ids_chan."""
    mroi = MultiROI()
    mroi.copyShapeFromStructuredGrid(like)
    mroi.setLabelCount(len(CLASSES))
    for k, (name, _, rgb) in enumerate(CLASSES):
        if counts[k]:
            roi = ids_chan.getAsROIWithinRange(k, k, None, None)
            if not mroi.addVolumeROIToLabel(k + 1, roi):
                raise RuntimeError(f'{title}: could not add class {name}')
            roi.deleteObject()
        mroi.setLabelName(k + 1, name)
        mroi.setLabelColor(k + 1, Color(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255,
                                        Color.OPACITY_FLAG.IN_RANGE_OPACITY.value))
    mroi.setTitle(title)
    sizes = [mroi.getLabelSize(k + 1) for k in range(len(CLASSES))]
    if sizes != [int(c) for c in counts] or mroi.getUnlabeledVoxelCount() != 0:
        raise RuntimeError(f'{title}: class sizes in Dragonfly {sizes} differ from the atlas '
                           f'{[int(c) for c in counts]}; stopping')
    return mroi


def make_pair(tomo, ids, pix, title):
    """Publish <title>_tomo and <title>_labels; returns the class voxel counts."""
    counts = np.bincount(ids.ravel(), minlength=len(CLASSES))
    chan = new_channel(tomo.shape, pix, CxvChannel_Data_Type.CXVCHANNEL_DATA_TYPE_FLOAT, f'{title}_tomo')
    chan.getNDArray(0)[...] = tomo
    ids_chan = new_channel(ids.shape, pix, CxvChannel_Data_Type.CXVCHANNEL_DATA_TYPE_UNSIGNED_BYTE,
                           f'{title}_ids')
    ids_chan.setAsTemporaryObject()
    ids_chan.getNDArray(0)[...] = ids
    mroi = new_multiroi(ids_chan, chan, counts, f'{title}_labels')
    ids_chan.deleteObject()
    chan.publish()
    mroi.publish()
    return counts


def load_pairs(runs):
    existing = {o.getTitle() for o in Channel.getAllInstances()}
    loaded = 0
    for i, run in enumerate(runs, start=1):
        if f'{run}_tomo' in existing:
            print(f'{i}/{len(runs)} {run}: already loaded, skipped')
            continue
        shape, pix = run_shape(run)
        need = np.prod(shape) * 16 / 2**30  # kept: tomogram + Multi-ROI; temporary: file copies, ids, ROI
        free = available_gib()
        if free is not None and free - need < MIN_FREE_GB:
            print(f'Stopped before {run}: {free:.0f} GiB RAM available, MIN_FREE_GB = {MIN_FREE_GB}')
            break
        tomo, ids = read_run(run)
        counts = make_pair(tomo, ids, pix, run)
        loaded += 1
        print(f'{i}/{len(runs)} {run}: {pix:.3f} A, {shape[2]}x{shape[1]}x{shape[0]}, voxels per class '
              f'{dict(zip([c[0] for c in CLASSES], counts.tolist()))}')
    print(f'Loaded {loaded} runs as <run>_tomo + <run>_labels')


def load_stack(runs):
    shapes = {run: run_shape(run) for run in runs}
    ny, nx = shapes[runs[0]][0][1:]
    keep = [r for r in runs if shapes[r][0][1:] == (ny, nx)]
    if len(keep) < len(runs):
        print(f'Not stacked, X/Y size differs from {nx}x{ny}: {[r for r in runs if r not in keep]}')
    nz = sum(shapes[r][0][0] for r in keep)
    pix = shapes[keep[0]][1]
    need = nz * ny * nx * 7 / 2**30  # bytes per voxel: tomogram 4, temporary ids 1 and ROI 1, Multi-ROI 1
    free = available_gib()
    if free is not None and free - need < MIN_FREE_GB:
        raise MemoryError(f'Stack needs about {need:.1f} GiB, {free:.0f} GiB available, '
                          f'MIN_FREE_GB = {MIN_FREE_GB}; use fewer runs')
    chan = new_channel((nz, ny, nx), pix, CxvChannel_Data_Type.CXVCHANNEL_DATA_TYPE_FLOAT,
                       f'{STACK_TITLE}_tomo')
    ids_chan = new_channel((nz, ny, nx), pix, CxvChannel_Data_Type.CXVCHANNEL_DATA_TYPE_UNSIGNED_BYTE,
                           f'{STACK_TITLE}_ids')
    ids_chan.setAsTemporaryObject()
    tomo_view, ids_view = chan.getNDArray(0), ids_chan.getNDArray(0)
    counts = np.zeros(len(CLASSES), np.int64)
    table, z = [], 0
    for i, run in enumerate(keep, start=1):
        tomo, ids = read_run(run)
        sd = tomo.std()
        tomo_view[z:z + len(tomo)] = (tomo - tomo.mean()) / (sd if sd > 0 else 1)
        ids_view[z:z + len(ids)] = ids
        counts += np.bincount(ids.ravel(), minlength=len(CLASSES))
        table.append((run, z, z + len(tomo) - 1, round(shapes[run][1], 4)))
        print(f'{i}/{len(keep)} {run}: slices {z}-{z + len(tomo) - 1}, pixel {shapes[run][1]:.3f} A')
        z += len(tomo)
    mroi = new_multiroi(ids_chan, chan, counts, f'{STACK_TITLE}_labels')
    ids_chan.deleteObject()
    chan.publish()
    mroi.publish()
    out = os.path.join(LIST_DIR, f'{STACK_TITLE}_slices.csv')
    with open(out, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['run', 'first_slice', 'last_slice', 'pixel_A'])
        writer.writerows(table)
    print(f'Stack {STACK_TITLE}: {len(keep)} runs, {nx}x{ny}x{nz}, voxels per class '
          f'{dict(zip([c[0] for c in CLASSES], counts.tolist()))}; slice table {out}')
    print(f'The stack spacing is that of {keep[0]} ({pix:.3f} A); the runs have different pixel sizes.')


def main():
    runs = selected_runs()
    if not runs:
        raise ValueError(f'No runs selected from {RUN_LISTS} in {LIST_DIR}')
    print(f'{len(runs)} runs from {RUN_LISTS}, MODE = {MODE}, SUB = {SUB}')
    if MODE == 'pairs':
        load_pairs(runs)
    elif MODE == 'stack':
        load_stack(runs)
    else:
        raise ValueError(f"MODE must be 'pairs' or 'stack', not {MODE!r}")


main()
