function out = eeg_fft_realtime(Xnew, fs, opts)
% EEG_FFT_REALTIME  Real-time FFT/PSD (all channels) using a rolling buffer.
%
% out = eeg_fft_realtime(Xnew, fs, opts)
%
% Defaults (if opts fields not provided):
%   winSec      = 1.0
%   nfft        = 0        (auto = nextpow2(nwin))
%   overlapSec  = 0.75*winSec
%   window      = 'hann'
%   detrend     = true
%   onesided    = true
%   return      = 'psd'    ('fft'|'psd'|'both')
%   smoothAlpha = 0.0

% ---- basic input checks ----
if nargin < 2
    error('Usage: out = eeg_fft_realtime(Xnew, fs, opts)');
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isnumeric(Xnew)
    error('Xnew must be numeric [nCh x nNew].');
end
if ~isscalar(fs) || fs <= 0
    error('fs must be a positive scalar (Hz).');
end

% ---- defaults ----
cfg.winSec      = 1.0;
cfg.nfft        = 0;                 % 0 => auto
cfg.overlapSec  = 0.75 * cfg.winSec; % seconds
cfg.window      = 'hann';            % 'hann'|'hamming'|'rect'
cfg.detrend     = true;
cfg.onesided    = true;
cfg.return      = 'psd';             % 'fft'|'psd'|'both'
cfg.smoothAlpha = 0.0;               % 0=no smoothing

% ---- override defaults from opts ----
fn = fieldnames(opts);
for k = 1:numel(fn)
    cfg.(fn{k}) = opts.(fn{k});
end

% ---- validate cfg ----
cfg.winSec = max(0.05, double(cfg.winSec));  % don’t allow absurdly tiny windows
if ~isfield(cfg,'overlapSec') || isempty(cfg.overlapSec)
    cfg.overlapSec = 0.75 * cfg.winSec;
end
cfg.overlapSec  = max(0, double(cfg.overlapSec));
cfg.smoothAlpha = min(max(double(cfg.smoothAlpha), 0), 1);

cfg.window = lower(string(cfg.window));
cfg.return = lower(string(cfg.return));

persistent buf nCh nwin nfft hop winVec haveSamples psdSmooth fAxis hopCounter

% ---- initialize / re-init if channel count changes or cfg changes materially ----
[nCh_now, nNew] = size(Xnew);

% Compute derived sizes
nwin_new = max(1, round(cfg.winSec * fs));

if cfg.nfft > 0
    nfft_new = round(cfg.nfft);
else
    nfft_new = 2^nextpow2(nwin_new);
end
if nfft_new < nwin_new
    % don’t truncate data; keep nfft at least nwin
    nfft_new = 2^nextpow2(nwin_new);
end

overlapSamp = round(cfg.overlapSec * fs);
overlapSamp = min(max(overlapSamp, 0), nwin_new - 1);
hop_new     = max(1, nwin_new - overlapSamp);

needReinit = isempty(buf) || isempty(nCh) || (nCh_now ~= nCh) || ...
    isempty(nwin) || (nwin_new ~= nwin) || isempty(nfft) || (nfft_new ~= nfft) || ...
    isempty(hop)  || (hop_new  ~= hop);

if needReinit
    nCh  = nCh_now;
    nwin = nwin_new;
    nfft = nfft_new;
    hop  = hop_new;

    buf = zeros(nCh, nwin, 'single');
    haveSamples = 0;
    hopCounter  = 0;

    switch cfg.window
        case "hann"
            winVec = single(hann(nwin, 'periodic')).';
        case "hamming"
            winVec = single(hamming(nwin, 'periodic')).';
        otherwise
            winVec = single(ones(1, nwin));
    end

    if cfg.onesided
        nBins = floor(nfft/2) + 1;
        fAxis = (0:nBins-1) * (fs/nfft);
    else
        fAxis = (0:nfft-1) * (fs/nfft);
    end

    psdSmooth = [];
end

% ---- push new samples into rolling buffer ----
Xnew = single(Xnew);

if nNew >= nwin
    buf = Xnew(:, end-nwin+1:end);
    haveSamples = nwin;
else
    if nNew > 0
        buf(:, 1:(nwin-nNew)) = buf(:, (nNew+1):nwin);
        buf(:, (nwin-nNew+1):nwin) = Xnew;
        haveSamples = min(nwin, haveSamples + nNew);
    end
end

% ---- decide whether to emit an update ----
hopCounter = hopCounter + nNew;

out = struct('ready', false, 'f', [], 'psd', [], 'fft', [], 'nwin', nwin, 'nfft', nfft);

if haveSamples < nwin || hopCounter < hop
    return
end
hopCounter = 0;
out.ready = true;

% ---- preprocess ----
Xw = buf;
if cfg.detrend
    Xw = Xw - mean(Xw, 2, 'omitnan');
end
Xw = Xw .* winVec;

% ---- FFT ----
Y = fft(Xw, nfft, 2);

if cfg.onesided
    Yuse = Y(:, 1:(floor(nfft/2)+1));
else
    Yuse = Y;
end

% ---- PSD-like power ----
P = abs(Yuse).^2;
winPow = sum(double(winVec).^2);
P = P / max(winPow, eps);

if cfg.smoothAlpha > 0
    if isempty(psdSmooth) || ~isequal(size(psdSmooth), size(P))
        psdSmooth = P;
    else
        a = cfg.smoothAlpha;
        psdSmooth = a*P + (1-a)*psdSmooth;
    end
    P = psdSmooth;
end

out.f = fAxis;

switch cfg.return
    case "fft"
        out.fft = Yuse;
    case "both"
        out.fft = Yuse;
        out.psd = P;
    otherwise % "psd"
        out.psd = P;
end
end
