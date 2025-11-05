function [regionBandPower, regionColors] = eeg_region_bandpower(EEG)
% EEG_REGION_BANDPOWER - Compute normalized bandpower per brain region
% and return RGB color encodings.

% ----------------------------------------------------
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

bands = struct( ...
    'delta',[0.5 4], ...
    'theta',[4 8], ...
    'alpha',[8 13], ...
    'beta',[13 30], ...
    'gamma',[30 45]);

% ----------------------------------------------------
if isstruct(EEG)
    data = double(EEG.data);
    fs = EEG.srate;
    labels = upper(cellstr(string({EEG.chanlocs.labels})));
else
    error('Input must be an EEGLAB EEG struct.');
end

bandNames = fieldnames(bands);
nR = numel(regions(:,1));
regionBandPower = struct();
regionColors = struct();

for b = 1:numel(bandNames)
    band = bandNames{b};
    fRange = bands.(band);
    vals = nan(1,nR);

    for r = 1:nR
        chans = upper(regions{r,2});
        idx = find(ismember(labels,chans));
        if isempty(idx), continue; end

        p = 0;
        for c = idx
            bp = bandpower(data(c,:), fs, fRange);
            p = p + log10(bp + eps);
        end
        vals(r) = p / numel(idx);
    end

    % Normalize
    if all(isnan(vals))
        vals(:) = 0;
    else
        vals = vals - min(vals,[],'omitnan');
        vals = vals ./ max(vals,[],'omitnan');
    end

    regionBandPower.(band) = vals(:)';
    cmap = jet(256);
    regionColors.(band) = interp1(linspace(0,1,256), cmap, vals, 'linear','extrap');
end

% Optional visualization only if no output requested
if nargout == 0
    figure('Color','w','Position',[100 100 800 400]);
    for b = 1:numel(bandNames)
        subplot(1,5,b);
        vals = regionBandPower.(bandNames{b});
        colors = regionColors.(bandNames{b});
        barh(vals,'FaceColor','flat','CData',colors);
        title(upper(bandNames{b}));
        set(gca,'YTick',1:nR,'YTickLabel',regions(:,1),'YDir','reverse');
        xlabel('Normalized Power');
    end
    sgtitle('EEG Band Power by Brain Region');
end
end
