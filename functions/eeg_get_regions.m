function [regions, regionNames] = eeg_get_regions()
% EEG_GET_REGIONS  Load and cache regions.json → {name, channels} cell.
%
% regions: {nR x 2} cell { 'FRONT_LEFT', {'Fp1','F3',...}; ... }
% regionNames: nR x 1 string of region names

persistent cachedRegions cachedNames

if ~isempty(cachedRegions)
    regions     = cachedRegions;
    regionNames = cachedNames;
    return
end

jsonPath = eeg_get_data_path('regions.json');
fid = fopen(jsonPath, 'r');
if fid < 0
    error('Could not open regions.json at: %s', jsonPath);
end
raw = fread(fid, inf);
fclose(fid);

regionsStruct = jsondecode(char(raw'));
fields = fieldnames(regionsStruct);
nR = numel(fields);

regions     = cell(nR, 2);
regionNames = strings(nR,1);

for i = 1:nR
    regionNames(i) = string(fields{i});
    regions{i,1}   = fields{i};
    regions{i,2}   = regionsStruct.(fields{i});
end

cachedRegions = regions;
cachedNames   = regionNames;
end
