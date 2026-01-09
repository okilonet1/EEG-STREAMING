% =========================================
% report_bad_channels_all_segments.m
% =========================================
% Identifies bad EEG channels across ALL .set files
% and prints a summary (no data is modified).
%
% REQUIREMENTS:
%   - EEGLAB
%   - suggest_bad_channels.m on path
%
% OUTPUT:
%   - Per-file bad channel list
%   - Per-subject frequency summary
%   - Global summary across all segments

clear; clc; eeglab;

%% ============================
% CONFIGURATION
% ============================

baseDir   = eeg_get_data_path('FREE REIN REHEARSAL DATA');
dirs = {
    fullfile(baseDir, 'segments_Lauren'), 'Lauren';
    fullfile(baseDir, 'segments_Jacob'),  'Jacob';
    };

% Detection parameters (conservative, movement-safe)
opt.lineHz        = 60;
opt.rmsZ          = 3.5;
opt.flatVarFrac   = 0.02;
opt.corrMin       = 0.35;
opt.maxHz         = 45;

%% ============================
% RUN
% ============================

allRows = [];

for d = 1:size(dirs,1)
    segDir = dirs{d,1};
    subj   = dirs{d,2};

    files = dir(fullfile(segDir, '*.set'));
    if isempty(files)
        warning('No .set files found in %s', segDir);
        continue
    end

    fprintf('\n==============================\n');
    fprintf('Subject: %s\n', subj);
    fprintf('Directory: %s\n', segDir);
    fprintf('==============================\n');

    for i = 1:numel(files)
        fname = files(i).name;
        fpath = fullfile(files(i).folder, fname);

        EEG = pop_loadset(fpath);
        EEG = eeg_checkset(EEG);

        bad = suggest_bad_channels(EEG, ...
            'lineHz', 60, ...
            'rmsZ', 5.0, ...          % more conservative than 3.5
            'flatVarFrac', 0.005, ... % stricter definition of flatline
            'corrMin', -1.0, ...      % effectively disables corr rejection
            'maxHz', 45);


        if isempty(bad)
            fprintf('[OK]   %-45s  no bad channels\n', fname);
        else
            fprintf('[BAD]  %-45s  ch = %s\n', fname, mat2str(bad'));
        end

        % Store for summary
        for k = 1:numel(bad)
            allRows = [allRows; {subj, fname, bad(k)}]; %#ok<AGROW>
        end
    end
end

%% ============================
% SUMMARY
% ============================

if isempty(allRows)
    fprintf('\nNo bad channels detected in any segment.\n');
    return
end

T = cell2table(allRows, 'VariableNames', {'subject','file','channel'});
% ---- Force types (prevents duplicate channel groups like '9' vs ' 9') ----
if iscell(T.channel)
    T.channel = cell2mat(T.channel);
end
T.channel = double(T.channel);
T.channel = round(T.channel);   % just in case anything weird slipped in

% subject/file as strings for safe strcmp
if iscell(T.subject), T.subject = string(T.subject); end
if iscell(T.file),    T.file    = string(T.file);    end


fprintf('\n==============================\n');
fprintf('SUMMARY: bad-channel frequency\n');
fprintf('==============================\n');

% Per subject
subs = unique(T.subject);

for i = 1:numel(subs)
    s = subs(i);
    Ts = T(T.subject == s, :);

    fprintf('\nSubject: %s\n', s);

    u = unique(Ts.channel);
    cnt = zeros(size(u));
    for k = 1:numel(u)
        cnt(k) = sum(Ts.channel == u(k));
    end

    [cnt,ord] = sort(cnt, 'descend');
    u = u(ord);

    summaryTbl = table(u, cnt, 'VariableNames', {'channel','count'});
    disp(summaryTbl);
end

fprintf('\nGLOBAL (all subjects):\n');
u = unique(T.channel);
cnt = zeros(size(u));
for k = 1:numel(u)
    cnt(k) = sum(T.channel == u(k));
end
[cnt,ord] = sort(cnt,'descend');
u = u(ord);
disp(table(u,cnt,'VariableNames',{'channel','count'}));
