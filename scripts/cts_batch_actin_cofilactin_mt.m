% Batch generation for actin/cofilactin/microtubule/ribosome cytoplasm tomograms.
% Run from MATLAB. The prompt asks for the number of primary tomograms; each
% primary tomogram also gets a matched zero-dose simulation.

clearvars;
rng('shuffle');

%% Paths
ctsRoot = '/home/nataliya/cryotomosim_CTS';
modelRoot = fullfile(ctsRoot, 'synthetic_cytoplasm_models');
outputRoot = '/mnt/big_data/CTS_actin_cofilactin_MT_simulation';

addpath(ctsRoot);
addpath(fullfile(ctsRoot, 'WIP'));

if ~isfolder(outputRoot)
    error('Output folder does not exist: %s', outputRoot);
end

%% Parameter grids and defaults
tomogramSize = [512, 512, 64];
tilts = -60:1:60;
defocusChoices = -7:1:-2;
doseChoices = 50:10:150;
defaultPixelGridCount = 20;
defaultPrimaryTomograms = numel(defocusChoices) * numel(doseChoices) * defaultPixelGridCount * 2;

prompt = sprintf('Number of primary tomograms [%d]: ', defaultPrimaryTomograms);
nPrimaryTomograms = input(prompt);
if isempty(nPrimaryTomograms)
    nPrimaryTomograms = defaultPrimaryTomograms;
end
nPrimaryTomograms = round(nPrimaryTomograms);

%% Model composition
baseLayerFiles = cell(6, 1);
baseLayerFiles{1} = {firstExisting(modelRoot, 'layer 2', ...
    {'neuroMT.cytosol.assembly.pdb', 'neuroMT.cytosol.assembly.mat'})};
baseLayerFiles{2} = {firstExisting(modelRoot, 'layer 2', ...
    {'actin_long.bundle.pdb', 'actin_long.bundle.mat'})};
baseLayerFiles{3} = {firstExisting(modelRoot, 'layer 2', ...
    {'cofilactin_long.bundle.pdb', 'cofilactin_long.bundle.mat'})};
baseLayerFiles{4} = {firstExisting(modelRoot, 'layer 2', ...
    {'ribo_4ujd.cytosol.cluster.pdb', 'ribo_4ujd.cytosol.cluster.mat'})};
baseLayerFiles{5} = allModelMats(fullfile(modelRoot, 'layer 3'));
baseLayerFiles{6} = allModelMats(fullfile(modelRoot, 'layer 4'));

membraneLayerFiles = allMembraneModelMats(fullfile(modelRoot, 'layer 1'));
membraneProbability = 0.7;

particleDensity = 0.8;
baseIters = [300, 1000, 1000, 500, 4000, 4000];
membraneIters = 200;
manifestPath = fullfile(outputRoot, 'batch_manifest.csv');
ensureManifest(manifestPath);

%% Batch loop
for runIndex = 1:nPrimaryTomograms
    runName = sprintf('%05d', runIndex);
    runFolder = fullfile(outputRoot, runName);
    simRecon = fullfile(runFolder, 'sim', '5_recon_sim.mrc');
    zeroDoseRecon = fullfile(runFolder, 'zero_dose_pair', '5_recon_zero_dose_pair.mrc');

    if isRunComplete(runFolder, runName)
        metadata = jsondecode(fileread(fullfile(runFolder, 'metadata.json')));
        appendManifestFromMetadata(manifestPath, metadata);
        fprintf('\nCTS batch run %d / %d is complete; skipping\n', runIndex, nPrimaryTomograms);
        continue
    elseif isfolder(runFolder)
        metadataFile = fullfile(runFolder, 'metadata.json');
        atomModelFile = fullfile(runFolder, [runName, '.atom.mat']);
        modelOutfile = fullfile(runFolder, [runName, '.mat']);
        if ~isfile(metadataFile) || ~isfile(atomModelFile)
            error('Run folder exists but cannot be resumed cleanly: %s', runFolder);
        end
        metadata = jsondecode(fileread(metadataFile));
        pix = metadata.pixel_size_A;
        defocus = metadata.defocus_um;
        dose = metadata.total_dose_e_per_A2;
        memCount = metadata.actual_membrane_count;
        fprintf('\nCTS batch run %d / %d already has a model; resuming simulations\n', ...
            runIndex, nPrimaryTomograms);
    else
        pix = round((3.5 + rand() * (20 - 3.5)) * 1000) / 1000;
        defocus = defocusChoices(randi(numel(defocusChoices)));
        dose = doseChoices(randi(numel(doseChoices)));

        fprintf('\nCTS batch run %d / %d\n', runIndex, nPrimaryTomograms);
        fprintf('  pixel size: %.3f A, defocus: %d um, dose: %d e/A^2\n', pix, defocus, dose);

        hasMembraneLayer = rand() < membraneProbability;
        if hasMembraneLayer
            layerFiles = [{membraneLayerFiles}; baseLayerFiles];
            runIters = [membraneIters, baseIters];
            fprintf('  membrane protein layer: yes (%d files)\n', numel(membraneLayerFiles));
        else
            layerFiles = baseLayerFiles;
            runIters = baseIters;
            fprintf('  membrane protein layer: no\n');
        end

        modelParam = makeModelParam(pix, layerFiles, particleDensity, runIters);
        [cts, ~, ~, ~, ~, ~, ~, ~, ~, modelOutfile] = cts_model_atomic( ...
            tomogramSize, modelParam, 'outdir', outputRoot, 'dynamotable', 1, 'basename', runName);

        [modelPath, modelName] = fileparts(char(modelOutfile));
        atomModelFile = fullfile(modelPath, strcat(modelName, '.atom.mat'));
        memCount = cts.param.mem;
        metadata = makeMetadata(runIndex, runName, tomogramSize, pix, defocus, dose, ...
            tilts, modelParam, memCount, layerFiles, modelOutfile, ...
            hasMembraneLayer, membraneProbability);
        writeJson(fullfile(modelPath, 'metadata.json'), metadata);
    end

    simParam = makeSimParam(pix, tilts, dose, defocus);
    if isfile(simRecon)
        fprintf('  sim reconstruction exists; skipping nonzero-dose simulation\n');
    else
        cts_simulate_atomic(atomModelFile, simParam, 'suffix', 'sim', 'runname', 'sim');
    end

    zeroDoseParam = simParam;
    zeroDoseParam.dose = 0;
    if isfile(zeroDoseRecon)
        fprintf('  zero-dose reconstruction exists; skipping zero-dose pair\n');
    else
        cts_simulate_atomic(atomModelFile, zeroDoseParam, 'suffix', 'zero_dose_pair', 'runname', 'zero_dose_pair');
    end

    if isRunComplete(runFolder, runName)
        appendManifestIfMissing(manifestPath, runIndex, pix, defocus, dose, memCount, modelOutfile);
    else
        warning('Run %s is still incomplete after processing; not adding it to manifest.', runName);
    end
end

fprintf('\nCompleted %d primary tomograms and %d total simulations including zero-dose pairs.\n', ...
    nPrimaryTomograms, nPrimaryTomograms * 2);

%% Local helper functions
function param = makeModelParam(pix, layerFiles, particleDensity, iters)
param.pix = pix;
param.layers = cell(size(layerFiles));
for layerIndex = 1:numel(layerFiles)
    fprintf('Loading model layer %d with %d files\n', layerIndex, numel(layerFiles{layerIndex}));
    param.layers{layerIndex} = helper_input(layerFiles{layerIndex}, pix, 0);
end
param.density = particleDensity * ones(1, numel(layerFiles));
param.iters = iters;
param.constraint = '   ';
param.grid = 0;
param.mem = 6;
param.filaments = 0;
param.beads = 0;
param.ice = 1;
param.bare = 0;
end

function param = makeSimParam(pix, tilts, dose, defocus)
param = param_simulate( ...
    'voltage', 300, ...
    'aberration', 2.7, ...
    'sigma', 1, ...
    'defocus', defocus, ...
    'tilt', tilts, ...
    'dose', dose, ...
    'tiltscheme', 'symmetric', ...
    'pix', pix, ...
    'tiltax', 'Y', ...
    'raddamage', 1, ...
    'scatter', 1, ...
    'tilterr', 0.3, ...
    'ice', 1);
end

function files = allModelMats(folderPath)
listing = dir(fullfile(folderPath, '*.mat'));
if isempty(listing)
    error('No .mat model files found in %s', folderPath);
end
names = sort({listing.name});
files = cellfun(@(name) fullfile(folderPath, name), names, 'UniformOutput', false);
end

function files = allMembraneModelMats(folderPath)
listing = dir(fullfile(folderPath, '*.mat'));
if isempty(listing)
    error('No .mat membrane model files found in %s', folderPath);
end
names = sort({listing.name});
keep = cellfun(@(name) contains(lower(name), 'membrane'), names);
names = names(keep);
if isempty(names)
    error('No .mat files with a membrane filename flag found in %s', folderPath);
end
files = cellfun(@(name) fullfile(folderPath, name), names, 'UniformOutput', false);
end

function path = firstExisting(rootFolder, subFolder, candidates)
for i = 1:numel(candidates)
    path = fullfile(rootFolder, subFolder, candidates{i});
    if isfile(path)
        return;
    end
end
error('None of the candidate files exist in %s: %s', ...
    fullfile(rootFolder, subFolder), strjoin(candidates, ', '));
end

function ensureManifest(manifestPath)
if ~isfile(manifestPath)
    fid = fopen(manifestPath, 'w');
    fprintf(fid, 'run_index,pixel_size_A,defocus_um,total_dose_e_per_A2,membrane_count,model_file\n');
    fclose(fid);
end
end

function tf = isRunComplete(runFolder, runName)
tf = isfile(fullfile(runFolder, 'metadata.json')) && ...
    isfile(fullfile(runFolder, [runName, '.mat'])) && ...
    isfile(fullfile(runFolder, [runName, '.atom.mat'])) && ...
    isfile(fullfile(runFolder, 'sim', '5_recon_sim.mrc')) && ...
    isfile(fullfile(runFolder, 'zero_dose_pair', '5_recon_zero_dose_pair.mrc'));
end

function appendManifestFromMetadata(manifestPath, metadata)
if ~manifestHasRun(manifestPath, metadata.run_index)
    appendManifest(manifestPath, metadata.run_index, metadata.pixel_size_A, ...
        metadata.defocus_um, metadata.total_dose_e_per_A2, ...
        metadata.actual_membrane_count, metadata.model_file);
end
end

function appendManifestIfMissing(manifestPath, runIndex, pix, defocus, dose, memCount, modelOutfile)
if ~manifestHasRun(manifestPath, runIndex)
    appendManifest(manifestPath, runIndex, pix, defocus, dose, memCount, modelOutfile);
end
end

function tf = manifestHasRun(manifestPath, runIndex)
tf = false;
if ~isfile(manifestPath)
    return
end
txt = fileread(manifestPath);
tf = ~isempty(regexp(txt, ['(^|\n)', num2str(runIndex), ','], 'once'));
end

function appendManifest(manifestPath, runIndex, pix, defocus, dose, memCount, modelOutfile)
fid = fopen(manifestPath, 'a');
fprintf(fid, '%d,%.3f,%d,%d,%d,"%s"\n', runIndex, pix, defocus, dose, memCount, char(modelOutfile));
fclose(fid);
end

function metadata = makeMetadata(runIndex, runName, tomogramSize, pix, defocus, dose, ...
    tilts, modelParam, actualMemCount, layerFiles, modelOutfile, ...
    hasMembraneLayer, membraneProbability)
metadata.run_index = runIndex;
metadata.run_name = runName;
metadata.model_file = modelOutfile;
metadata.atom_model_file = strrep(modelOutfile, '.mat', '.atom.mat');
metadata.tomogram_size_voxels = tomogramSize;
metadata.pixel_size_A = pix;
metadata.defocus_um = defocus;
metadata.total_dose_e_per_A2 = dose;
metadata.zero_dose_pair = true;
metadata.tilts_degrees = tilts;
metadata.voltage_kV = 300;
metadata.spherical_aberration_mm = 2.7;
metadata.envelope_sigma = 1;
metadata.radiation_damage = 1;
metadata.tilt_error = 0.3;
metadata.tilt_scheme = 'symmetric';
metadata.requested_membrane_count = modelParam.mem;
metadata.actual_membrane_count = actualMemCount;
metadata.has_membrane_layer = hasMembraneLayer;
metadata.membrane_probability = membraneProbability;
metadata.ice = modelParam.ice;
metadata.particle_density = modelParam.density;
metadata.layer_iterations = modelParam.iters;
metadata.layers = layerFiles;
end

function writeJson(filename, data)
fid = fopen(filename, 'w');
fprintf(fid, '%s', jsonencode(data));
fclose(fid);
end
