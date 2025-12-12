function eeg_scope_monitor_update(mon, Xraw, Xproc)
% EEG_SCOPE_MONITOR_UPDATE
% Update the advanced monitor:
%   - Append new block to raw/processed buffers
%   - Use selected window length (1/2/5 s)
%   - Plot stacked traces for chosen channel group
%   - Show means if enabled
%   - Multicolor vs single-color
%   - Channel numbers next to traces
%
% mon   : struct from eeg_scope_monitor_init (stored in guidata)
% Xraw  : [nCh x nSamp] raw block
% Xproc : [nCh x nSamp] processed block

if ~isvalid(mon.fig)
    return;
end

mon = guidata(mon.fig);
[nChBlock, nSamp] = size(Xraw); %#ok<NASGU>

% Safety: clip to monitor's number of channels
nCh = min(mon.nCh, size(Xraw,1));
Xraw  = Xraw(1:nCh,:);
Xproc = Xproc(1:nCh,:);

% Append to buffers (circular)
bufLen = size(mon.buf_raw,2);
k      = size(Xraw,2);
idx    = mod(mon.pos + (1:k) - 1, bufLen) + 1;

mon.buf_raw(1:nCh, idx)  = Xraw;
mon.buf_proc(1:nCh,idx)  = Xproc;
mon.pos = idx(end);

% Which window?
winSec = mon.winOptions(mon.winIdx);  % 1,2,5
winSamples = min(winSec * mon.fs, bufLen);

% Extract tail
tailIdx = mod(mon.pos - (winSamples-1):mon.pos, bufLen) + 1;

if mon.dataIdx == 1
    bufPlot = mon.buf_raw(:, tailIdx);
else
    bufPlot = mon.buf_proc(:, tailIdx);
end

% Channel group
chIdx = intersect(mon.groupIdx, 1:nCh);
if isempty(chIdx)
    chIdx = 1:min(8,nCh);
end
bufPlot = bufPlot(chIdx,:);

% Build offsets
chStd = std(bufPlot, 0, 2);
baseScale = max(chStd);
if baseScale <= 0, baseScale = 1; end
offsets = (0:numel(chIdx)-1)' * (baseScale * 5);

% X axis
if winSec == 1
    % 1 s: show sample indices
    tAxis = 1:winSamples;
    mon.ax.XLabel.String = 'Samples';
else
    tAxis = (0:winSamples-1) / mon.fs;
    mon.ax.XLabel.String = 'Time (s)';
end

% Reset all lines to NaN
for c = 1:mon.nCh
    set(mon.lines(c), 'XData', tAxis, 'YData', nan(1, numel(tAxis)));
end

% Apply color mode
if mon.multicolor
    for c = 1:mon.nCh
        set(mon.lines(c), 'Color', mon.colors(c,:));
    end
else
    for c = 1:mon.nCh
        set(mon.lines(c), 'Color', [0 0.4470 0.7410]); % default blue
    end
end

% Plot selected channels
for kCh = 1:numel(chIdx)
    cGlobal = chIdx(kCh);
    set(mon.lines(cGlobal), 'XData', tAxis, ...
                            'YData', bufPlot(kCh,:) + offsets(kCh));
end

% Means overlay
if mon.showMean
    hold(mon.ax, 'on');
    % Remove old mean lines if any
    if isfield(mon,'meanLines') && ~isempty(mon.meanLines)
        delete(mon.meanLines(ishandle(mon.meanLines)));
    end
    mon.meanLines = gobjects(numel(chIdx),1);
    for kCh = 1:numel(chIdx)
        mu = mean(bufPlot(kCh,:)) + offsets(kCh);
        mon.meanLines(kCh) = plot(mon.ax, tAxis, mu*ones(size(tAxis)), ...
            'LineStyle','--','LineWidth',0.5,'Color',[0.5 0.5 0.5]);
    end
else
    if isfield(mon,'meanLines') && ~isempty(mon.meanLines)
        delete(mon.meanLines(ishandle(mon.meanLines)));
        mon.meanLines = [];
    end
end

% Channel numbers
if ~isempty(mon.textHandles)
    delete(mon.textHandles(ishandle(mon.textHandles)));
end
mon.textHandles = gobjects(numel(chIdx),1);
xRight = tAxis(end);
for kCh = 1:numel(chIdx)
    cGlobal = chIdx(kCh);
    yPos    = offsets(kCh);
    lab     = sprintf('%d', cGlobal);
    mon.textHandles(kCh) = text(mon.ax, xRight, yPos, lab, ...
        'HorizontalAlignment','left', ...
        'VerticalAlignment','middle', ...
        'Color',[0 0 0], ...
        'FontSize',8);
end

% Axes limits
mon.ax.YLim = [min(offsets)-baseScale*2, max(offsets)+baseScale*2];
mon.ax.XLim = [tAxis(1), tAxis(end)];

guidata(mon.fig, mon);
end
