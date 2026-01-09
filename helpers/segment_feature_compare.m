% ============================
% segment_feature_compare.m
% ============================
% Compute numeric features from clipped EEGLAB .set segments and compare
% improv vs fixed.

clear; clc;

% -------- EDIT: where your segments were saved --------
baseDir = eeg_get_data_path('FREE REIN REHEARSAL DATA');  % your helper
dirLauren = fullfile(baseDir, 'segments_Lauren');
dirJacob  = fullfile(baseDir, 'segments_Jacob');

% Frequency settings
bands.theta = [4 7];
bands.alpha = [8 12];
bands.beta  = [13 30];
bands.hf    = [30 45];  % keep <=45 to reduce EMG/aliasing; adjust if you want 30-80
fFitRange   = [2 40];   % for spectral slope fit (avoid DC, avoid high EMG)



% ---------- Run ----------
eeglab; %#ok<*NOPTS>


% If your montage has known bad channels, list them here (indices):
badChLauren = [32];
badChJacob  = [1 8];

T1 = compute_dir_features(dirLauren, "Lauren", bands, fFitRange, badChLauren, badChJacob);
T2 = compute_dir_features(dirJacob,  "Jacob",  bands, fFitRange, badChLauren, badChJacob);


T = [T1; T2];

% Keep only fixed/improv for classification (exclude mixed/finale etc.)
isFI = ismember(T.label, ["fixed","improv"]);
Tf  = T(isFI,:);

disp("=== Per-segment feature table (fixed/improv only) ===");
disp(Tf);

% -------- Simple comparisons (improv vs fixed) --------
fprintf('\n=== Mean features by label ===\n');
G = groupsummary(Tf, "label", "mean", Tf.Properties.VariableNames(5:end));
disp(G);

% Quick “which features differ most” (effect size-ish: |mean diff|/pooled std)
featCols = Tf.Properties.VariableNames(5:end);
diffScore = zeros(numel(featCols),1);

for k = 1:numel(featCols)
    xFix = Tf{Tf.label=="fixed", featCols{k}};
    xImp = Tf{Tf.label=="improv", featCols{k}};
    m1 = mean(xFix, 'omitnan'); m2 = mean(xImp, 'omitnan');
    s1 = std(xFix,  'omitnan'); s2 = std(xImp,  'omitnan');
    sp = sqrt(0.5*(s1.^2 + s2.^2) + eps);
    diffScore(k) = abs(m2 - m1) / sp;
end

[sortedScore, idx] = sort(diffScore, 'descend');
fprintf('\n=== Features ranked by separation (bigger is better) ===\n');
for i=1:min(10,numel(idx))
    fprintf('%2d) %-18s  score=%.3f\n', i, featCols{idx(i)}, sortedScore(i));
end

% -------- Train a quick classifier (logistic regression) --------
% Label: improv=1, fixed=0
y = double(Tf.label == "improv");

X = Tf{:, featCols};
% Normalize columns (z-score)
X = (X - mean(X,1,'omitnan')) ./ (std(X,0,1,'omitnan') + eps);

% Remove any rows with NaNs
good = all(isfinite(X),2) & isfinite(y);
X = X(good,:); y = y(good);

if size(X,1) >= 6
    B = glmfit(X, y, 'binomial', 'link', 'logit');
    p = glmval(B, X, 'logit');
    pred = p >= 0.5;
    acc = mean(pred == y);
    fprintf('\nClassifier (in-sample) accuracy: %.2f%% (quick sanity check)\n', 100*acc);
    fprintf('Top positive weights suggest features that increase with "improv".\n');

    w = B(2:end);
    [~, widx] = sort(abs(w), 'descend');
    for i=1:min(10,numel(widx))
        fprintf('%2d) %-18s  weight=%+.3f\n', i, featCols{widx(i)}, w(widx(i)));
    end
else
    fprintf('\nNot enough segments to fit a classifier robustly.\n');
end


% ============================
% FUNCTIONS
% ============================
function T = compute_dir_features(segDir, subj, bands, fFitRange, badChLauren, badChJacob)

files = dir(fullfile(segDir, '*.set'));
if isempty(files)
    warning('No .set files found in %s', segDir);
    T = table();
    return
end

rows = [];

for i = 1:numel(files)
    fname = files(i).name;
    fpath = fullfile(files(i).folder, fname);

    EEG = pop_loadset('filename', fname, 'filepath', files(i).folder);
    EEG = eeg_checkset(EEG);

    % ---- offline-only subject-specific bad channel removal ----
    if strcmpi(subj, "Lauren")
        badChThis = badChLauren;
    elseif strcmpi(subj, "Jacob")
        badChThis = badChJacob;
    else
        badChThis = [];
    end

    if ~isempty(badChThis)
        badChThis = badChThis(badChThis >= 1 & badChThis <= EEG.nbchan);
        if ~isempty(badChThis)
            EEG = pop_select(EEG, 'nochannel', badChThis);
            EEG = eeg_checkset(EEG);
        end
    end

    % Parse label from filename: e.g., Lauren_01_fixed_fix1.set
    [label, segname] = parse_label_from_filename(fname);

    % If epoched, convert to continuous
    if EEG.trials ~= 1
        EEG = eeg_epoch2continuous(EEG);
        EEG = eeg_checkset(EEG);
    end

    X  = double(EEG.data);
    fs = EEG.srate;

    % Basic de-mean
    X = X - mean(X,2);

    feats = compute_features(X, fs, bands, fFitRange);

    rows = [rows; {subj, label, string(fname), segname, ...
        feats.theta, feats.alpha, feats.beta, feats.alphaFrac, feats.betaAlpha, feats.hfFrac, ...
        feats.specKurt, feats.specSlope, feats.rms, feats.timeKurt}]; %#ok<AGROW>
end

T = cell2table(rows, 'VariableNames', ...
    {'subject','label','file','segmentName', ...
    'thetaPow','alphaPow','betaPow','alphaFraction','betaAlphaRatio','hfFraction', ...
    'fftKurtosis','spectralSlope','rms','timeKurtosis'});
end


function feats = compute_features(X, fs, bands, fFitRange)
% PSD
[P, f] = simple_psd(X, fs); % P: [nCh x nFreq]

% Band means (per channel)
th = bandmean(P,f,bands.theta(1),bands.theta(2));
al = bandmean(P,f,bands.alpha(1),bands.alpha(2));
be = bandmean(P,f,bands.beta(1), bands.beta(2));
hf = bandmean(P,f,bands.hf(1),   min(bands.hf(2), fs/2-1));

base = bandmean(P,f,4,30) + eps;

% Aggregate across channels robustly
feats.theta      = median(th, 'omitnan');
feats.alpha      = median(al, 'omitnan');
feats.beta       = median(be, 'omitnan');
feats.alphaFrac  = median(al ./ base, 'omitnan');
feats.betaAlpha  = log10(median(be ./ (al + eps), 'omitnan') + eps);

hiMax = min(bands.hf(2), fs/2-1);
totalHi = bandmean(P,f,4,hiMax) + eps;
feats.hfFrac     = median(hf ./ totalHi, 'omitnan'); % EMG-ish proxy

% Spectral kurtosis across frequency bins (per channel -> median)
idx = (f >= 5) & (f <= hiMax);
feats.specKurt   = median(kurtosis(P(:,idx), 0, 2), 'omitnan');

% Spectral slope (1/f): fit log10(P) vs log10(f) in fFitRange
feats.specSlope  = spectral_slope(P, f, fFitRange);

% Time-domain roughness / artifactiness
rmsCh = sqrt(mean(X.^2,2));
feats.rms = median(rmsCh, 'omitnan');
feats.timeKurt = median(kurtosis(X, 0, 2), 'omitnan');
end

function s = spectral_slope(P, f, fr)
idx = (f >= fr(1)) & (f <= fr(2));
ff = f(idx);
if numel(ff) < 5
    s = NaN; return
end
% Use channel-median spectrum for stability
S = median(P(:,idx), 1);
x = log10(ff(:) + eps);
y = log10(S(:)  + eps);
c = polyfit(x, y, 1);
s = c(1); % more negative = steeper 1/f
end

function [P,f] = simple_psd(X, fs)
% FFT-based PSD-like power (not scaled to physical units; good for comparison)
nfft = 2^nextpow2(size(X,2));
w = hann(size(X,2))';
Xw = X .* w;
Y = fft(Xw, nfft, 2);
P = abs(Y(:,1:floor(nfft/2)+1)).^2;
f = (0:floor(nfft/2))*(fs/nfft);
end

function m = bandmean(P,f,f1,f2)
idx = (f>=f1) & (f<=f2);
if ~any(idx)
    m = nan(size(P,1),1);
else
    m = mean(P(:,idx),2);
end
end

function [label, segname] = parse_label_from_filename(fname)
% Expected: Subject_##_<label>_<name>.set
s = string(fname);
s = erase(s, ".set");
parts = split(s, "_");
label = "unknown";
segname = s;

if numel(parts) >= 3
    label = lower(parts(3));
end
if numel(parts) >= 4
    segname = strjoin(parts(4:end), "_");
end

end
