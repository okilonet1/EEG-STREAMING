function [regionBandPower, regionColors] = eeg_region_bandpower(EEG)
% EEG_REGION_BANDPOWER
% Compute normalized regional bandpower after minimal preprocessing
% and return RGB color encodings for visualization.
%
% Usage:
%   [regionBandPower, regionColors] = eeg_region_bandpower(EEG)
%
%   EEG - EEGLAB EEG structure with fields:
%         EEG.data  [channels x samples]
%         EEG.srate (sampling frequency)
%         EEG.chanlocs.labels (channel names)
%
%   regionBandPower.(band) - normalized power values per region
%   regionColors.(band)    - corresponding RGB color map per region

% ----------------------------------------------------
% --- Reset persistent variables when EEG struct has no data ---
persistent smoothVals_perBand
if nargin == 0
    clear smoothVals_perBand
    return
end

alpha = 0.3;  % smoothing factor (0 = no smoothing, 1 = immediate)

% --- Load region definitions ---
fid = fopen('regions.json','r');
if fid < 0, error('regions.json not found in current directory.'); end
raw = fread(fid, inf);
fclose(fid);
regionsStruct = jsondecode(char(raw'));

fields = fieldnames(regionsStruct);
nR = numel(fields);
regions = cell(nR,2);
for i = 1:nR
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
% --- Validate EEG input ---
if ~isstruct(EEG) || ~isfield(EEG,'data') || ~isfield(EEG,'srate')
    error('Input must be a valid EEGLAB EEG struct with .data and .srate fields');
end

data = double(EEG.data);
fs = EEG.srate;
labels = upper(string({EEG.chanlocs.labels}));

% ----------------------------------------------------
% --- LIGHT PREPROCESSING PIPELINE ---
% Common average reference
data = data - mean(data,1);

% Apply high-pass, notch, and low-pass filters (reuse designed filters)
persistent hp notch lp
if isempty(hp)
    hp = designfilt('highpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',0.5,'SampleRate',fs);
    notch = designfilt('bandstopiir','FilterOrder',4, ...
        'HalfPowerFrequency1',59,'HalfPowerFrequency2',61,'SampleRate',fs);
    lp = designfilt('lowpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',45,'SampleRate',fs);
end
data = filtfilt(hp, data')';
data = filtfilt(notch, data')';
data = filtfilt(lp, data')';

% ----------------------------------------------------
% --- BANDPOWER COMPUTATION ---
bandNames = fieldnames(bands);
regionBandPower = struct();
regionColors = struct();

for b = 1:numel(bandNames)
    band = bandNames{b};
    fRange = bands.(band);
    vals = nan(1,nR);

    for r = 1:nR
        chans = upper(string(regions{r,2}));
        idx = find(ismember(labels,chans));
        if isempty(idx), continue; end

        p = 0;
        for c = idx
            bp = bandpower(data(c,:), fs, fRange);
            p = p + log10(bp + eps);
        end
        vals(r) = p / numel(idx);
    end

    % Normalize across regions
    if all(isnan(vals)), vals(:) = 0;
    else
        vals = vals - min(vals,[],'omitnan');
        vals = vals ./ max(vals,[],'omitnan');
    end

    % --- Smoothing ---
    if isempty(smoothVals_perBand) || numel(smoothVals_perBand) ~= nR
        smoothVals_perBand = vals;
    else
        smoothVals_perBand = alpha*vals + (1-alpha)*smoothVals_perBand;
    end
    vals = smoothVals_perBand;

    % Save results
    regionBandPower.(band) = vals(:)';

    % Assign colors using jet colormap
    cmap = jet(256);
    regionColors.(band) = interp1(linspace(0,1,256), cmap, vals, 'linear','extrap');
end

% ----------------------------------------------------
% --- Visualization (if no output requested) ---
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
