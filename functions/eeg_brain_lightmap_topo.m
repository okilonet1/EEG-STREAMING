function eeg_brain_lightmap_topo(band)
% EEG_BRAIN_LIGHTMAP_TOPO
% Live per-channel bandpower visualizer (2D flattened head)
% Uses modular init/update + shared helpers.
%
% Usage:
%   eeg_brain_lightmap_topo('alpha')

if nargin < 1, band = 'alpha'; end
band = lower(band);

fprintf('[ChannelLightmap] Starting 2D topo visualization (%s band)\n', upper(band));

% --- Connect to BrainVision RDA ---
try, bv_rda_client('close'); end %#ok<TRYNC>
S = bv_rda_client('open','127.0.0.1',51244,32,500); %#ok<NASGU>
fs = 500;

% --- Load channel coordinates (.sfp) via helper path ---
sfpPath = eeg_get_data_path('channel_locations.sfp');
fid = fopen(sfpPath,'r');
if fid < 0
    error('Could not open channel_locations.sfp at: %s', sfpPath);
end
C = textscan(fid, '%s %f %f %f');
fclose(fid);

labels = C{1};
coords = [C{2}, C{3}, C{4}];
Nch    = numel(labels);

% --- 2D azimuthal-like projection ---
theta  = atan2(coords(:,2), coords(:,1));
radius = 0.5 + 0.5*coords(:,3);
x = radius .* cos(theta);
y = radius .* sin(theta);
x = x / max(abs(x));
y = y / max(abs(y));

% --- Initialize topo figure via modular helper ---
vis = eeg_topo_lightmap_init(labels, x, y, band);

% --- Band ranges (shared helper) ---
bands = eeg_get_band_ranges();
if ~isfield(bands, band)
    error('Unknown band "%s". Valid bands: %s', band, strjoin(fieldnames(bands),', '));
end
freqRange = bands.(band);

% --- Temporal smoothing state ---
alphaSmooth = 0.3;
smoothVals  = [];

fprintf('[ChannelLightmap] Streaming... press Ctrl+C or close figure to stop.\n');

% --- Live update loop ---
while isvalid(vis.fig)
    X = bv_rda_client('pull', 0.25);
    if isempty(X) || all(X(:)==0)
        pause(0.05);
        continue;
    end
    [nChanStream, ~] = size(X);
    Nuse = min(nChanStream, Nch);

    % Compute bandpower per channel
    vals = zeros(1,Nuse);
    for c = 1:Nuse
        vals(c) = bandpower(X(c,:), fs, freqRange);
    end

    % Normalize to [0,1]
    vals = vals - min(vals);
    vals = vals ./ max(vals + eps);

    % Smoothing
    if isempty(smoothVals) || numel(smoothVals) ~= Nuse
        smoothVals = vals;
    else
        smoothVals = alphaSmooth*vals + (1-alphaSmooth)*smoothVals;
    end
    vals = smoothVals;

    % Map to RGB
    rgbCh = eeg_vals_to_hsv(vals);  % Nuse x 3

    % Update via modular helper
    eeg_topo_lightmap_update(vis, rgbCh);

    drawnow limitrate;
end

try, bv_rda_client('close'); end %#ok<TRYNC>
end
