function summary = cts_atlas_to_labels(root,opt)
% summary = cts_atlas_to_labels(root,opt)
% converts CTS atlases into a fixed set of named classes, with the same class ids in every run
% Atlas_<suffix>.mrc stores value v for the label on line v+1 of Atlas_<suffix>.txt (line 1 is
% background). The numbering changes between runs, so classes are matched by atlas name.
% Atlas labels not listed in opt.classes are written as background.
%
% root          a run folder (contains sim/Atlas_sim.txt) or a folder of run folders
% opt.runs      cell array of run folder names inside root, default all runs found
% opt.outroot   default '' writes into <run>/labels, otherwise into <outroot>/<run>
% opt.overwrite default 0 skips runs that already have labels.json
% opt.masks     default 1 also writes mask_<class>.mrc (0/1) for every class
% opt.imod      default 1 also writes particles.mod from zcoords_<label>.csv with IMOD point2model
% opt.classes   struct array with fields name, atlas (cell of atlas names merged into the class),
%               color (rgb 0-255) and radius (A, sphere size of csv points in 3dmod, 0 for none)
%
% outputs per run: labels.mrc (bytes, 0 background, 1..N classes), mask_<class>.mrc, labels.json,
% particles.mod (object k = class k). Same outputs as scripts/cts_atlas_to_labels.sh
% see Markdowns/atlas_labels_actin_cofilactin_mt.md for what the atlas labels mean
% ex
% cts_atlas_to_labels('/mnt/big_data/CTS_actin_cofilactin_MT_simulation','runs',{'00297','00300'})

arguments
    root = '/mnt/big_data/CTS_actin_cofilactin_MT_simulation'
    opt.runs = {}
    opt.outroot = ''
    opt.overwrite = 0
    opt.masks = 1
    opt.imod = 1
    opt.classes = struct('name',{'microtubule','actin','cofilactin','ribosome','membrane'}, ...
        'atlas',{{'neuroMT'},{'actin_long'},{'cofilactin_long'},{'ribo_4ujd'},{'vesicle'}}, ...
        'color',{[0 158 115],[230 159 0],[213 94 0],[0 114 178],[204 121 167]}, ...
        'radius',{125,40,50,130,0})
end
root = abspath(char(root));
if ~isempty(opt.outroot), opt.outroot = abspath(char(opt.outroot)); end

% collect run folders
if isrun(root)
    runs = {root};
elseif isempty(opt.runs)
    d = dir(root); d = d([d.isdir] & ~startsWith({d.name},'.'));
    runs = fullfile(root,{d.name}); runs = runs(cellfun(@isrun,runs));
else
    runs = fullfile(root,cellstr(opt.runs));
end
if isempty(runs), error('No CTS run folders with an atlas found in %s',root); end

if opt.imod==1 && system('which point2model >/dev/null 2>&1')~=0
    warning('IMOD point2model not found on the path, skipping particles.mod'); opt.imod = 0;
end

summary = struct('run',{},'out',{},'absent',{});
for i=1:numel(runs)
    summary(end+1) = convertrun(runs{i},opt); %#ok<AGROW>
end
end

%% internal functions
function info = convertrun(run,opt)
[~,name] = fileparts(run);
if isfile(fullfile(run,'sim','Atlas_sim.txt')), sub = 'sim'; else, sub = 'zero_dose_pair'; end
atlasmrc = fullfile(run,sub,append('Atlas_',sub,'.mrc'));
atlastxt = fullfile(run,sub,append('Atlas_',sub,'.txt'));
ref = fullfile(run,sub,append('5_recon_',sub,'.mrc')); % 3dmod reference for the model coordinates
if ~isfile(ref), ref = atlasmrc; end
if isempty(opt.outroot), out = fullfile(run,'labels'); else, out = fullfile(opt.outroot,name); end
info = struct('run',name,'out',out,'absent',{{}});
if isfile(fullfile(out,'labels.json')) && opt.overwrite==0
    fprintf('%s: labels exist, skipping (set overwrite to redo)\n',name); return
end
if ~isfolder(out), mkdir(out); end

[atlas,s] = ReadMRC(atlasmrc);
pix = round(s.pixA,4);
names = strtrim(splitlines(fileread(atlastxt))); names = names(~cellfun(@isempty,names));

% lookup table from atlas value (+1) to class id, matched by name in the order given per class
cl = opt.classes;
lut = zeros(numel(names),1,'uint8');
for k=1:numel(cl)
    [tf,loc] = ismember(cl(k).atlas,names); loc = loc(tf);
    lut(loc) = k;
    cl(k).labels = names(loc)'; cl(k).values = loc(:)'-1;
end
labels = lut(round(atlas)+1); % same size as atlas, 0 for every unlisted label
WriteMRC(labels,pix,fullfile(out,'labels.mrc'),0);
counts = accumarray(double(labels(:))+1,1,[numel(cl)+1,1]);

if opt.masks==1
    for k=1:numel(cl)
        WriteMRC(uint8(labels==k),pix,fullfile(out,append('mask_',cl(k).name,'.mrc')),0);
    end
end

% csv points -> "object contour x y z radius" in pixels (IMOD -zcoord convention)
pts = zeros(0,6); ncsv = zeros(1,numel(cl));
for k=1:numel(cl)
    if cl(k).radius==0, continue, end
    for j=1:numel(cl(k).atlas)
        f = fullfile(run,append('zcoords_',cl(k).atlas{j},'.csv'));
        if ~isfile(f), continue, end
        c = readmatrix(f,'FileType','text','NumHeaderLines',0);
        n = size(c,1); ncsv(k) = ncsv(k)+n;
        pts = [pts; repmat([k 1],n,1), c(:,1:3)/pix, repmat(cl(k).radius/pix,n,1)]; %#ok<AGROW>
    end
end
modname = NaN; % written as null
if opt.imod==1 && ~isempty(pts)
    ptsfile = fullfile(out,'.points.txt');
    fid = fopen(ptsfile,'w'); fprintf(fid,'%d %d %.3f %.3f %.3f %.2f\n',pts'); fclose(fid);
    cmd = append('point2model -scat -zcoord -sizes -sphere 1 -image "',ref,'"');
    for k=1:numel(cl)
        cmd = append(cmd,' -name ',cl(k).name,' -color ',strjoin(string(cl(k).color),','));
    end
    cmd = append(cmd,' "',ptsfile,'" "',fullfile(out,'particles.mod'),'"');
    [st,msg] = system(cmd); delete(ptsfile);
    if st~=0, warning('point2model failed for %s: %s',name,msg); else, modname = 'particles.mod'; end
end

% labels.json, arrays are wrapped in cells so single entries stay json arrays
classes = cell(1,numel(cl)+1);
classes{1} = jsonclass(0,'background',{},{},true,counts(1),[0 0 0],0,NaN);
for k=1:numel(cl)
    mask = NaN; if opt.masks==1, mask = append('mask_',cl(k).name,'.mrc'); end
    classes{k+1} = jsonclass(k,cl(k).name,cl(k).labels,num2cell(cl(k).values),~isempty(cl(k).values),...
        counts(k+1),cl(k).color,ncsv(k),mask);
end
j = struct('run',name,'atlas_mrc',atlasmrc,'atlas_txt',atlastxt,'reference_mrc',ref,...
    'pixel_size_A',pix,'size_xyz',size(atlas),'labels_mrc','labels.mrc','imod_model',modname);
j.classes = classes;
fid = fopen(fullfile(out,'labels.json'),'w'); fprintf(fid,'%s\n',jsonencode(j,'PrettyPrint',true)); fclose(fid);

info.absent = {cl(cellfun(@isempty,{cl.values})).name};
absent = ''; if ~isempty(info.absent), absent = append(', absent: ',strjoin(info.absent,' ')); end
fprintf('%s: pixel %.4f A, %ix%ix%i%s -> %s\n',name,pix,size(atlas),absent,out);
end

function c = jsonclass(id,name,labels,values,present,voxels,color,csvpoints,mask)
c = struct('id',id,'name',name,'atlas_labels',{labels},'atlas_values',{values},'present',present,...
    'voxels',voxels,'color',color,'csv_points',csvpoints,'mask_mrc',mask);
end

function tf = isrun(folder)
tf = isfile(fullfile(folder,'sim','Atlas_sim.txt')) || ...
    isfile(fullfile(folder,'zero_dose_pair','Atlas_zero_dose_pair.txt'));
end

function p = abspath(p)
if ~startsWith(p,filesep), p = fullfile(pwd,p); end
end
