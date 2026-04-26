# Local fixes

## 2026-04-23
### param_model GUI crash
Error:
Index exceeds the number of array elements...

Cause:
param struct has 11 fields, GUI prompts only 10 values.

Local fix:
```default = struct2cell(param);
for i = 1:numel(default)
    default{i} = num2str(default{i});
end

default = default(1:numel(prompt));   % keep defaults aligned with prompts

p = inputdlg(prompt,ptitle,[1 40],default);
if isempty(p)
    error('param_model:cancelled','Model parameter dialog was cancelled.');
end

fn = fieldnames(param);
fn = fn(1:numel(p));                  % keep fields aligned with GUI inputs

for i = 1:numel(fn)
    tmp = str2double(p{i});
    if isnan(tmp), tmp = str2num(p{i}); end
    if i == 5, tmp = p{i}; end
    param.(fn{i}) = tmp;
end\
```

Status:
likely real repo bug

## 2026-04-23
### pdb loading crash
Error:
Loading layer 1 structures 
Loading input 1 read: 6ks8 
Unrecognized function or variable 'helper_pdbparse'. 
Error in helper_pdb2vol (line 27) data = helper_pdbparse(pdb); 
Error in helper_input (line 91) [tmp.vol,tmp.sumvol,names] = helper_pdb2vol(list{i},pixelsize,trim,centering,sv); 
Error in param_model (line 122) layers{i} = helper_input('gui',param.pix);

Cause: 
subfolders are not in matlab path



## 2026-04-26
### Tilt series parameters GUI vs expectation mismatch
Error:
Loading layer 1 structures 
Loading input 1 read: 6ks8  .mat exists,  .mat exists, generating at 12 A   done
Loading layer 2 structures 
Loading input 1 read: 6ks8  .mat exists,  .mat exists, generating at 12 A   done
Generating carbon film    complete 
Layer 1, attempting 750 placements up to density 0.3:  
30,60,89,117,145,174,201,225,250,278,301,325,346,366,379,392,404,421,437,454,469,482,495,505,515,
Placed 515 particles, failed 235 attempted placements, final density 0.245586
Layer 2, attempting 1250 placements up to density 0.5:  
14,28,45,58,71,79,90,103,113,123,135,143,153,160,171,177,184,192,195,198,207,213,218,226,229,
Placed 229 particles, failed 1021 attempted placements, final density 0.331177
Generating vitreous ice   done 
Index exceeds the number of array elements. Index must not exceed 14.

Error in param_simulate (line 82)
        param.(fn{i}) = str2double(p{i});

