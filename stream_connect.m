
% stream_connect.m
% Master script to:
%   - Connect to BrainVision RDA
%   - Visualize EEG (monitor, topo, regions, 3D, MCU)
%   - Advanced monitor graph (raw vs processed)
%   - Optional recording of raw/processed to EEGLAB dataset

clear; close all; clc;
addpath('functions');
addpath("eeglab2025.1.0")
%% --- CONFIGURATION ---

% Visualization toggles
ENABLE_MONITOR     = true;    % advanced monitor graph (raw vs processed)
ENABLE_REGION_MAP  = false;
ENABLE_TOPO        = true;
ENABLE_3D          = false;
ENABLE_MCU         = false;

% Recording toggles
ENABLE_RAW_RECORDING      = false;   % record raw (as pulled from RDA)
ENABLE_PROCESSED_RECORDING = false;  % record processed data (after your cleaning)

band    = 'alpha';
pullDur = 1;                  % seconds per pull
fs      = 500;
host    = '192.168.50.7';
port    = 51244;
nCh     = 32;

% MCU config
mcuPort = "/dev/cu.EEG-ESP32";
mcuBaud = 115200;

%% --- Connect to BrainVision RDA ---

fprintf('[EEG Master] Connecting to BrainVision RDA stream...\n');
try, bv_rda_client('close'); end %#ok<TRYNC>
S = bv_rda_client('open', host, port, nCh, fs); %#ok<NASGU>
pause(2.0);

%% --- Load channel geometry & regions ---

sfpPath = eeg_get_data_path('channel_locations.sfp');
fid = fopen(sfpPath,'r');
if fid < 0
    error('Could not open channel_locations.sfp at: %s', sfpPath);
end
C = textscan(fid, '%s %f %f %f');
fclose(fid);
chanLabels_sfp = C{1};
coords         = [C{2}, C{3}, C{4}];
Nch_geom       = numel(chanLabels_sfp);

Nch        = min(nCh, Nch_geom);
chanLabels = chanLabels_sfp(1:Nch);
coords     = coords(1:Nch, :);

% 2D topo
theta  = atan2(coords(:,2), coords(:,1));
radius = 0.5 + 0.5*coords(:,3);
x2d = radius .* cos(theta);
y2d = radius .* sin(theta);
x2d = x2d / max(abs(x2d));
y2d = y2d / max(abs(y2d));

% 3D
coords3d = coords ./ max(vecnorm(coords,2,2));
x3d = coords3d(:,1);
y3d = coords3d(:,2);
z3d = coords3d(:,3);

[regions, regionNames] = eeg_get_regions();
nR = size(regions,1);

bands = eeg_get_band_ranges();
if ~isfield(bands, band)
    error('Unknown band "%s". Valid bands: %s', band, strjoin(fieldnames(bands),', '));
end
freqRange = bands.(band);

%% --- MCU ---

if ENABLE_MCU
    fprintf('[EEG Master] Opening MCU serial port %s @ %d...\n', mcuPort, mcuBaud);
    mcu = serialport(mcuPort, mcuBaud);
else
    mcu = [];
end

%% --- Initialize monitor + other figures ---

if ENABLE_MONITOR
    mon = eeg_scope_monitor_init(Nch, fs, chanLabels);
else
    mon = [];
end

if ENABLE_REGION_MAP
    regVis = eeg_region_lightmap_init(regionNames, band);
else
    regVis = [];
end

if ENABLE_TOPO
    topoVis = eeg_topo_lightmap_init(chanLabels, x2d, y2d, band);
else
    topoVis = [];
end

if ENABLE_3D
    vis3D = eeg_3d_lightmap_init(chanLabels, x3d, y3d, z3d, band);
else
    vis3D = [];
end

%% --- Prepare EEG struct for region-bandpower ---

EEG = struct();
EEG.srate    = fs;
EEG.data     = zeros(Nch, 1);
EEG.chanlocs = struct('labels', chanLabels);

%% --- State for smoothing (for topo/regions) ---

alphaSmooth      = 0.3;
smoothValsCh     = [];
smoothValsRegion = [];

%% --- Recording buffers ---

rec_raw  = [];   % [Nch x totalSamples]
rec_proc = [];   % [Nch x totalSamples]

%% --- Main streaming loop ---

fprintf('[EEG Master] Streaming started... press Ctrl+C to stop.\n');
blockCount = 0;

while true
    if isempty(findobj('type','figure'))
        disp('[EEG Master] All figures closed. Stopping stream.');
        break;
    end

    X = bv_rda_client('pull', pullDur);   % [nChanStream x nSamp], µV
    if isempty(X)
        fprintf('[%s] Empty block (no data yet)\n', datestr(now,'HH:MM:SS'));
        pause(0.5);
        continue;
    end

    [nChanStream, nSamp] = size(X);
    if nChanStream < Nch
        warning('Stream has %d channels, expected at least %d. Using %d.', ...
            nChanStream, Nch, nChanStream);
        Nuse = nChanStream;
    else
        Nuse = Nch;
    end

    Xraw = X(1:Nuse, :);   % raw, unprocessed data (µV)

    % ----- Prelim processed data (placeholder: same as raw now) -----
    Xproc = eeg_preclean_light(Xraw, fs);

    EEG.data     = Xraw;
    EEG.chanlocs = struct('labels', chanLabels(1:Nuse));

    blockCount = blockCount + 1;
    means      = mean(Xraw,2);
    nonzero    = sum(any(Xraw,2));
    fprintf('[%s] Block %d | %d samples | %d/%d active channels | mean range: %.2f–%.2f µV\n',...
        datestr(now,'HH:MM:SS'), blockCount, nSamp, nonzero, Nuse, min(means), max(means));

    %% --- Recording accumulation ---

    if ENABLE_RAW_RECORDING
        rec_raw = [rec_raw, Xraw]; %#ok<AGROW>
    end
    if ENABLE_PROCESSED_RECORDING
        rec_proc = [rec_proc, Xproc]; %#ok<AGROW>
    end

    %% --- Monitor graph (raw vs processed, channel groups, etc.) ---

    if ENABLE_MONITOR && ~isempty(mon) && isvalid(mon.fig)
        eeg_scope_monitor_update(mon, Xraw, Xproc);
    end

    %% --- Per-channel bandpower (for topo + 3D) ---

    if ENABLE_TOPO || ENABLE_3D
        valsCh = zeros(1,Nuse);
        for c = 1:Nuse
            valsCh(c) = bandpower(Xraw(c,:), fs, freqRange);
        end
        valsCh = valsCh - min(valsCh);
        valsCh = valsCh ./ max(valsCh + eps);

        if isempty(smoothValsCh) || numel(smoothValsCh) ~= Nuse
            smoothValsCh = valsCh;
        else
            smoothValsCh = alphaSmooth*valsCh + (1-alphaSmooth)*smoothValsCh;
        end
        valsCh = smoothValsCh;

        rgbCh = eeg_vals_to_hsv(valsCh);
    else
        rgbCh = [];
    end

    %% --- Region bandpower (for 16-region map + MCU) ---

    if ENABLE_REGION_MAP || ENABLE_MCU
        regionBP = eeg_region_bandpower(EEG);
        if isfield(regionBP, band)
            valsRegion = regionBP.(band);
        else
            valsRegion = zeros(1, nR);
        end

        if isempty(smoothValsRegion) || numel(smoothValsRegion) ~= numel(valsRegion)
            smoothValsRegion = valsRegion;
        else
            smoothValsRegion = alphaSmooth*valsRegion + ...
                (1-alphaSmooth)*smoothValsRegion;
        end
        valsRegion = smoothValsRegion;
        rgbRegion  = eeg_vals_to_hsv(valsRegion);
    else
        rgbRegion = [];
    end

    if ENABLE_REGION_MAP && ~isempty(regVis) && isvalid(regVis.fig)
        eeg_region_lightmap_update(regVis, rgbRegion);
    end

    if ENABLE_TOPO && ~isempty(topoVis) && isvalid(topoVis.fig)
        eeg_topo_lightmap_update(topoVis, rgbCh);
    end

    if ENABLE_3D && ~isempty(vis3D) && isvalid(vis3D.fig)
        eeg_3d_lightmap_update(vis3D, rgbCh);
    end

    if ENABLE_MCU && ~isempty(mcu)
        send_to_mcu(mcu, rgbRegion);
        while mcu.NumBytesAvailable > 0
            line = readline(mcu);
            disp("ESP32: " + string(line));
        end
    end

    drawnow limitrate nocallbacks;
end

%% --- Cleanup + save recordings ---

try, bv_rda_client('close'); end %#ok<TRYNC>
if ENABLE_MCU && ~isempty(mcu)
    clear mcu
end

% ---- Save to EEGLAB .set ----
try
    outDir = fullfile('data','recordings');
    if ~exist(outDir,'dir')
        mkdir(outDir);
    end
    ts = datestr(now,'yyyy-mm-dd_HHMMSS');

    % Raw recording
    if ENABLE_RAW_RECORDING && ~isempty(rec_raw)
        fname_raw = sprintf('%s_raw.set', ts);
        EEG_raw = eeg_emptyset;
        EEG_raw.data   = rec_raw;
        EEG_raw.srate  = fs;
        EEG_raw.nbchan = size(rec_raw,1);
        EEG_raw.trials = 1;
        EEG_raw.pnts   = size(rec_raw,2);
        EEG_raw.chanlocs = struct('labels', cellstr(chanLabels(1:size(rec_raw,1))));
        EEG_raw = eeg_checkset(EEG_raw);
        EEG_raw.etc.stream_info = struct( ...
            'type', 'raw', ...
            'band', band, ...
            'host', host, ...
            'port', port, ...
            'pullDur', pullDur);
        pop_saveset(EEG_raw, 'filename', fname_raw, 'filepath', outDir);
        fprintf('[EEG Master] Saved raw recording to %s\n', fullfile(outDir,fname_raw));
    end

    % Processed recording
    if ENABLE_PROCESSED_RECORDING && ~isempty(rec_proc)
        fname_proc = sprintf('%s_proc.set', ts);
        EEG_proc = eeg_emptyset;
        EEG_proc.data   = rec_proc;
        EEG_proc.srate  = fs;
        EEG_proc.nbchan = size(rec_proc,1);
        EEG_proc.trials = 1;
        EEG_proc.pnts   = size(rec_proc,2);
        EEG_proc.chanlocs = struct('labels', cellstr(chanLabels(1:size(rec_proc,1))));
        EEG_proc = eeg_checkset(EEG_proc);
        EEG_proc.etc.stream_info = struct( ...
            'type', 'processed', ...
            'band', band, ...
            'host', host, ...
            'port', port, ...
            'pullDur', pullDur);
        pop_saveset(EEG_proc, 'filename', fname_proc, 'filepath', outDir);
        fprintf('[EEG Master] Saved processed recording to %s\n', fullfile(outDir,fname_proc));
    end

catch ME
    warning(ME.identifier, 'Failed to save EEGLAB datasets: %s', ME.message);
end


