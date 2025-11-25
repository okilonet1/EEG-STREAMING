% stream_connect.m
% Master script to:
%   - Connect to BrainVision RDA
%   - Show live EEG monitor
%   - Show region lightmap (16 regions)
%   - Show 2D topographic per-channel map
%   - Show 3D per-channel brain
%   - Optionally stream region colors to NodeMCU / ESP

clear; close all; clc;

% --- Ensure helper + viz functions are on the path ---
addpath('functions');

%% --- CONFIGURATION ---

% Enable / disable modules
ENABLE_MONITOR     = true;   % simple 2-panel monitor
ENABLE_REGION_MAP  = true;   % 16-region bubble map
ENABLE_TOPO        = true;   % 2D per-channel head
ENABLE_3D          = false;  % 3D per-channel head
ENABLE_MCU         = false;  % stream 16-region colors to NodeMCU / ESP

band    = 'alpha';          % band to visualize
pullDur = 1;              % seconds per pull
fs      = 500;              % sampling rate (Hz)
host    = '127.0.0.1';
port    = 51244;
nCh     = 32;               % number of channels expected from RDA

% MCU config (only used if ENABLE_MCU = true)
mcuPort = "/dev/tty.SLAB_USBtoUART";  % change for your system
mcuBaud = 115200;

%% --- Connect to BrainVision RDA ---

fprintf('[EEG Master] Connecting to BrainVision RDA stream...\n');
try, bv_rda_client('close'); end %#ok<TRYNC>
S = bv_rda_client('open', host, port, nCh, fs); %#ok<NASGU>
pause(2.0);  % allow recorder to start sending data

%% --- Load channel geometry & regions once ---

% Channel coordinates from .sfp (for topo + 3D)
sfpPath = eeg_get_data_path('channel_locations.sfp');
fid = fopen(sfpPath,'r');
if fid < 0
    error('Could not open channel_locations.sfp at: %s', sfpPath);
end
C = textscan(fid, '%s %f %f %f');
fclose(fid);
chanLabels_sfp = C{1};
coords         = [C{2}, C{3}, C{4}];   % [x y z] per channel
Nch_geom       = numel(chanLabels_sfp);

% Use as many channels as both stream and .sfp share
Nch = min(nCh, Nch_geom);
chanLabels = chanLabels_sfp(1:Nch);
coords     = coords(1:Nch, :);

% 2D topo projection
theta  = atan2(coords(:,2), coords(:,1));   % azimuth
radius = 0.5 + 0.5*coords(:,3);             % compress height into radius
x2d = radius .* cos(theta);
y2d = radius .* sin(theta);
x2d = x2d / max(abs(x2d));
y2d = y2d / max(abs(y2d));

% 3D projection
coords3d = coords ./ max(vecnorm(coords,2,2));
x3d = coords3d(:,1);
y3d = coords3d(:,2);
z3d = coords3d(:,3);

% Regions (16-region map)
[regions, regionNames] = eeg_get_regions();
nR = size(regions,1);

% Band ranges
bands = eeg_get_band_ranges();
if ~isfield(bands, band)
    error('Unknown band "%s". Valid bands: %s', band, strjoin(fieldnames(bands),', '));
end
freqRange = bands.(band);

%% --- Set up MCU (optional) ---

if ENABLE_MCU
    fprintf('[EEG Master] Opening MCU serial port %s @ %d...\n', mcuPort, mcuBaud);
    mcu = serialport(mcuPort, mcuBaud);
else
    mcu = [];
end

%% --- Initialize figures / visualization modules ---

% 1) Simple monitor
if ENABLE_MONITOR
    mon = eeg_monitor_init();
else
    mon = [];
end

% 2) Region lightmap
if ENABLE_REGION_MAP
    regVis = eeg_region_lightmap_init(regionNames, band);
else
    regVis = [];
end

% 3) Topographic 2D head
if ENABLE_TOPO
    topoVis = eeg_topo_lightmap_init(chanLabels, x2d, y2d, band);
else
    topoVis = [];
end

% 4) 3D head
if ENABLE_3D
    vis3D = eeg_3d_lightmap_init(chanLabels, x3d, y3d, z3d, band);
else
    vis3D = [];
end

%% --- Prepare EEG struct for region-bandpower function ---

EEG = struct();
EEG.srate = fs;
EEG.data  = zeros(Nch, 1);    % will overwrite each pull
EEG.chanlocs = struct('labels', chanLabels);

%% --- State for smoothing ---

alphaSmooth = 0.3;
smoothValsCh     = [];  % per-channel
smoothValsRegion = [];  % per-region

%% --- Main streaming loop ---

fprintf('[EEG Master] Streaming started... press Ctrl+C to stop.\n');
blockCount = 0;

while true
    % Stop if *all* figs closed
    if isempty(findobj('type','figure'))
        disp('[EEG Master] All figures closed. Stopping stream.');
        break;
    end

    % Pull block
    X = bv_rda_client('pull', pullDur);
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

    Xuse = X(1:Nuse, :);
    % EEG.data(1:Nuse, 1:nSamp) = Xuse;
    % NEW (better – always match actual window length)
    EEG.data = Xuse;
    % if you want to be super correct about chanlocs length:
    EEG.chanlocs = struct('labels', chanLabels(1:Nuse));

    % Basic stats
    blockCount = blockCount + 1;
    means = mean(Xuse,2);
    nonzero = sum(any(Xuse,2));
    fprintf('[%s] Block %d | %d samples | %d/%d active channels | mean range: %.2f–%.2f µV\n',...
        datestr(now,'HH:MM:SS'), blockCount, nSamp, nonzero, Nuse, min(means), max(means));

    %% 1) Update simple monitor
    if ENABLE_MONITOR && ~isempty(mon) && isvalid(mon.fig)
        eeg_monitor_update(mon, Xuse, means, nonzero);
    end

    %% 2) Per-channel bandpower (for topo + 3D)
    if ENABLE_TOPO || ENABLE_3D
        valsCh = zeros(1,Nuse);
        for c = 1:Nuse
            valsCh(c) = bandpower(Xuse(c,:), fs, freqRange);
        end

        valsCh = valsCh - min(valsCh);
        valsCh = valsCh ./ max(valsCh + eps);

        if isempty(smoothValsCh) || numel(smoothValsCh) ~= Nuse
            smoothValsCh = valsCh;
        else
            smoothValsCh = alphaSmooth*valsCh + (1-alphaSmooth)*smoothValsCh;
        end
        valsCh = smoothValsCh;

        rgbCh = eeg_vals_to_hsv(valsCh);  % Nuse x 3
    else
        valsCh = [];
        rgbCh  = [];
    end

    %% 3) Region bandpower (for 16-region map + MCU)
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

        rgbRegion = eeg_vals_to_hsv(valsRegion);  % nR x 3
    else
        valsRegion = [];
        rgbRegion  = [];
    end

    %% 4) Update region lightmap
    if ENABLE_REGION_MAP && ~isempty(regVis) && isvalid(regVis.fig)
        eeg_region_lightmap_update(regVis, rgbRegion);
    end

    %% 5) Update topo figure
    if ENABLE_TOPO && ~isempty(topoVis) && isvalid(topoVis.fig)
        eeg_topo_lightmap_update(topoVis, rgbCh);
    end

    %% 6) Update 3D figure
    if ENABLE_3D && ~isempty(vis3D) && isvalid(vis3D.fig)
        eeg_3d_lightmap_update(vis3D, rgbCh);
    end

    %% 7) Stream to MCU (16 regions)
    if ENABLE_MCU && ~isempty(mcu)
        rgb255 = uint8(round(255 * rgbRegion));
        frame  = reshape(rgb255.', 1, []);    % [R1 G1 B1 ... Rn Gn Bn]
        write(mcu, frame, "uint8");
        write(mcu, uint8(10), "uint8");       % newline terminator
    end

    drawnow limitrate nocallbacks;
end

% Cleanup
try, bv_rda_client('close'); end %#ok<TRYNC>
if ENABLE_MCU && ~isempty(mcu)
    clear mcu
end
