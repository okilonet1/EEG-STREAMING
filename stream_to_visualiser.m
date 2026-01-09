% stream_to_visualiser.m
%
% Dual-stream EEG -> TouchDesigner + CSV recording
% - Pulls from TWO RDA streams
% - Computes one scalar output per stream (e.g., improv_prob)
% - Streams each scalar to its own TD TCP/IP DAT Server
% - Records streamed values to CSV under ./recording/

clear; close all; clc;
addpath('functions');

%% ============================
% CONFIG
%% ============================
cfg = struct();

cfg.pullDur = 0.02;     % seconds per pull
cfg.fs      = 500;      % Hz
cfg.nCh     = 32;

% Two RDA sources
cfg.host1 = '127.0.0.1';  cfg.port1 = 51244;
cfg.host2 = '127.0.0.1';  cfg.port2 = 51244;

% Names for recording filenames
cfg.streamName1 = "host1";
cfg.streamName2 = "host2";

% TouchDesigner targets (TCP/IP DAT in Server mode)
cfg.visIP    = "127.0.0.1";
cfg.visPort1 = 7006;
cfg.visPort2 = 7007;

% Mode to compute + stream
cfg.featureMode = "improv_prob";
cfg.updateHz    = 15;

% Monitor
cfg.enableMonitor = true;
cfg.monitorStream = 1;

% Recording
cfg.enableRecording = true;
cfg.recordEveryN    = 1;
cfg.recordType      = "feature_" + cfg.featureMode;

% Feature options
cfg.band    = 'alpha';
cfg.fftBand = eeg_get_band_ranges().(cfg.band);   % <-- use the function form you have

% Model file for improv_prob
cfg.modelFile = 'improv_model.mat';            % betaVec, muFeat, sdFeat

%% ============================
% INIT
%% ============================
cleanupObj = onCleanup(@cleanup_all);

% Recording
rec = struct('dir',"",'fid1',-1,'fid2',-1,'step',0);
if cfg.enableRecording
    [rec.dir, rec.fid1, rec.fid2] = recording_init(cfg.streamName1, cfg.streamName2, cfg.recordType);
end

% Close anything from a previous run
safe_close_rda_all();

% Open both streams
bv_rda_client('open', cfg.host1, cfg.port1, cfg.nCh, cfg.fs);
bv_rda_client('open', cfg.host2, cfg.port2, cfg.nCh, cfg.fs);
pause(0.3);

% Monitor init
if cfg.enableMonitor
    mon = eeg_monitor_init();
else
    mon = [];
end

% -------- Build Name-Value args ONCE --------
MJ = load('improv_model_Jacob.mat',  'betaVec','muFeat','sdFeat');
ML = load('improv_model_Lauren.mat', 'betaVec','muFeat','sdFeat');

opts1 = struct("pullDur", cfg.pullDur, "updateHz", cfg.updateHz, "fftBand", cfg.fftBand, "useHann", true, ...
    "model", struct("betaVec", MJ.betaVec, "muFeat", MJ.muFeat, "sdFeat", MJ.sdFeat));

opts2 = struct("pullDur", cfg.pullDur, "updateHz", cfg.updateHz, "fftBand", cfg.fftBand, "useHann", true, ...
    "model", struct("betaVec", ML.betaVec, "muFeat", ML.muFeat, "sdFeat", ML.sdFeat));




fprintf('[stream_to_visualiser] Dual streaming started… Ctrl+C to stop.\n');
if cfg.enableRecording
    fprintf('[recording] Writing CSVs to: %s\n', rec.dir);
end

%% ============================
% MAIN LOOP
%% ============================
while true
    [Xuse1, Xuse2] = pull_two_streams(cfg);

    % Monitor
    if cfg.enableMonitor && ~isempty(mon) && isvalid(mon.fig)
        update_monitor(mon, cfg.monitorStream, Xuse1, Xuse2);
    end

    % Feature + Stream + Record
    rec.step = rec.step + 1;
    doRec = cfg.enableRecording && (mod(rec.step, cfg.recordEveryN) == 0);

    if ~isempty(Xuse1) && any(isfinite(Xuse1(:)))
        o1 = eeg_activity_feature(Xuse1, cfg.fs, "improv_prob", "stream1", opts1);
        val1 = o1.y01;
        stream_out(val1, "tcp", cfg.visIP, cfg.visPort1);
        if doRec, recording_write(rec.fid1, val); end
    end

    if ~isempty(Xuse2) && any(isfinite(Xuse2(:)))
        o2 = eeg_activity_feature(Xuse2, cfg.fs, "improv_prob", "stream2", opts2);
        val2 = o2.y01;
        stream_out(val2, "tcp", cfg.visIP, cfg.visPort2);
        if doRec, recording_write(rec.fid2, val); end
    end

    drawnow limitrate nocallbacks;
end

%% ============================
% HELPERS
%% ============================

function [Xuse1, Xuse2] = pull_two_streams(cfg)
Xuse1 = [];
Xuse2 = [];

X1 = bv_rda_client(cfg.host1, cfg.port1, 'pull', cfg.pullDur);
X2 = bv_rda_client(cfg.host2, cfg.port2, 'pull', cfg.pullDur);

if ~isempty(X1)
    nUse  = min(cfg.nCh, size(X1,1));
    Xuse1 = X1(1:nUse, :);
end

if ~isempty(X2)
    nUse  = min(cfg.nCh, size(X2,1));
    Xuse2 = X2(1:nUse, :);
end
end

function update_monitor(mon, whichStream, Xuse1, Xuse2)
if whichStream == 2 && ~isempty(Xuse2)
    means   = mean(Xuse2,2);
    nonzero = sum(any(Xuse2,2));
    eeg_monitor_update(mon, Xuse2, means, nonzero);
elseif ~isempty(Xuse1)
    means   = mean(Xuse1,2);
    nonzero = sum(any(Xuse1,2));
    eeg_monitor_update(mon, Xuse1, means, nonzero);
end
end

function [recDir, fid1, fid2] = recording_init(streamName1, streamName2, recordType)
rootDir = fileparts(mfilename('fullpath'));
recDir  = fullfile(rootDir, 'recording');
if ~exist(recDir, 'dir'), mkdir(recDir); end

ts = datestr(now, 'yyyymmdd_HHMMSS');
f1 = fullfile(recDir, sprintf('%s__%s__%s.csv', streamName1, recordType, ts));
f2 = fullfile(recDir, sprintf('%s__%s__%s.csv', streamName2, recordType, ts));

fid1 = fopen(f1, 'w');
fid2 = fopen(f2, 'w');
if fid1 < 0 || fid2 < 0
    error('recording_init:FileOpenFailed', 'Could not open recording CSV files for writing.');
end

fprintf(fid1, 'iso_time,unix_time_s,value\n');
fprintf(fid2, 'iso_time,unix_time_s,value\n');
fprintf('[recording] opened:\n  %s\n  %s\n', f1, f2);
end

function recording_write(fid, value)
if fid < 0, return; end
t = datetime('now','TimeZone','local','Format','yyyy-MM-dd HH:mm:ss.SSS');
fprintf(fid, '%s,%.6f,%.10g\n', char(t), posixtime(t), value);
end

function safe_close_rda_all()
try, bv_rda_client('close'); catch, end
end

function cleanup_all()
try, bv_rda_client('close'); catch, end
try, stream_out(0, "close", "", []); catch, end

try
    ws = evalin('base','whos(''rec'')');
    if ~isempty(ws)
        rec = evalin('base','rec');
        if isfield(rec,'fid1') && rec.fid1 > 0, fclose(rec.fid1); end
        if isfield(rec,'fid2') && rec.fid2 > 0, fclose(rec.fid2); end
        fprintf('[recording] closed CSV files.\n');
    end
catch
end
end
