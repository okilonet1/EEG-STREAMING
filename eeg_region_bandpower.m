function [regionBandPower, regionColors] = eeg_region_bandpower(EEG)
% EEG_REGION_BANDPOWER - Compute normalized bandpower per brain region
% and return RGB color encodings.

% ----------------------------------------------------
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
