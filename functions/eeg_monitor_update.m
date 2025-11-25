function eeg_monitor_update(mon, Xuse, means, nonzero)
% EEG_MONITOR_UPDATE  Update the simple EEG monitor.

[nChan, nSamp] = size(Xuse);
ax1 = mon.ax1;
ax2 = mon.ax2;

cla(ax1); cla(ax2);

% Plot first 8 channels
nPlot = min(8, nChan);
plot(ax1, Xuse(1:nPlot, :)' + (0:nPlot-1)*100, 'k');
ylim(ax1,[-50 100*(nPlot-1)+150]);
xlim(ax1,[0 nSamp]);
set(ax1,'YTick',(0:nPlot-1)*100, ...
    'YTickLabel',arrayfun(@(x)sprintf('Ch%d',x),1:nPlot,'UniformOutput',false));

% Bar plot for means
bar(ax2, means, 'FaceColor',[0.2 0.4 0.9]);
ylim(ax2,[-100 100]);
xlim(ax2,[0 nChan+1]);
title(ax2,sprintf('Mean µV per Channel (Nonzero: %d/%d)', nonzero, nChan));
end
