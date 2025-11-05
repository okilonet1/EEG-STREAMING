function regionColors = eeg_region_colors(EEG)
% EEG_REGION_COLORS - Reduce EEG channels into 16 brain regions and map to colors.
% Usage:
%    regionColors = eeg_region_colors(EEG)
%
% EEG can be:
%   - an EEGLAB EEG structure (with EEG.data, EEG.chanlocs)
%   - or a numeric matrix [nChannels x nSamples] with matching channel labels below.

%% --- Define brain region mapping ---
fid = fopen('regions.json');
raw = fread(fid, inf);
str = char(raw');
fclose(fid);

regionsStruct = jsondecode(str);

fields = fieldnames(regionsStruct);
regions = cell(length(fields), 2);

for i = 1:length(fields)
    regions{i,1} = fields{i};
    regions{i,2} = regionsStruct.(fields{i});
end

%% --- Extract data & labels ---
if isstruct(EEG)
    data = double(EEG.data);
    labels = upper({EEG.chanlocs.labels});
else
    data = EEG;
    error('Need channel labels to map regions.');
end

%% --- Compute mean amplitude per region ---
nR = size(regions,1);
regionVals = zeros(1,nR);

for r = 1:nR
    chans = upper(regions{r,2});
    idx = find(ismember(labels,chans));
    if isempty(idx)
        regionVals(r) = NaN;
    else
        % Use RMS to represent power over time
        regionVals(r) = sqrt(mean(mean(data(idx,:).^2,2)));
    end
end

% Normalize values to [0,1]
regionVals = regionVals - min(regionVals,[],2,'omitnan');
regionVals = regionVals ./ max(regionVals,[],2,'omitnan');

%% --- Map amplitude to color ---
% We'll use hue = fixed (blue -> high power), intensity = value.
colormapFunc = @(x) [x, 0.3*x, 1-x];  % blue→cyan→white gradient
regionColors = zeros(nR,3);

for r = 1:nR
    val = regionVals(r);
    if isnan(val)
        regionColors(r,:) = [0.5 0.5 0.5]; % grey for missing
    else
        regionColors(r,:) = colormapFunc(val);
    end
end

%% --- Display ---
figure('Name','EEG Region Color Map','Color','w');
barh(regionVals,'FaceColor','flat','CData',regionColors);
yticklabels(regions(:,1));
xlabel('Normalized Power');
title('16 Brain Regions → Color Intensity');
set(gca,'YDir','reverse');
end
