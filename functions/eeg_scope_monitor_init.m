function mon = eeg_scope_monitor_init(nCh, fs, chanLabels)
% EEG_SCOPE_MONITOR_INIT
% Create advanced EEG monitor:
%   - raw vs processed data
%   - channel groups (All, 1-8, 9-16, ...)
%   - time window (1, 2, 5 s)
%   - mean-per-channel overlay toggle
%   - multicolor toggle
%   - channel numbers shown near traces

maxWinSec = 5;                 % largest window we support
bufLen    = fs * maxWinSec;

mon = struct();
mon.nCh   = nCh;
mon.fs    = fs;
mon.labels = chanLabels(:);

mon.fig = figure('Name','EEG Monitor', ...
                 'NumberTitle','off');

mon.ax  = axes('Parent', mon.fig);
hold(mon.ax, 'on');
xlabel(mon.ax, 'Time');
ylabel(mon.ax, 'Channel');
title(mon.ax, 'EEG Monitor (raw / processed)');

% Buffers for raw & processed
mon.buf_raw  = zeros(nCh, bufLen);
mon.buf_proc = zeros(nCh, bufLen);
mon.pos      = 0;

% Default options
mon.winOptions  = [1 2 5];     % seconds
mon.winIdx      = 3;           % default = 5 s
mon.dataModes   = {'Raw','Processed'};
mon.dataIdx     = 1;           % default = Raw
mon.groupIdx    = 1:nCh;       % visible channels (default All)
mon.showMean    = true;
mon.multicolor  = true;

% Plot lines (one per channel)
tAxis = (0:bufLen-1) / fs;
mon.lines = gobjects(nCh,1);
for c = 1:nCh
    mon.lines(c) = plot(mon.ax, tAxis, nan(1, numel(tAxis)));
end

mon.textHandles = gobjects(0);

% Colormap for multicolor mode
cols = lines(nCh);
mon.colors = cols;

% ---------- UI controls ----------

% Channel group labels: All, 1-8, 9-16, ...
groupLabels = {'All'};
for startIdx = 1:8:nCh
    endIdx = min(startIdx+7, nCh);
    groupLabels{end+1} = sprintf('%d-%d', startIdx, endIdx); %#ok<AGROW>
end

uicontrol('Style','text', 'Parent',mon.fig, ...
    'String','Channels', 'Units','pixels', 'Position',[10 60 70 15]);

mon.ui.groupPopup = uicontrol('Style','popupmenu', ...
    'Parent', mon.fig, ...
    'String', groupLabels, ...
    'Units','pixels', ...
    'Position', [10 40 120 20], ...
    'Callback', @(src,evt)onGroupChange(src,mon));

uicontrol('Style','text', 'Parent',mon.fig, ...
    'String','Window', 'Units','pixels', 'Position',[10 100 70 15]);

mon.ui.winPopup = uicontrol('Style','popupmenu', ...
    'Parent', mon.fig, ...
    'String', {'1 s','2 s','5 s'}, ...
    'Units','pixels', ...
    'Position', [10 80 80 20], ...
    'Value', mon.winIdx, ...
    'Callback', @(src,evt)onWindowChange(src,mon));

uicontrol('Style','text', 'Parent',mon.fig, ...
    'String','Data', 'Units','pixels', 'Position',[10 140 70 15]);

mon.ui.dataPopup = uicontrol('Style','popupmenu', ...
    'Parent', mon.fig, ...
    'String', mon.dataModes, ...
    'Units','pixels', ...
    'Position', [10 120 80 20], ...
    'Value', mon.dataIdx, ...
    'Callback', @(src,evt)onDataModeChange(src,mon));

mon.ui.meanCheckbox = uicontrol('Style','checkbox', ...
    'Parent', mon.fig, ...
    'String', 'Show mean per channel', ...
    'Value', mon.showMean, ...
    'Units','pixels', ...
    'Position', [120 120 160 20], ...
    'Callback', @(src,evt)onMeanToggle(src,mon));

mon.ui.colorCheckbox = uicontrol('Style','checkbox', ...
    'Parent', mon.fig, ...
    'String', 'Multicolor', ...
    'Value', mon.multicolor, ...
    'Units','pixels', ...
    'Position', [120 80 100 20], ...
    'Callback', @(src,evt)onColorToggle(src,mon));

guidata(mon.fig, mon);
end

% ---------- UI callbacks (update mon struct in guidata) ----------

function onGroupChange(src,mon)
mon = guidata(mon.fig);
labels = src.String;
val    = src.Value;
choice = labels{val};

if strcmpi(choice, 'All')
    mon.groupIdx = 1:mon.nCh;
else
    parts = sscanf(choice, '%d-%d');
    if numel(parts) == 2
        mon.groupIdx = parts(1):parts(2);
    else
        mon.groupIdx = 1:mon.nCh;
    end
end
guidata(mon.fig, mon);
end

function onWindowChange(src,mon)
mon = guidata(mon.fig);
mon.winIdx = src.Value;  % 1 -> 1s, 2 -> 2s, 3 -> 5s
guidata(mon.fig, mon);
end

function onDataModeChange(src,mon)
mon = guidata(mon.fig);
mon.dataIdx = src.Value; % 1=Raw, 2=Processed
guidata(mon.fig, mon);
end

function onMeanToggle(src,mon)
mon = guidata(mon.fig);
mon.showMean = logical(src.Value);
guidata(mon.fig, mon);
end

function onColorToggle(src,mon)
mon = guidata(mon.fig);
mon.multicolor = logical(src.Value);
guidata(mon.fig, mon);
end
