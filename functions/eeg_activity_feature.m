function out = eeg_activity_feature(Xuse, fs, mode, streamId, opts)
% EEG_ACTIVITY_FEATURE
% One-scalar EEG features + robust normalization per stream.
%
% NEW MODE:
%   "improv_prob" -> logistic model probability p(improv) in [0,1]
%                   uses opts.model.betaVec, opts.model.muFeat, opts.model.sdFeat

arguments
    Xuse {mustBeNumeric}
    fs (1,1) double {mustBePositive}
    mode (1,1) string
    streamId (1,1) string
    opts.rawChannel (1,1) double {mustBePositive} = 8
    opts.rawAgg (1,1) string = "latest"
    opts.fftBand (1,2) double {mustBeNonnegative} = [5 40]
    opts.useHann (1,1) logical = true
    opts.pullDur (1,1) double {mustBePositive} = 0.02
    opts.updateHz (1,1) double {mustBePositive} = 15

    % For improv_prob
    opts.model struct = struct()     % expects fields betaVec, muFeat, sdFeat
end

persistent ST
if isempty(ST)
    ST = containers.Map('KeyType','char','ValueType','any');
end
sid = char(streamId);

if ~ST.isKey(sid)
    ST(sid) = init_state();
end
s = ST(sid);

% ---- parameters ----
winSec        = 1.0;
nWinTarget    = max(128, round(winSec * fs));
smoothAlpha   = 0.20;

% desired update rate -> computeEvery pulls
computeEvery = max(1, round((1/opts.updateHz) / opts.pullDur));

% normalization (for non-prob modes)
histMax       = 400;
pLo           = 10;
pHi           = 90;

if isempty(Xuse) || ~any(isfinite(Xuse(:)))
    out = blank_out(mode);
    return
end

[nCh, nNew] = size(Xuse);

% init / re-init
needInit = isempty(s.RB) || size(s.RB,1) ~= nCh || s.nWin ~= nWinTarget || s.lastFs ~= fs;
if needInit
    s.nWin     = nWinTarget;
    s.RB       = zeros(nCh, s.nWin, 'single');
    s.step     = 0;
    s.featPrev = 0;
    s.hist     = zeros(0,1);
    s.lastFs   = fs;
    s.filled   = 0;
end

% update rolling buffer
Xuse = single(Xuse);

if nNew >= s.nWin
    s.RB = Xuse(:, end-s.nWin+1:end);
    s.filled = 1;
else
    s.RB(:, 1:end-nNew) = s.RB(:, nNew+1:end);
    s.RB(:, end-nNew+1:end) = Xuse;
    s.filled = min(1, s.filled + double(nNew)/double(s.nWin));
end

% compute feature
s.step = s.step + 1;

modeL = lower(mode);

if modeL == "raw_voltage"
    featRaw = compute_raw_voltage(Xuse, opts.rawChannel, opts.rawAgg);

else
    doCompute = (mod(s.step, computeEvery) == 0);
    if ~doCompute
        featRaw = s.featPrev;   % hold last
    else
        if s.filled < 1
            featRaw = s.featPrev;  % hold until buffer full
        else
            if modeL == "improv_prob"
                featRaw = compute_improv_prob(double(s.RB), fs, opts.model);
            else
                featRaw = compute_mode_feature(double(s.RB), fs, mode, opts);
            end
        end
    end
end

if ~isfinite(featRaw), featRaw = 0; end

% smooth
featSmooth = smoothAlpha*featRaw + (1-smoothAlpha)*s.featPrev;
s.featPrev = featSmooth;

% -----------------------------
% OUTPUT MAPPING
% -----------------------------
if modeL == "improv_prob"
    % Probability already [0,1] -> do NOT percentile-normalize
    y01  = max(0, min(1, featSmooth));
    lo   = 0;
    hi   = 1;
    out  = struct('featRaw',featRaw,'featSmooth',featSmooth,'y01',y01,'lo',lo,'hi',hi,'mode',mode);
else
    % normalization (percentile) for non-prob modes
    s.hist(end+1,1) = featSmooth; %#ok<AGROW>
    if numel(s.hist) > histMax
        s.hist(1:numel(s.hist)-histMax) = [];
    end

    lo = prctile(s.hist, pLo);
    hi = prctile(s.hist, pHi);
    span = hi - lo;

    if ~isfinite(span) || span < 1e-9
        lo = featSmooth - 1;
        hi = featSmooth + 1;
        span = hi - lo;
    end

    y01 = (featSmooth - lo) / span;
    y01 = max(0, min(1, y01));

    out = struct('featRaw',featRaw,'featSmooth',featSmooth,'y01',y01,'lo',lo,'hi',hi,'mode',mode);
end

ST(sid) = s;

end

% ---------------- helpers ----------------
function s = init_state()
s = struct('RB',[],'nWin',0,'step',0,'featPrev',0,'hist',zeros(0,1), ...
    'lastFs',NaN,'filled',0);
end

function out = blank_out(mode)
out = struct('featRaw',0,'featSmooth',0,'y01',0.5,'lo',0,'hi',1,'mode',mode);
end

function v = compute_raw_voltage(Xuse, rawChannel, rawAgg)
[nCh, nSamp] = size(Xuse);
if nSamp == 0, v = 0; return; end
latest = double(Xuse(:, end));

switch lower(rawAgg)
    case "latest"
        ch = min(max(1, round(rawChannel)), nCh);
        v = latest(ch);
    case "mean"
        v = mean(latest, 'omitnan');
    case "median"
        v = median(latest, 'omitnan');
    otherwise
        error('opts.rawAgg must be "latest", "mean", or "median".');
end
end

function p = compute_improv_prob(Xw, fs, model)
% model.betaVec: (nFeat+1)x1, model.muFeat: 1xnFeat, model.sdFeat: 1xnFeat
% If model missing, return 0.5

if ~isfield(model,'betaVec') || ~isfield(model,'muFeat') || ~isfield(model,'sdFeat')
    p = 0.5; return;
end

betaVec = model.betaVec(:);
muFeat  = model.muFeat;
sdFeat  = model.sdFeat;

% Feature extractor (must match your training feature order)
% Xw is [nCh x nWin], already rolling window
Xw = Xw - mean(Xw,2);

[P,f] = simple_psd(Xw, fs);

% bands (match offline)
th = bandmean(P,f,4,7);
al = bandmean(P,f,8,12);
be = bandmean(P,f,13,30);

hiMax = min(45, fs/2-1);
hf = bandmean(P,f,30,hiMax);

base = bandmean(P,f,4,30) + eps;

thetaPow      = median(th, 'omitnan');
alphaPow      = median(al, 'omitnan');
betaPow       = median(be, 'omitnan');
alphaFraction = median(al ./ base, 'omitnan');
betaAlphaRatio= log10(median(be ./ (al + eps), 'omitnan') + eps);

totalHi = bandmean(P,f,4,hiMax) + eps;
hfFraction = median(hf ./ totalHi, 'omitnan');

idx = (f >= 5) & (f <= hiMax);
if any(idx)
    fftKurtosis = median(kurtosis(P(:,idx), 0, 2), 'omitnan');
else
    fftKurtosis = 0;
end

spectralSlope = spectral_slope(P, f, [2 40]);

rmsCh = sqrt(mean(Xw.^2,2));
rmsVal = median(rmsCh, 'omitnan');

timeKurtosis = median(kurtosis(Xw, 0, 2), 'omitnan');

x = [thetaPow, alphaPow, betaPow, alphaFraction, betaAlphaRatio, hfFraction, ...
    fftKurtosis, spectralSlope, rmsVal, timeKurtosis];

% z-score with training stats
xz = (x - muFeat) ./ (sdFeat + eps);

% logistic
z = betaVec(1) + xz(:)' * betaVec(2:end);
p = 1 / (1 + exp(-z));
p = max(0, min(1, p));
end

function feat = compute_mode_feature(Xw, fs, mode, opts)
Xw = Xw - mean(Xw,2);

switch lower(mode)
    case "rms_activity"
        rmsCh = sqrt(mean(Xw.^2, 2));
        feat  = median(rmsCh);

    case "alpha_fraction"
        [P,f] = simple_psd(Xw, fs);
        alpha = bandmean(P,f,8,13);
        total = bandmean(P,f,4,30) + eps;
        feat  = median(alpha ./ total);

    case "beta_alpha_ratio"
        [P,f] = simple_psd(Xw, fs);
        beta  = bandmean(P,f,13,30);
        alpha = bandmean(P,f,8,13) + eps;
        feat  = log10(median(beta ./ alpha) + eps);

    case "hf_fraction"
        [P,f] = simple_psd(Xw, fs);
        hiMax = min(100, fs/2 - 1);
        hf    = bandmean(P,f,30,hiMax);
        total = bandmean(P,f,4,hiMax) + eps;
        feat  = median(hf ./ total);

    case "fft_kurtosis"
        band = opts.fftBand;
        f1 = max(0, min(band(1), fs/2));
        f2 = max(0, min(band(2), fs/2));
        if f2 <= f1, feat = 0; return; end

        [P1, f] = onesided_fft_power(Xw, fs, opts.useHann);
        idx = (f >= f1) & (f <= f2);
        if ~any(idx)
            feat = 0;
        else
            Pb = P1(:, idx);
            k  = kurtosis(Pb, 0, 2);
            feat = median(k, 'omitnan');
        end

    otherwise
        error('Unknown mode "%s".', mode);
end

if ~isfinite(feat), feat = 0; end
end

function s = spectral_slope(P, f, fr)
idx = (f >= fr(1)) & (f <= fr(2));
ff = f(idx);
if numel(ff) < 5, s = NaN; return; end
c = polyfit(log10(ff(:)+eps), log10(median(P(:,idx),1)'+eps), 1);
s = c(1);
end

function [P1,f] = onesided_fft_power(Xw, fs, useHann)
[nCh, N] = size(Xw);
if useHann
    w = hann(N)';
    Xw = Xw .* w;
end
X  = fft(Xw, [], 2);
nH = floor(N/2) + 1;
Xh = X(:, 1:nH);
P1 = abs(Xh).^2;
f  = (0:nH-1) * (fs/N);
end

function [P,f] = simple_psd(Xw, fs)
nfft = 2^nextpow2(size(Xw,2));
Y = fft(Xw, nfft, 2);
P = abs(Y(:,1:floor(nfft/2)+1)).^2;
f = (0:floor(nfft/2))*(fs/nfft);
end

function m = bandmean(P,f,f1,f2)
idx = (f>=f1) & (f<=f2);
if ~any(idx)
    m = zeros(size(P,1),1);
else
    m = mean(P(:,idx),2);
end
end
