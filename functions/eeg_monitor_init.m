function mon = eeg_monitor_init()
% EEG_MONITOR_INIT  Create monitor figure and axes.

mon.fig = figure('Name','Live EEG Stream Monitor','Color','w');
mon.ax1 = subplot(2,1,1);
mon.ax2 = subplot(2,1,2);
hold(mon.ax1,'on');
hold(mon.ax2,'on');

title(mon.ax1,'Last 1-sec EEG snippet (first 8 channels)');
xlabel(mon.ax1,'Samples'); ylabel(mon.ax1,'Amplitude (µV)');
title(mon.ax2,'Channel mean amplitudes');
xlabel(mon.ax2,'Channel'); ylabel(mon.ax2,'µV');
ylim(mon.ax2,[-100 100]);
end
