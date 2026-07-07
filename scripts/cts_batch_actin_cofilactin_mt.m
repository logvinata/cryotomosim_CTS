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
tomogramSize = [256, 256, 64];
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
layerFiles = cell(6, 1);
layerFiles{1} = {firstExisting(modelRoot, 'layer 2', ...
    {'neuroMT.cytosol.assembly.pdb', 'neuroMT.cytosol.assembly.mat'})};
layerFiles{2} = {firstExisting(modelRoot, 'layer 2', ...
    {'actin_long.bundle.pdb', 'actin_long.bundle.mat'})};
layerFiles{3} = {firstExisting(modelRoot, 'layer 2', ...
    {'cofilactin_long.bundle.pdb', 'cofilactin_long.bundle.mat'})};
layerFiles{4} = {firstExisting(modelRoot, 'layer 2', ...
    {'ribo_4ujd.cytosol.cluster.pdb', 'ribo_4ujd.cytosol.cluster.mat'})};
layerFiles{5} = allModelMats(fullfile(modelRoot, 'layer 3'));
layerFiles{6} = allModelMats(fullfile(modelRoot, 'layer 4'));

particleDensity = 0.8;
iters = [1000, 1000, 1000, 2000, 4000, 8000];
manifestPath = fullfile(outputRoot, 'batch_manifest.csv');
writeManifestHeader(manifestPath);

%% Batch loop
for runIndex = 1:nPrimaryTomograms
    pix = round((0.76 + rand() * (20 - 0.76)) * 1000) / 1000;
    defocus = defocusChoices(randi(numel(defocusChoices)));
    dose = doseChoices(randi(numel(doseChoices)));
    suffix = sprintf('act_cofil_MT_%05d_pix_%06.3f_df_%+03d_dose_%03d', ...
        runIndex, pix, defocus, dose);
    suffix = strrep(suffix, '.', 'p');
    suffix = strrep(suffix, '+', 'p');
    suffix = strrep(suffix, '-', 'm');

    fprintf('\nCTS batch run %d / %d\n', runIndex, nPrimaryTomograms);
    fprintf('  pixel size: %.3f A, defocus: %d um, dose: %d e/A^2\n', pix, defocus, dose);

    modelParam = makeModelParam(pix, layerFiles, particleDensity, iters);
    [cts, ~, ~, ~, ~, ~, ~, ~, ~, modelOutfile] = cts_model_atomic( ...
        tomogramSize, modelParam, 'suffix', suffix, 'outdir', outputRoot, 'dynamotable', 1);

    [modelPath, modelName] = fileparts(modelOutfile);
    atomModelFile = fullfile(modelPath, [modelName, '.atom.mat']);

    simParam = makeSimParam(pix, tilts, dose, defocus);
    cts_simulate_atomic(atomModelFile, simParam, 'suffix', sprintf('dose_%03d', dose));

    zeroDoseParam = simParam;
    zeroDoseParam.dose = 0;
    cts_simulate_atomic(atomModelFile, zeroDoseParam, 'suffix', 'dose_000_pair');

    appendManifest(manifestPath, runIndex, pix, defocus, dose, cts.param.mem, modelOutfile);
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

function writeManifestHeader(manifestPath)
fid = fopen(manifestPath, 'w');
fprintf(fid, 'run_index,pixel_size_A,defocus_um,total_dose_e_per_A2,membrane_count,model_file\n');
fclose(fid);
end

function appendManifest(manifestPath, runIndex, pix, defocus, dose, memCount, modelOutfile)
fid = fopen(manifestPath, 'a');
fprintf(fid, '%d,%.3f,%d,%d,%d,"%s"\n', runIndex, pix, defocus, dose, memCount, modelOutfile);
fclose(fid);
end
