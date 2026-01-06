band        = 'alpha';     % band to compute (optional)
pullDur     = 0.2;         % seconds per pull
fs          = 500;         % sampling rate
host        = '192.168.50.7'; % BrainVision Recorder
%host        = '127.0.0.1'; % BrainVision Recorder
port        = 51244;       % RDA port
nCh         = 32;          % expected channels

try, bv_rda_client('close'); catch, end
bv_rda_client('open', host, port, nCh, fs);
pause(0.5);
bv_rda_client('debug', true);

for k = 1:30
    % X = bv_rda_client('pull', 0.02);
    % fprintf("pull %02d: %dx%d, mean=%.3f\n", k, size(X,1), size(X,2), mean(X(:)));
    X = bv_rda_client('pull', 0.02);
    fprintf("range uV: [%.2f, %.2f], mean=%.2f\n", min(X(:)), max(X(:)), mean(X(:)));
    pause(0.02);
end
