% setup_cts_path.m
repo_root = fileparts(mfilename('fullpath'));

addpath(repo_root);
addpath(fullfile(repo_root,'scripts'));
addpath(fullfile(repo_root,'deprec'));
addpath(fullfile(repo_root,'structures_filaments'));
addpath(genpath(fullfile(repo_root,'WIP')));  % fix for "Unrecognized function or variable 'helper_pdbparse'"