function regionColors = eeg_region_colors_amplitude(EEG)
% EEG_REGION_COLORS_AMPLITUDE
% Reduce EEG channels into 16 brain regions and map to colors.
%
% Usage:
%    regionColors = eeg_region_colors_amplitude(EEG)
%
% EEG can be:
%   - an EEGLAB EEG structure (with EEG.data, EEG.chanlocs)

%% --- Load region definitions via shared helper ---
[regions, regionNames] = eeg_get_regions();
nR = size(regions,1);

%% --- Extract data & labels ---
if isstruct(EEG)
    data   = double(EEG.data);
    labels = upper(string({EEG.chanlocs.labels}));
else
    error('EEG must be an EEGLAB struct with .data and .chanlocs.labels');
end

%% --- Compute RMS amplitude per region ---
regionVals = nan(1,nR);

for r = 1:nR
    chans = upper(string(regions{r,2}));
    idx   = find(ismember(labels, chans));
    if isempty(idx)
        regionVals(r) = NaN;
    else
        % RMS across time and channels
        regionVals(r) = sqrt(mean(mean(data(idx,:).^2, 2)));
    end
end

% Normalize values to [0,1] ignoring NaNs
minv = min(regionVals,[],'omitnan');
maxv = max(regionVals,[],'omitnan');
regionVals = (regionVals - minv) ./ (maxv - minv + eps);

%% --- Map amplitude to HSV-based color using shared mapping ---
regionColors = eeg_vals_to_hsv(regionVals);  % nR x 3

% Grey-out missing regions
for r = 1:nR
    if isnan(regionVals(r))
        regionColors(r,:) = [0.5 0.5 0.5];
    end
end

%% --- Optional display ---
figure('Name','EEG Region Color Map','Color','w');
barh(regionVals,'FaceColor','flat','CData',regionColors);
yticks(1:nR);
yticklabels(regionNames);
xlabel('Normalized RMS Amplitude');
title('16 Brain Regions → Color Intensity');
set(gca,'YDir','reverse');
end
