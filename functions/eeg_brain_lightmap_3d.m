function eeg_brain_lightmap_3d(band)
% EEG_BRAIN_LIGHTMAP_3D
% Live per-channel bandpower visualizer in 3D.
% Uses modular init/update + shared helpers.
%
% Usage:
%   eeg_brain_lightmap_3d('alpha')

if nargin < 1, band = 'alpha'; end
band = lower(band);

fprintf('[3DLightmap] Starting 3D brain visualization (%s band)\n', upper(band));

% --- Connect to BrainVision RDA ---
try, bv_rda_client('close'); end %#ok<TRYNC>
S = bv_rda_client('open','127.0.0.1',51244,32,500); %#ok<NASGU>
fs = 500;

% --- Load channel coordinates (.sfp) via helper ---
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

% Normalize radius to fit unit sphere
coords = coords ./ max(vecnorm(coords,2,2));

x = coords(:,1);
y = coords(:,2);
z = coords(:,3);

% --- Initialize 3D figure via modular helper ---
vis = eeg_3d_lightmap_init(labels, x, y, z, band);

% --- Band ranges ---
bands = eeg_get_band_ranges();
if ~isfield(bands, band)
    error('Unknown band "%s". Valid bands: %s', band, strjoin(fieldnames(bands),', '));
end
freqRange = bands.(band);

% --- Temporal smoothing state ---
alphaSmooth = 0.3;
smoothVals  = [];

fprintf('[3DLightmap] Streaming... press Ctrl+C or close figure to stop.\n');

% --- Live update loop ---
while isvalid(vis.fig)
    X = bv_rda_client('pull', 1.0);
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
    eeg_3d_lightmap_update(vis, rgbCh);

    drawnow limitrate;
end

try, bv_rda_client('close'); end %#ok<TRYNC>
end
