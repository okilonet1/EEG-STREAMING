% ============================
% clip_improv_fixed_segments_from_notes.m
% ============================
% Uses your written timestamps (mm:ss strings or numeric minutes) to clip
% Lauren + Jacob recordings into EEGLAB .set segments.
%
% REQUIREMENTS:
%   - EEGLAB + bva-io (pop_loadbv)
%
% HOW TO USE:
%   1) Set dataDir + vhdr for Lauren and Jacob.
%   2) Run this script.
%   3) Segments saved under <dataDir>/segments_<subject>/
%

clear; clc;

%% ============================
% PATHS (EDIT THESE)
% ============================
dataDir = eeg_get_data_path('FREE REIN REHEARSAL DATA');
lauren.dataDir = dataDir;
lauren.vhdr    = 'jan5threhearsal.vhdr';            % <-- change

jacob.dataDir  = dataDir;
jacob.vhdr     = 'jan5threhearsalperson2(male).vhdr';             % <-- change

keepFirstN = 32;   % keep first 32 channels as EEG (set [] to keep all)

% Optional padding around each segment (seconds)
padBefore = 0.0;
padAfter  = 0.0;

% Optional quick PSD plots for QC
DO_PSD_QC = true;
PSD_FREQ_RANGE = [1 40];

%% ============================
% SEGMENTS FROM YOUR NOTES
% ============================
% Each row: {label, startTime, endTime, name}
% startTime/endTime can be:
%   - "mm:ss" string (e.g., "09:14")
%   - numeric minutes (e.g., 70.3) meaning minutes since start

laurenSegments = {
    "fixed",  "00:26",  "04:29",  "fix1";
    "improv", "09:14",  "13:30",  "improv1";
    "fixed",  "18:32",  "25:00",  "fix2";
    "improv", "31:40",  "36:30",  "improv2";
    "fixed",  "39:06",  "43:03",  "fix3";
    "improv", "49:35",  "53:20",  "improv3";

    % ========= FINALE FULL (NEW) =========
    % whole finale block as one continuous file
    "finale", "57:21",  "70:18",  "finale_full";

    % ========= LAUREN FINALE SPLIT (existing) =========
    "fixed",  "57:21",  "58:48",  "finale_fix1";
    "improv", "58:48",  "61:23",  "finale_improv1";
    "fixed",  "61:23",  "61:59",  "finale_fix2";
    "improv", "61:59",  "63:35",  "finale_improv2";
    "fixed",  "63:35",  "64:48",  "finale_fix3";
    "improv", "64:48",  "66:36",  "finale_improv3";
    "improv", "66:36",  "67:46",  "finale_free";
    "fixed",  "67:46",  "70:18",  "finale_fix4";
    };

jacobSegments = {
    "fixed",  "09:40",  "13:38",  "fix1";
    "fixed",  "14:03",  "18:36",  "fix2";
    "improv", "18:58",  "22:53",  "improv3";
    "improv", "23:13",  "27:31",  "improv1";
    "improv", "27:45",  "32:24",  "improv2";
    "fixed",  "32:47",  "36:47",  "fix3";

    % ========= FINALE FULL (NEW) =========
    "finale", "36:57",  "49:14",  "finale_full";

    % ========= FINALE SPLIT (existing) =========
    "fixed",  "36:57",  "38:24",  "finale_fix1";
    "improv", "38:24",  "40:59",  "finale_improv1";
    "fixed",  "40:59",  "41:35",  "finale_fix2";
    "improv", "41:35",  "43:11",  "finale_improv2";
    "fixed",  "43:11",  "44:24",  "finale_fix3";
    "improv", "44:24",  "46:12",  "finale_improv3";
    "improv", "46:12",  "47:22",  "finale_free";
    "fixed",  "47:22",  "49:14",  "finale_fix4";
    };



%% ============================
% RUN CLIPPING
% ============================
clip_subject(lauren, laurenSegments, "Lauren", keepFirstN, padBefore, padAfter, DO_PSD_QC, PSD_FREQ_RANGE);
clip_subject(jacob,  jacobSegments,  "Jacob",  keepFirstN, padBefore, padAfter, DO_PSD_QC, PSD_FREQ_RANGE);

fprintf('\nAll done.\n');

%% ============================
% FUNCTIONS
% ============================

function clip_subject(cfg, segTable, subjName, keepFirstN, padBefore, padAfter, DO_PSD_QC, PSD_FREQ_RANGE)
fprintf('\n==== %s ====\n', char(subjName));

[ALLEEG, EEG, CURRENTSET] = eeglab; %#ok<ASGLU>

% Force cfg fields to char (EEGLAB-friendly)
dataDirChar = char(cfg.dataDir);
vhdrChar    = char(cfg.vhdr);

EEG = pop_loadbv(dataDirChar, vhdrChar);
EEG = eeg_checkset(EEG);

if ~isempty(keepFirstN) && EEG.nbchan > keepFirstN
    EEG = pop_select(EEG, 'channel', 1:keepFirstN);
    EEG = eeg_checkset(EEG);
end

fs = EEG.srate;
T  = EEG.xmax; % seconds

fprintf('Loaded: %d chans, %.1f Hz, %.1f sec\n', EEG.nbchan, fs, T);

% Build output dir using chars only
subjNameChar = char(subjName);
outDirChar   = fullfile(dataDirChar, ['segments_' subjNameChar]);
if ~exist(outDirChar, 'dir'), mkdir(outDirChar); end

for i = 1:size(segTable,1)
    label = char(string(segTable{i,1}));
    t1    = to_seconds(segTable{i,2});
    t2    = to_seconds(segTable{i,3});
    name  = char(string(segTable{i,4}));

    % apply padding
    t1 = t1 - padBefore;
    t2 = t2 + padAfter;

    % clamp
    t1 = max(0, t1);
    t2 = min(T, t2);

    if ~(isfinite(t1) && isfinite(t2) && t2 > t1)
        warning('%s seg %d (%s): invalid times [%g, %g], skipping.', subjNameChar, i, name, t1, t2);
        continue
    end

    EEGseg = pop_select(EEG, 'time', [t1 t2]);
    EEGseg = eeg_checkset(EEGseg);

    EEGseg.setname = sprintf('%s_%02d_%s_%s_%0.1fs_%0.1fs', subjNameChar, i, label, name, t1, t2);

    % IMPORTANT: filename/filepath as scalar char
    outNameChar = sprintf('%s_%02d_%s_%s.set', subjNameChar, i, label, name);

    % Make sure fields exist and are char scalars (prevents pop_saveset strcmpi crash)
    EEGseg.filename = '';
    EEGseg.filepath = outDirChar;

    EEGseg = pop_saveset(EEGseg, 'filename', outNameChar, 'filepath', outDirChar);

    fprintf('Saved %-30s  [%7.2f  %7.2f] sec  (dur=%.2f s)\n', outNameChar, t1, t2, (t2-t1));

    if DO_PSD_QC
        fig = figure('Visible','off');
        try
            pop_spectopo(EEGseg, 1, [0 EEGseg.xmax*1000], 'EEG', ...
                'freqrange', PSD_FREQ_RANGE, 'electrodes','off');
            title(strrep(EEGseg.setname,'_','\_'));

            pngNameChar = strrep(outNameChar, '.set', '_PSD.png');
            saveas(fig, fullfile(outDirChar, pngNameChar));
        catch ME
            warning('%s seg %d PSD failed: %s', subjNameChar, i, ME.message);
        end
        close(fig);
    end
end

fprintf('Segments saved in: %s\n', outDirChar);
end


function t = to_seconds(x)
% Convert:
%   - "mm:ss" or "hh:mm:ss" string -> seconds
%   - numeric -> minutes (per your "70.3" note), converted to seconds

if isstring(x) || ischar(x)
    s = string(x);
    parts = split(s, ":");
    parts = strtrim(parts);

    if numel(parts) == 2
        mm = str2double(parts(1));
        ss = str2double(parts(2));
        t  = 60*mm + ss;
    elseif numel(parts) == 3
        hh = str2double(parts(1));
        mm = str2double(parts(2));
        ss = str2double(parts(3));
        t  = 3600*hh + 60*mm + ss;
    else
        error('Bad time string "%s". Use "mm:ss" or "hh:mm:ss".', s);
    end
else
    % numeric minutes -> seconds (your "70.3" style)
    t = double(x) * 60.0;
end
end
