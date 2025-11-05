clear bv_rda_client
close all
clc

% --- CONFIGURATION ---
host = '169.254.230.22';
port = 51244;
nCh  = 64;       % adjust if actual stream has fewer (try 32 if unsure)
fs   = 500;      % sampling rate in Hz
pullDur = 1.0;   % seconds per pull (1 s recommended)

fprintf('[EEG Monitor] Connecting to BrainVision RDA stream...\n');
try, bv_rda_client('close'); end
S = bv_rda_client('open', host, port, nCh, fs);
pause(2.0);  % allow recorder to start sending data

% --- Setup live figure ---
figure('Name','Live EEG Stream Monitor','Color','w');
ax1 = subplot(2,1,1);
ax2 = subplot(2,1,2);
hold(ax1,'on'); hold(ax2,'on');
title(ax1,'Last 1-sec EEG snippet (first 8 channels)');
xlabel(ax1,'Samples'); ylabel(ax1,'Amplitude (µV)');
title(ax2,'Channel mean amplitudes');
xlabel(ax2,'Channel'); ylabel(ax2,'µV');
ylim(ax2,[-100 100]); % adjust if signals are bigger

fprintf('[EEG Monitor] Streaming started... press Ctrl+C to stop.\n');

% --- Continuous monitoring loop ---
blockCount = 0;
while true
    % Pull 1-second block
    X = bv_rda_client('pull', pullDur);
    if isempty(X)
        fprintf('[%s] Empty block (no data yet)\n', datestr(now,'HH:MM:SS'));
        pause(0.5);
        continue;
    end

    % Some streams send in nV; if values are too small (<1e-3 µV), scale up
    if mean(abs(X(:))) < 1e-3
        fprintf('[Warning] Very low amplitude detected (<1e-3 µV)\n');
    end

    blockCount = blockCount + 1;
    [nChan, nSamp] = size(X);

    % Compute simple stats
    means = mean(X,2);
    nonzero = sum(any(X,2));
    fprintf('[%s] Block %d | %d samples | %d/%d active channels | mean range: %.2f–%.2f µV\n',...
        datestr(now,'HH:MM:SS'), blockCount, nSamp, nonzero, nChan, min(means), max(means));

    % --- Plot updates ---
    cla(ax1); cla(ax2);

    % plot first 8 channels
    plot(ax1, X(1:min(8,nChan), :)' + (0:min(7,nChan-1))*100, 'k');
    ylim(ax1,[-50 850]);
    xlim(ax1,[0 nSamp]);
    set(ax1,'YTick',(0:min(7,nChan-1))*100, 'YTickLabel',arrayfun(@(x)sprintf('Ch%d',x),1:min(8,nChan),'UniformOutput',false));
    
    % bar plot of channel means
    bar(ax2, means, 'FaceColor',[0.2 0.4 0.9]);
    ylim(ax2,[-100 100]);
    xlim(ax2,[0 nChan+1]);
    title(ax2,sprintf('Mean µV per Channel (Nonzero: %d/%d)', nonzero, nChan));
    
    drawnow limitrate nocallbacks;
end
