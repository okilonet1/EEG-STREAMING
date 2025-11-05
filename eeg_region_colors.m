function regionColors = eeg_region_colors(EEG)
% EEG_REGION_COLORS - Reduce EEG channels into 16 brain regions and map to colors.
% Usage:
%    regionColors = eeg_region_colors(EEG)
%
% EEG can be:
%   - an EEGLAB EEG structure (with EEG.data, EEG.chanlocs)
%   - or a numeric matrix [nChannels x nSamples] with matching channel labels below.

%% --- Define brain region mapping ---
regions = {
    'Left Frontal',     {'Fp1','F3','F7'}
    'Right Frontal',    {'Fp2','F4','F8'}
    'Midline Frontal',  {'Fz','AFz'}
    'Left Central',     {'FC3','C3','CP3'}
    'Right Central',    {'FC4','C4','CP4'}
    'Midline Central',  {'Cz'}
    'Left Parietal',    {'P3','P7'}
    'Right Parietal',   {'P4','P8'}
    'Midline Parietal', {'Pz'}
    'Left Temporal',    {'T7','FT7'}
    'Right Temporal',   {'T8','FT8'}
    'Left Occipital',   {'O1','PO3'}
    'Right Occipital',  {'O2','PO4'}
    'Midline Occipital',{'Oz'}
    'Left FC',          {'FC5','F5'}
    'Right FC',         {'FC6','F6'}
    };

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
