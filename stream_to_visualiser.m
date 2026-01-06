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
pullDur     = 0.02;         % seconds per pull
fs          = 500;         % sampling rate
% host        = '192.168.50.7'; % BrainVision Recorder
host        = '127.0.0.1'; % BrainVision Recorder
port        = 51244;       % RDA port
nCh         = 32;          % expected channels

% TCP visualizer target
% VIS_IP      = "192.168.50.219"; % Loopback; change to Visualiser IP
VIS_IP      = "127.0.0.1"; % Loopback; change to Visualiser IP
VIS_PORT    = 7006;        % Choose any open port (TouchDesigner)

ENABLE_MONITOR = true;      % local 2-panel EEG monitor
ENABLE_TOPO     = false;    % per-channel topo
ENABLE_REGION   = false;    % 16-region bandpower bubble map
ENABLE_TCP_RAW  = false;     % send raw EEG data over TCP
ENABLE_TCP_BP   = false;     % send bandpower over TCP
ENABLE_TCP_FFT  = false;     % send FFT over TCP
ENABLE_FEATURE  = true;    % stream ONE normalized feature (0..1)
FEATURE_MODE    = "kurtosis";   % "kurtosis" | "alpha" | "emg"

% Clean up only the TCP server on VIS_PORT from a previous run
try
    stream_out(0, "close", "", VIS_PORT);
end

% Ensure cleanup also happens when this script ends (even on Ctrl+C)
cleanupObj = onCleanup(@() stream_out(0, "close", "", VIS_PORT));

%% ============================
% Connect to RDA
% =============================

try
    bv_rda_client('close');
catch
end

bv_rda_client('open', host, port, nCh, fs);
pause(0.5);

% bv_rda_client('debug', true);

% trigger ingestion + debug prints
% for k = 1:20
%     X = bv_rda_client('pull', 0.02);
%     fprintf("range uV: [%.2f, %.2f], mean=%.2f\n", min(X(:)), max(X(:)), mean(X(:)));
%     pause(0.02);
% end



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
        % v = dataRaw(8,1);                           % one sample, one channel
        v = dataRaw(8,end);

        stream_out(v, "tcp", VIS_IP, VIS_PORT);
    end

    %% =============== SEND FFT OVER TCP (binary float32) ===============
    if ENABLE_TCP_FFT
        opts = struct('winSec',1.0,'nfft',512,'smoothAlpha',0.3,'return',"fft");
        out  = eeg_fft_realtime(Xuse, fs, opts);

        nCh   = 32;
        nBins = 257;

        testFFT = zeros(nCh, nBins);

        for ch = 1:nCh
            testFFT(ch, 1) = ch;              % channel index marker
            testFFT(ch, 2:end) = 1:(nBins-1); % ramp so TD can see ordering
        end


        if out.ready
            fftMag = abs(out.fft);                 % [nCh x nBins] numeric
            fprintf('[stream_to_visualiser] FFT ready, sending over TCP...\n');
            fprintf("ready=%d | size(psd)=%s | size(fft)=%s\n", ...
                out.ready, mat2str(size(out.psd)), mat2str(size(out.fft)));

            stream_out(Xuse, "tcp", VIS_IP, VIS_PORT);


        end



    end


    % ====== STREAM ONE NORMALIZED FEATURE (0..1) FAST ======
    if ENABLE_FEATURE
        y01 = feature_norm01(Xuse, fs, FEATURE_MODE);   % [0,1]
        % Send one value per line to TouchDesigner TCP/IP DAT (Server)
        stream_out(sprintf('%.6f\n', y01), "tcp", VIS_IP, VIS_PORT);
    end


    drawnow limitrate nocallbacks;
end

function y01 = feature_norm01(Xuse, fs, mode)
% FEATURE_NORM01  Returns one normalized scalar in [0,1] for visualization.
%
% mode:
%   "kurtosis" -> artifact/spike intensity
%   "alpha"    -> calm/alpha energy (8–13 Hz)
%   "emg"      -> movement/EMG burst (30–80 Hz or 30–100 Hz depending on fs)

arguments
    Xuse {mustBeNumeric}
    fs (1,1) double {mustBePositive}
    mode (1,1) string
end

% ---- persistent state (rolling window + normalization) ----
persistent RB nWin mu var featPrev step lastMode lastFs

% ---- parameters ----
winSec     = 1.0;                 % 1-second stable feature window
nWinTarget = max(64, round(winSec * fs));
smoothAlpha = 0.2;                % feature smoothing (0..1)
baseAlpha   = 0.01;               % baseline adapts slowly
computeEvery = 3;                 % do heavy compute every N calls (keeps speed)

[nCh, nNew] = size(Xuse);

% ---- re-init if needed ----
if isempty(RB) || isempty(nWin) || size(RB,1) ~= nCh || nWin ~= nWinTarget || isempty(lastMode) || mode ~= lastMode || isempty(lastFs) || fs ~= lastFs
    nWin = nWinTarget;
    RB = zeros(nCh, nWin, 'single');
    mu = 0; var = 1;
    featPrev = 0;
    step = 0;
    lastMode = mode;
    lastFs = fs;
end

% ---- update rolling buffer ----
Xuse = single(Xuse);
if nNew >= nWin
    RB = Xuse(:, end-nWin+1:end);
else
    RB(:, 1:end-nNew) = RB(:, nNew+1:end);
    RB(:, end-nNew+1:end) = Xuse;
end

% ---- compute feature (optionally downsample compute cadence) ----
step = step + 1;

doCompute = (mod(step, computeEvery) == 0);

if ~doCompute
    feat = featPrev;  % reuse last computed feature
else
    switch lower(mode)
        case "kurtosis"
            % Artifact intensity: excess kurtosis across channels
            Xw = double(RB);
            Xw = Xw - mean(Xw, 2);
            kuCh = kurtosis(Xw, 0, 2) - 3;     % [nCh x 1]
            feat = median(kuCh);               % robust one number

        case "alpha"
            % Calm/alpha energy: average alpha bandpower across channels
            % Uses a simple FFT-based bandpower estimate from the rolling window.
            Xw = double(RB);
            Xw = Xw - mean(Xw, 2);

            nfft = 2^nextpow2(size(Xw,2));
            Y = fft(Xw, nfft, 2);
            P = abs(Y(:,1:floor(nfft/2)+1)).^2;
            f = (0:floor(nfft/2))*(fs/nfft);

            idx = (f >= 8) & (f <= 13);
            if any(idx)
                alphaPowCh = mean(P(:,idx), 2);
                feat = log10(mean(alphaPowCh) + eps);  % log compress
            else
                feat = featPrev;
            end

        case "emg"
            % Movement/EMG burst: high-frequency power (typically 30–80/100 Hz)
            Xw = double(RB);
            Xw = Xw - mean(Xw, 2);

            nfft = 2^nextpow2(size(Xw,2));
            Y = fft(Xw, nfft, 2);
            P = abs(Y(:,1:floor(nfft/2)+1)).^2;
            f = (0:floor(nfft/2))*(fs/nfft);

            hiMax = min(100, fs/2 - 1);       % don’t exceed Nyquist
            idx = (f >= 30) & (f <= hiMax);
            if any(idx)
                hiPowCh = mean(P(:,idx), 2);
                feat = log10(mean(hiPowCh) + eps);     % log compress
            else
                feat = featPrev;
            end

        otherwise
            error('Unknown mode "%s". Use "kurtosis", "alpha", or "emg".', mode);
    end
end

% ---- smooth feature ----
featSmooth = smoothAlpha*feat + (1-smoothAlpha)*featPrev;
featPrev = featSmooth;

% ---- normalize to 0..1 using EMA z-score + tanh squash ----
mu = (1-baseAlpha)*mu + baseAlpha*featSmooth;
dx = featSmooth - mu;
var = (1-baseAlpha)*var + baseAlpha*(dx*dx);
sigma = sqrt(max(var, 1e-12));

z = dx / sigma;
z = max(min(z, 4), -4);
y01 = 0.5 * (tanh(z/2) + 1);
end
