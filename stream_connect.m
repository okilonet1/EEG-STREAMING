% stream_connect.m
% Master script to:
%   - Connect to BrainVision RDA
%   - Show live EEG monitor
%   - Show region lightmap (16 regions)
%   - Show 2D topographic per-channel map
%   - Show 3D per-channel brain
%   - Optionally stream region colors to NodeMCU / ESP
%   - Show raw, unprocessed EEG scope (stacked traces)
%   - Allow per-channel group selection (1–8, 9–16, etc.) for raw + monitor

clear; close all; clc;

% --- Ensure helper + viz functions are on the path ---
addpath('functions');

% --- Globals for UI channel selection ---
global RAW_CH_GROUP MON_CH_GROUP NCH_GLOBAL

%% --- CONFIGURATION ---

% Enable / disable modules
ENABLE_MONITOR     = true;    % simple 2-panel monitor (existing)
ENABLE_REGION_MAP  = false;   % 16-region bubble map
ENABLE_TOPO        = false;   % 2D per-channel head
ENABLE_3D          = false;   % 3D per-channel head
ENABLE_MCU         = true;    % stream 16-region colors to NodeMCU / ESP

% NEW: raw, unprocessed stacked trace view
ENABLE_RAW_SCOPE   = true;    % show raw EEG with no preliminary cleaning
RAW_SCOPE_SEC      = 5;       % seconds of data to keep in raw scope window

band    = 'alpha';            % band to visualize
pullDur = 1;                  % seconds per pull
fs      = 500;                % sampling rate (Hz)
host    = '127.0.0.1';
port    = 51244;
nCh     = 32;                 % number of channels expected from RDA

% MCU config (only used if ENABLE_MCU = true)
mcuPort = "/dev/cu.EEG-ESP32";  % change for your system
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
Nch        = min(nCh, Nch_geom);
chanLabels = chanLabels_sfp(1:Nch);
coords     = coords(1:Nch, :);

% Set global channel count + default groups (used by UI)
NCH_GLOBAL   = Nch;
RAW_CH_GROUP = 1:Nch;
MON_CH_GROUP = 1:Nch;

% Build channel group labels: All, 1–8, 9–16, ...
groupLabels = {'All'};
for startIdx = 1:8:Nch
    endIdx = min(startIdx+7, Nch);
    groupLabels{end+1} = sprintf('%d-%d', startIdx, endIdx); %#ok<SAGROW>
end

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
    % Add channel group menu for monitor
    uicontrol('Style','popupmenu', ...
              'Parent', mon.fig, ...
              'String', groupLabels, ...
              'Units','pixels', ...
              'Position', [10 10 120 20], ...
              'TooltipString','Monitor channels: All, 1-8, 9-16, ...', ...
              'Callback', @(src,evt)select_channel_group(src,'mon'));
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

% 5) NEW: raw stacked-scope figure
if ENABLE_RAW_SCOPE
    rawScope.fig   = figure('Name','Raw EEG Scope (µV, unprocessed)', ...
                            'NumberTitle','off');
    rawScope.ax    = axes('Parent', rawScope.fig);
    hold(rawScope.ax, 'on');
    xlabel(rawScope.ax, 'Time (s)');
    ylabel(rawScope.ax, 'Channel (offset traces)');
    title(rawScope.ax, 'Raw EEG (no cleaning)');
    rawScope.lines = [];         % will init once Nuse is known
    rawScope.buf   = [];         % [Nuse x (fs*RAW_SCOPE_SEC)]
    rawScope.pos   = 0;          % circular buffer index

    % Channel group menu for raw scope
    uicontrol('Style','popupmenu', ...
              'Parent', rawScope.fig, ...
              'String', groupLabels, ...
              'Units','pixels', ...
              'Position', [10 10 120 20], ...
              'TooltipString','Raw channels: All, 1-8, 9-16, ...', ...
              'Callback', @(src,evt)select_channel_group(src,'raw'));
else
    rawScope = [];
end

%% --- Prepare EEG struct for region-bandpower function ---

EEG = struct();
EEG.srate    = fs;
EEG.data     = zeros(Nch, 1);    % will overwrite each pull
EEG.chanlocs = struct('labels', chanLabels);

%% --- State for smoothing ---

alphaSmooth      = 0.3;
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

    Xuse         = X(1:Nuse, :);        % raw, unprocessed µV
    EEG.data     = Xuse;
    EEG.chanlocs = struct('labels', chanLabels(1:Nuse));

    % Basic stats
    means   = mean(Xuse,2);
    nonzero = sum(any(Xuse,2));
    blockCount = blockCount + 1;
    fprintf('[%s] Block %d | %d samples | %d/%d active channels | mean range: %.2f–%.2f µV\n',...
        datestr(now,'HH:MM:SS'), blockCount, nSamp, nonzero, Nuse, min(means), max(means));

    % --- Get current channel groups (cap to Nuse) ---
    global RAW_CH_GROUP MON_CH_GROUP NCH_GLOBAL
    chIdxRaw = intersect(1:Nuse, RAW_CH_GROUP);
    chIdxMon = intersect(1:Nuse, MON_CH_GROUP);

    if isempty(chIdxRaw), chIdxRaw = 1:min(8,Nuse); end
    if isempty(chIdxMon), chIdxMon = 1:min(8,Nuse); end

    %% 0) NEW: Update raw stacked EEG scope (no cleaning)
    if ENABLE_RAW_SCOPE && ~isempty(rawScope) && isvalid(rawScope.fig)
        % Initialize buffer + lines lazily when we know Nuse
        if isempty(rawScope.buf) || size(rawScope.buf,1) ~= Nuse
            rawScope.buf = zeros(Nuse, fs * RAW_SCOPE_SEC);
            rawScope.pos = 0;

            cla(rawScope.ax);
            hold(rawScope.ax, 'on');
            tAxis = (0:size(rawScope.buf,2)-1) / fs;
            rawScope.lines = gobjects(Nuse,1);
            for c = 1:Nuse
                rawScope.lines(c) = plot(rawScope.ax, tAxis, nan(1, numel(tAxis)));
            end
            xlabel(rawScope.ax, 'Time (s)');
            ylabel(rawScope.ax, 'Channel (offset traces)');
            title(rawScope.ax, sprintf('Raw EEG (last %d s, µV, unprocessed)', RAW_SCOPE_SEC));
        end

        % Append new block to circular buffer
        k = size(Xuse,2);
        L = size(rawScope.buf,2);
        idx = mod(rawScope.pos + (1:k) - 1, L) + 1;
        rawScope.buf(:,idx) = Xuse;
        rawScope.pos = idx(end);

        % Reorder buffer so that time is increasing along tAxis
        tailIdx = mod(rawScope.pos - (L-1):rawScope.pos, L) + 1;
        bufPlot = rawScope.buf(:, tailIdx);

        % For raw scope, only display selected channels (others NaN)
        chStd = std(bufPlot(chIdxRaw,:), 0, 2);
        baseScale = max(chStd);
        if baseScale <= 0
            baseScale = 1;
        end
        offsets = (0:numel(chIdxRaw)-1)' * (baseScale * 5);  % spacing

        tAxis = (0:L-1) / fs;
        % First set all lines to NaN
        for c = 1:Nuse
            set(rawScope.lines(c), 'XData', tAxis, 'YData', nan(1, numel(tAxis)));
        end
        % Now update only the selected group
        for kCh = 1:numel(chIdxRaw)
            c = chIdxRaw(kCh);
            set(rawScope.lines(c), 'XData', tAxis, ...
                                   'YData', bufPlot(c,:) + offsets(kCh));
        end

        % Axes limits
        rawScope.ax.YLim = [min(offsets)-baseScale*2, max(offsets)+baseScale*2];
        rawScope.ax.XLim = [tAxis(1), tAxis(end)];
    end

    %% 1) Update simple monitor (using selected group)
    if ENABLE_MONITOR && ~isempty(mon) && isvalid(mon.fig)
        Xmon    = Xuse(chIdxMon,:);
        meansMn = means(chIdxMon);
        nonzMn  = sum(any(Xmon,2));
        eeg_monitor_update(mon, Xmon, meansMn, nonzMn);
    end

    %% 2) Per-channel bandpower (for topo + 3D) – still uses all Nuse channels
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
        send_to_mcu(mcu, rgbRegion);

        % Non-blocking debug read
        while mcu.NumBytesAvailable > 0
            line = readline(mcu);
            disp("ESP32: " + string(line));
        end
    end

    drawnow limitrate nocallbacks;
end

% Cleanup
try, bv_rda_client('close'); end %#ok<TRYNC>
if ENABLE_MCU && ~isempty(mcu)
    clear mcu
end

%% --- Local helper: channel group selection callback ---

function select_channel_group(src, mode)
% mode = 'raw' or 'mon'
global RAW_CH_GROUP MON_CH_GROUP NCH_GLOBAL

labels = src.String;
val    = src.Value;
choice = labels{val};

if strcmpi(choice, 'All')
    idx = 1:NCH_GLOBAL;
else
    % Expect "start-end" format, e.g., "1-8"
    parts = sscanf(choice, '%d-%d');
    if numel(parts) == 2
        idx = parts(1):parts(2);
    else
        idx = 1:NCH_GLOBAL;
    end
end

if strcmpi(mode,'raw')
    RAW_CH_GROUP = idx;
elseif strcmpi(mode,'mon')
    MON_CH_GROUP = idx;
end
end
