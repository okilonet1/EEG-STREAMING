% stream_to_visualiser.m
%
% Lightweight streaming script for sending EEG data over TCP to
% external visualizers (TouchDesigner, Python, Unity, etc.)
%
% This script:
%   - Connects to BrainVision Recorder (RDA)
%   - Pulls continuous EEG data
%   - Computes per-channel & per-region bandpower (optional)
%   - Streams data via TCP using stream_out()
%

clear; close all; clc;
addpath('functions');



%% ============================
% CONFIGURATION
% =============================

band        = 'alpha';     % band to compute (optional)
pullDur     = 1;         % seconds per pull
fs          = 500;         % sampling rate
host        = '127.0.0.1'; % BrainVision Recorder
port        = 51244;       % RDA port
nCh         = 32;          % expected channels

% TCP visualizer target
VIS_IP      = "127.0.0.1"; % Loopback; change to Badie's IP if needed
VIS_PORT    = 9000;        % Choose any open port (TouchDesigner)

ENABLE_MONITOR = true;      % local 2-panel EEG monitor
ENABLE_TOPO     = false;    % per-channel topo
ENABLE_REGION   = false;    % 16-region bandpower bubble map
ENABLE_TCP_RAW  = false;     % send raw EEG data over TCP
ENABLE_TCP_BP   = false;     % send bandpower over TCP

% Clean up only the TCP server on VIS_PORT from a previous run
try
    stream_out(0, "close", "", VIS_PORT);
end

% Ensure cleanup also happens when this script ends (even on Ctrl+C)
cleanupObj = onCleanup(@() stream_out(0, "close", "", VIS_PORT));

%% ============================
% Connect to RDA
% =============================

fprintf('[stream_to_visualiser] Connecting to RDA…\n');
try, bv_rda_client('close'); end
S = bv_rda_client('open', host, port, nCh, fs); %#ok<NASGU>
pause(1.5);

%% ============================
% Load channel labels (.sfp)
% =============================

sfpPath = eeg_get_data_path('channel_locations.sfp');
fid = fopen(sfpPath,'r');
C = textscan(fid, '%s %f %f %f'); fclose(fid);

chanLabels_sfp = C{1};
coords         = [C{2}, C{3}, C{4}];
Nch_geom       = numel(chanLabels_sfp);

Nch = min(nCh, Nch_geom);
chanLabels = chanLabels_sfp(1:Nch);

%% ============================
% Region definitions
% =============================

[regions, regionNames] = eeg_get_regions();
nR = size(regions,1);

bands = eeg_get_band_ranges();
freqRange = bands.(band);

%% ============================
% Visualization setup
% =============================

if ENABLE_MONITOR
    mon = eeg_monitor_init();
else
    mon = [];
end

if ENABLE_TOPO
    % simple flat topomap
    theta  = atan2(coords(:,2), coords(:,1));
    radius = 0.5 + 0.5*coords(:,3);
    x2d = radius .* cos(theta);
    y2d = radius .* sin(theta);
    x2d = x2d / max(abs(x2d)); y2d = y2d / max(abs(y2d));
    topoVis = eeg_topo_lightmap_init(chanLabels(1:Nch), x2d(1:Nch), y2d(1:Nch), band);
else
    topoVis = [];
end

if ENABLE_REGION
    regVis = eeg_region_lightmap_init(regionNames, band);
else
    regVis = [];
end

%% ============================
% Streaming loop
% =============================

fprintf('[stream_to_visualiser] Streaming started… Press Ctrl+C to stop.\n');
blockCount = 0;

while true
    % Pull raw EEG block
    X = bv_rda_client('pull', pullDur);
    if isempty(X)
        fprintf('[%s] No data yet…\n', datestr(now,'HH:MM:SS'));
        pause(0.25);
        continue;
    end

    [nStream, nSamp] = size(X);
    Nuse             = min(Nch, nStream);
    Xuse             = X(1:Nuse, :);

    blockCount = blockCount + 1;

    %% =============== LOCAL MONITOR UPDATE ===============
    if ENABLE_MONITOR && isvalid(mon.fig)
        means = mean(Xuse,2);
        nonzero = sum(any(Xuse,2));
        eeg_monitor_update(mon, Xuse, means, nonzero);
    end

    %% =============== TOPOGRAPHIC PLOT ===============
    if ENABLE_TOPO && isvalid(topoVis.fig)
        valsCh = zeros(1,Nuse);
        for c = 1:Nuse
            valsCh(c) = bandpower(Xuse(c,:), fs, freqRange);
        end
        valsCh = valsCh - min(valsCh);
        valsCh = valsCh ./ max(valsCh + eps);
        rgbCh  = eeg_vals_to_hsv(valsCh);
        eeg_topo_lightmap_update(topoVis, rgbCh);
    end

    %% =============== REGION BANDPOWER ===============
    if ENABLE_REGION || ENABLE_TCP_BP
        EEGtmp.data     = Xuse;
        EEGtmp.srate    = fs;
        EEGtmp.chanlocs = struct('labels', chanLabels(1:Nuse));

        regionBP = eeg_region_bandpower(EEGtmp);
        valsRegion = regionBP.(band);
        rgbRegion  = eeg_vals_to_hsv(valsRegion);

        if ENABLE_REGION && isvalid(regVis.fig)
            eeg_region_lightmap_update(regVis, rgbRegion);
        end
    end

    %% =============== SEND RAW EEG OVER TCP ===============
    if ENABLE_TCP_RAW
        dataRaw = single(Xuse);
        % stream_out(dataRaw, "tcp", VIS_IP, VIS_PORT);
        stream_out(dataRaw, "tcp_server", "", VIS_PORT);
    end



    drawnow limitrate nocallbacks;
end
