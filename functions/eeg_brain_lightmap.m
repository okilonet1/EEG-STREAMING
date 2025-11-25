function rgbArray = eeg_brain_lightmap(band)
% EEG_BRAIN_LIGHTMAP
% Live 16-region band-power visualizer using modular helpers.
%
% Usage:
%   eeg_brain_lightmap('alpha')
%   rgbArray = eeg_brain_lightmap('beta');  % returns last RGB frame

if nargin < 1, band = 'alpha'; end
band = lower(band);

fprintf('[EEG-Lightmap] Starting real-time visualization (%s band)\n', upper(band));

% --- Connect to BrainVision RDA (standalone default) ---
try, bv_rda_client('close'); end %#ok<TRYNC>
S = bv_rda_client('open','127.0.0.1',51244,32,500); %#ok<NASGU>
fs = 500;

% --- Regions + region names ---
[regions, regionNames] = eeg_get_regions();
nR = numel(regionNames);

% --- EEG struct (32 channels) ---
EEG = struct();
EEG.srate = fs;
EEG.data  = zeros(32, fs);
chanLabels = { ...
    'Fp1','Fz','F3','F7','FT9','FC5','FC1','C3','T7','TP9','CP5','CP1',...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz',...
    'C4','T8','FT10','FC6','FC2','F4','F8','Fp2'};
for i = 1:numel(chanLabels)
    EEG.chanlocs(i).labels = chanLabels{i};
end

% --- Initialize region lightmap via new helper ---
vis = eeg_region_lightmap_init(regionNames, band);

% --- For optional return + MCU-style use ---
rgbArray = zeros(nR,3);

fprintf('[EEG-Lightmap] Streaming... press Ctrl+C or close figure to stop.\n');

while isvalid(vis.fig)
    % Pull 250 ms of data
    X = bv_rda_client('pull', 0.25);
    if isempty(X) || all(X(:)==0)
        pause(0.05);
        continue;
    end
    EEG.data = X;

    % --- Compute regional bandpower using shared backend ---
    regionBP = eeg_region_bandpower(EEG);  % handles filtering + smoothing

    if ~isfield(regionBP, band)
        warning('Band "%s" not found in regionBandPower.', band);
        continue;
    end

    vals = regionBP.(band);      % 1 x nR, normalized [0,1]

    % --- Map to RGB via shared HSV helper ---
    rgbArray = eeg_vals_to_hsv(vals);   % nR x 3

    % --- Update visualization via modular helper ---
    eeg_region_lightmap_update(vis, rgbArray);

    drawnow limitrate nocallbacks;
end

try, bv_rda_client('close'); end %#ok<TRYNC>
end
