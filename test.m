
% ---- Connect to the simulator ----
nCh = 8;
fs  = 500;
S = bv_rda_client('open', '127.0.0.1', 51244, nCh, fs);

winSec = 1.0;  % window size to pull (seconds)
pause(0.5);    % small wait for first packets

% ---- Setup plot ----
figure('Name','Live EEG Stream','Color','w');
Y = bv_pull_block(winSec);
h = plot(Y, 'LineWidth', 1);
ylim([-60 60]);
xlabel('Samples'); ylabel('Amplitude (scaled µV)');
title('Live EEG (Simulated)');
grid on;

% ---- Real-time update loop ----
while isvalid(h(1))
    % Pull latest block
    Y = bv_pull_block(winSec);

    % Update existing plot lines efficiently
    for i = 1:length(h)
        set(h(i), 'YData', Y(:, i));
    end

    drawnow limitrate;  % refresh graphics
    pause(0.05);        % 20 FPS (~50 ms delay)
end

% ---- Clean up ----
bv_rda_client('close');
