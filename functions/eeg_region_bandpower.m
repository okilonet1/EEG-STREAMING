function regionBandPower = eeg_region_bandpower(EEG)
% EEG_REGION_BANDPOWER
% Compute normalized regional bandpower after minimal preprocessing.
%
% Usage:
%   regionBandPower = eeg_region_bandpower(EEG)
%
% regionBandPower.(band) -> 1 x nRegions normalized [0,1] values.

% ----------------------------------------------------
% --- Reset persistent variables when called with no args ---
persistent smoothVals_perBand hp notch lp lastFs
if nargin == 0
    clear smoothVals_perBand hp notch lp lastFs
    return
end

alphaSmooth = 0.3;  % temporal smoothing

% --- Validate EEG input ---
if ~isstruct(EEG) || ~isfield(EEG,'data') || ~isfield(EEG,'srate')
    error('Input must be a valid EEGLAB EEG struct with .data and .srate fields');
end

data   = double(EEG.data);
fs     = EEG.srate;
labels = upper(string({EEG.chanlocs.labels}));

% --- Load regions and band ranges ---
[regions, regionNames] = eeg_get_regions();
nR    = size(regions,1);
bands = eeg_get_band_ranges();
bandNames = fieldnames(bands);

% ----------------------------------------------------
% --- LIGHT PREPROCESSING PIPELINE ---
% Common average reference
data = data - mean(data,1);

% Design (or reuse) filters; redesign if sample rate changes
if isempty(hp) || isempty(lastFs) || lastFs ~= fs
    hp = designfilt('highpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',0.5,'SampleRate',fs);
    notch = designfilt('bandstopiir','FilterOrder',4, ...
        'HalfPowerFrequency1',59,'HalfPowerFrequency2',61,'SampleRate',fs);
    lp = designfilt('lowpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',45,'SampleRate',fs);
    lastFs = fs;
end

data = filtfilt(hp,    data')';
data = filtfilt(notch, data')';
data = filtfilt(lp,    data')';

% ----------------------------------------------------
% --- BANDPOWER COMPUTATION ---
regionBandPower = struct();

if isempty(smoothVals_perBand)
    smoothVals_perBand = struct();
end

for b = 1:numel(bandNames)
    bandName = bandNames{b};
    fRange   = bands.(bandName);
    vals     = nan(1, nR);

    % Per-region log-power
    for r = 1:nR
        chans = upper(string(regions{r,2}));
        idx   = find(ismember(labels, chans));
        if isempty(idx), continue; end

        p = 0;
        for c = idx
            bp = bandpower(data(c,:), fs, fRange);
            p  = p + log10(bp + eps);
        end
        vals(r) = p / numel(idx);
    end

    % Normalize across regions to [0,1]
    if all(isnan(vals))
        vals(:) = 0;
    else
        vals = vals - min(vals,[],'omitnan');
        vals = vals ./ max(vals,[],'omitnan');
    end

    % Temporal smoothing PER BAND
    if ~isfield(smoothVals_perBand, bandName) || ...
            numel(smoothVals_perBand.(bandName)) ~= nR
        smoothVals_perBand.(bandName) = vals;
    else
        smoothVals_perBand.(bandName) = ...
            alphaSmooth*vals + (1-alphaSmooth)*smoothVals_perBand.(bandName);
    end

    regionBandPower.(bandName) = smoothVals_perBand.(bandName);
end
end
