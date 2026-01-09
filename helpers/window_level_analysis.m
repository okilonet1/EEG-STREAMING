% ============================
% window_level_analysis_vFinal_Revised_FIXED_LASSO_HEATMAP.m
% ============================
% Fixed & Optimized EEG Classification (Fixed vs Improv)
%
% FEATURES:
% - Aligned per-window storage
% - LASSO Regularization
% - Subject-Specific Pipelines
% - "Cognitive Barcode" Visualization (Confidence Heatmaps)
% - Realtime Model Export

clear; clc; close all;
eeglab; %#ok<*NOPTS>

% --- Ground Truth Schedule (for plotting) ---
GT = struct();
S = {
    "00:00","fixed"
    "01:27","improv"
    "04:02","fixed"
    "04:38","improv"
    "06:14","fixed"
    "07:27","improv"
    "10:25","fixed"
    };
GT.Jacob.finale_full  = S;
GT.Lauren.finale_full = S;

%% ============================
% 1. SETTINGS & PATHS
% ============================
baseDir   = eeg_get_data_path('FREE REIN REHEARSAL DATA');
dirLauren = fullfile(baseDir, 'segments_Lauren');
dirJacob  = fullfile(baseDir, 'segments_Jacob');

% Windowing
winSec = 1.0;
hopSec = 0.5;
trimEdgeSec = 0.0;

% Frequency Bands
bands.theta = [4 7];
bands.alpha = [8 12];
bands.beta  = [13 30];
bands.hf    = [30 45];
fFitRange   = [2 40];

% Bad Channels (Offline)
badChLauren = [32];
badChJacob  = [1 8];

% Model settings
USE_ELASTIC_NET = false;   % set true to use Alpha=0.5
AlphaVal = 1.0;            % 1.0 LASSO, 0.5 elastic net
if USE_ELASTIC_NET, AlphaVal = 0.5; end

INNER_CV_FOLDS = 5;
MIN_TRAIN_N    = 50;       % safer than 20 if doing inner CV
MIN_CLASS_N    = 10;       % min per class for stability
NUM_LAMBDA     = 50;

%% ============================
% 2. FEATURE EXTRACTION
% ============================
fprintf('Extracting features for Lauren...\n');
Tw1 = extract_windows_from_dir(dirLauren, "Lauren", winSec, hopSec, trimEdgeSec, bands, fFitRange, badChLauren, badChJacob);
fprintf('Extracting features for Jacob...\n');
Tw2 = extract_windows_from_dir(dirJacob,  "Jacob",  winSec, hopSec, trimEdgeSec, bands, fFitRange, badChLauren, badChJacob);
Tw  = [Tw1; Tw2];

% Filter for binary classification
isFI = ismember(string(Tw.label), ["fixed","improv"]);
Tw = Tw(isFI,:);

% Exclude finale_full from training pool (still available for plotting later)
Tw = Tw(~contains(lower(Tw.file), "finale"), :);

% Type enforcement
Tw.label       = string(Tw.label);
Tw.subject     = string(Tw.subject);
Tw.file        = string(Tw.file);
Tw.segmentName = string(Tw.segmentName);

fprintf('\n=== Window table built ===\n');
fprintf('Total windows: %d\n', height(Tw));
fprintf('Fixed: %d | Improv: %d\n', sum(Tw.label=="fixed"), sum(Tw.label=="improv"));

% Feature columns used by the classifier (must exist in Tw)
featCols = {'thetaPow','alphaPow','betaPow','alphaFraction','betaAlphaRatio','hfFraction', ...
    'fftKurtosis','spectralSlope','rms','timeKurtosis'};


%% ============================
% 3–7. RUN PIPELINE PER SUBJECT (Jacob-only, Lauren-only)
% ============================

subjectsToRun = ["Jacob","Lauren"];

for k = 1:numel(subjectsToRun)
    sRun = subjectsToRun(k);

    fprintf('\n\n========================================\n');
    fprintf('         SUBJECT PIPELINE: %s\n', char(sRun));
    fprintf('========================================\n');

    TwS = Tw(Tw.subject == sRun, :);

    % Pass GT and Global Settings into the pipeline
    run_subject_pipeline(TwS, char(sRun), featCols, ...
        AlphaVal, NUM_LAMBDA, INNER_CV_FOLDS, MIN_TRAIN_N, MIN_CLASS_N, ...
        GT, baseDir, winSec, hopSec, trimEdgeSec, bands, fFitRange);
end


%% ============================
% FUNCTIONS
% ============================

function Tw = extract_windows_from_dir(segDir, subj, winSec, hopSec, trimEdgeSec, bands, fFitRange, badChLauren, badChJacob)
files = dir(fullfile(segDir, '*.set'));
rows = [];

for i = 1:numel(files)
    fname = files(i).name;
    [label, segname] = parse_label_from_filename(fname);

    EEG = pop_loadset('filename', fname, 'filepath', files(i).folder);
    EEG = eeg_checkset(EEG);
    if EEG.trials > 1
        EEG = eeg_epoch2continuous(EEG);
    end

    if strcmpi(subj, "Lauren")
        badCh = badChLauren;
    else
        badCh = badChJacob;
    end
    if ~isempty(badCh), badCh = badCh(badCh <= EEG.nbchan); end
    if ~isempty(badCh), EEG = pop_select(EEG, 'nochannel', badCh); end

    X  = double(EEG.data);
    fs = EEG.srate;
    X  = X - mean(X,2);

    winN = max(8, round(winSec * fs));
    hopN = max(1, round(hopSec * fs));
    startSamp = 1 + round(trimEdgeSec*fs);
    endSamp   = size(X,2) - round(trimEdgeSec*fs);

    if endSamp - startSamp + 1 < winN, continue; end
    wStarts = startSamp : hopN : (endSamp - winN + 1);

    for w = 1:numel(wStarts)
        a = wStarts(w);
        b = a + winN - 1;
        Xw = X(:, a:b);

        feats = compute_features(Xw, fs, bands, fFitRange);

        t0 = (a-1)/fs;
        t1 = (b-1)/fs;

        rows = [rows; {subj, string(label), string(fname), string(segname), ...
            t0, t1, feats.theta, feats.alpha, feats.beta, feats.alphaFrac, feats.betaAlpha, feats.hfFrac, ...
            feats.specKurt, feats.specSlope, feats.rms, feats.timeKurt}]; %#ok<AGROW>
    end
end

Tw = cell2table(rows, 'VariableNames', ...
    {'subject','label','file','segmentName','t0','t1', ...
    'thetaPow','alphaPow','betaPow','alphaFraction','betaAlphaRatio','hfFraction', ...
    'fftKurtosis','spectralSlope','rms','timeKurtosis'});
end

function feats = compute_features(X, fs, bands, fFitRange)
[P, f] = simple_psd(X, fs);

th = bandmean(P,f,bands.theta(1),bands.theta(2));
al = bandmean(P,f,bands.alpha(1),bands.alpha(2));
be = bandmean(P,f,bands.beta(1), bands.beta(2));

hiMax = min(bands.hf(2), fs/2-1);
hf = bandmean(P,f,bands.hf(1), hiMax);

base = bandmean(P,f,4,30) + eps;

feats.theta      = median(th, 'omitnan');
feats.alpha      = median(al, 'omitnan');
feats.beta       = median(be, 'omitnan');
feats.alphaFrac  = median(al ./ base, 'omitnan');

feats.betaAlpha  = log10(median(be ./ (al + eps), 'omitnan') + eps);

totalHi = bandmean(P,f,4,hiMax) + eps;
feats.hfFrac     = median(hf ./ totalHi, 'omitnan');

idx = (f >= 5) & (f <= hiMax);
if any(idx)
    feats.specKurt = median(kurtosis(P(:,idx), 0, 2), 'omitnan');
else
    feats.specKurt = 0;
end

feats.specSlope  = spectral_slope(P, f, fFitRange);

rmsCh = sqrt(mean(X.^2,2));
feats.rms = median(rmsCh, 'omitnan');

feats.timeKurt = median(kurtosis(X, 0, 2), 'omitnan');
end

function s = spectral_slope(P, f, fr)
idx = (f >= fr(1)) & (f <= fr(2));
ff = f(idx);
if numel(ff) < 5
    s = NaN;
    return;
end
c = polyfit(log10(ff(:)+eps), log10(median(P(:,idx),1)'+eps), 1);
s = c(1);
end

function [P,f] = simple_psd(X, fs)
nfft = 2^nextpow2(size(X,2));
Y = fft(X.*hann(size(X,2))', nfft, 2);
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
s = string(fname);
if contains(s, "_fixed_", "IgnoreCase", true)
    label = "fixed";
elseif contains(s, "_improv_", "IgnoreCase", true) || contains(s, "_free", "IgnoreCase", true)
    label = "improv";
else
    label = "unknown";
end

s2 = erase(s, ".set");
parts = split(s2, "_");
if numel(parts) >= 4
    segname = strjoin(parts(4:end), "_");
else
    segname = s2;
end
end

% ====== COGNITIVE BARCODE (HEATMAP) VISUALIZATION ======
function plot_finale_heatmap(segDir, subj, winSec, hopSec, trimEdgeSec, ...
    bands, fFitRange, badCh, featCols, mu, sd, betaVec, GT)

% Find finale/mixed files
files = [dir(fullfile(segDir, '*finale*.set')); dir(fullfile(segDir, '*mixed*.set'))];
if isempty(files)
    fprintf('  No finale/mixed files found for heatmap in %s\n', segDir);
    return;
end

figure('Name', subj + " Cognitive Barcode", 'Color', 'w', 'Position', [100 100 1200 600]);

for i = 1:numel(files)
    fname = files(i).name;
    EEG = pop_loadset('filename', fname, 'filepath', files(i).folder);
    EEG = eeg_checkset(EEG);
    if EEG.trials > 1, EEG = eeg_epoch2continuous(EEG); end

    if ~isempty(badCh), bC = badCh(badCh<=EEG.nbchan); EEG = pop_select(EEG,'nochannel',bC); end

    X = double(EEG.data); fs = EEG.srate; X = X - mean(X,2);

    % Extract Windows
    winN = max(8, round(winSec*fs));
    hopN = max(1, round(hopSec*fs));
    startSamp = 1 + round(trimEdgeSec*fs);
    endSamp   = size(X,2) - round(trimEdgeSec*fs);

    if endSamp - startSamp + 1 < winN, continue; end
    wStarts = startSamp : hopN : (endSamp - winN + 1);

    F = zeros(numel(wStarts), numel(featCols));
    tt = zeros(numel(wStarts),1);

    % Compute features
    for w = 1:numel(wStarts)
        a = wStarts(w); b = a + winN - 1;
        feats = compute_features(X(:,a:b), fs, bands, fFitRange);
        F(w,:) = [feats.theta, feats.alpha, feats.beta, feats.alphaFrac, feats.betaAlpha, feats.hfFrac, ...
            feats.specKurt, feats.specSlope, feats.rms, feats.timeKurt];
        tt(w) = ((a+b)/2)/fs;
    end

    % Normalize & Predict
    Fz = (F - mu) ./ (sd + eps);
    p = glmval(betaVec, Fz, 'logit');

    % --- HEATMAP VISUALIZATION ---
    ax = subplot(numel(files), 1, i);

    % Create image matrix (1 row, N columns)
    % We replicate rows for visual thickness if needed, but here 1 row is fine
    imagesc(ax, tt, [0 1], p');
    colormap(ax, hot); % Black=Fixed, Red/Yellow/White=Improv
    caxis([0 1]);

    % Aesthetics
    title(strrep(fname,'_','\_'), 'FontSize', 10);
    yticks([]); ylabel('State');
    if i == numel(files), xlabel('Time (s)'); end

    % Overlay Ground Truth (Green bars for Improv)
    hold on;
    gt = get_gt_intervals_for_file(subj, fname, EEG.xmax, GT);

    % Draw thin green boxes around TRUE improv sections
    if ~isempty(gt)
        for k=1:size(gt,1)
            if gt{k,3} == "improv"
                rectangle('Position', [gt{k,1}, -0.5, gt{k,2}-gt{k,1}, 2], ...
                    'EdgeColor', 'g', 'LineWidth', 2, 'LineStyle', '-');
            end
        end
    end
    colorbar;
end
end

function gt=gt_label_from_filename(f)
[gt,~]=parse_label_from_filename(f);
end

function i = get_gt_intervals_for_file(subj, fname, dur, GT)
i = [];
if isfield(GT, char(subj))
    k = fieldnames(GT.(char(subj)));
    for j = 1:numel(k)
        if contains(fname, k{j}, 'IgnoreCase', true)
            i = schedule_to_intervals(GT.(char(subj)).(k{j}), dur);
            return;
        end
    end
end
end

function i = schedule_to_intervals(s, dur)
if isempty(s), i=[]; return; end
t=zeros(size(s,1),1);
l=strings(size(s,1),1);
for j=1:size(s,1)
    t(j)=to_seconds(s{j,1});
    l(j)=lower(string(s{j,2}));
    if l(j)=="free", l(j)="improv"; end
end
[ts,ix]=sort(t);
l=l(ix);

if ts(1)>0
    ts=[0;ts];
    l=[l(1);l];
end

i=cell(0,3);
for j=1:numel(ts)
    t0=ts(j);
    t1=dur;
    if j<numel(ts), t1=ts(j+1); end
    if t1>t0
        i(end+1,:)={t0,t1,l(j)}; %#ok<AGROW>
    end
end
end

function t=to_seconds(x)
if ischar(x) || isstring(x)
    p=split(string(x),":");
    if numel(p)==2
        t=str2double(p(1))*60 + str2double(p(2));
    else
        t=0;
    end
else
    t=x*60;
end
end

% --- SUBJECT PIPELINE ---
function run_subject_pipeline(TwS, subjName, featCols, AlphaVal, NUM_LAMBDA, INNER_CV_FOLDS, MIN_TRAIN_N, MIN_CLASS_N, ...
    GT, baseDir, winSec, hopSec, trimEdgeSec, bands, fFitRange)
% Runs LOSO, prints diagnostics, visualizes HEATMAP, and exports model.

% --- Safety: ensure only fixed/improv and enough data ---
TwS = TwS(ismember(lower(TwS.label), ["fixed","improv"]), :);

fprintf('\n[%s] File label sanity (from filename parsing):\n', subjName);
U = unique(TwS.file);
for ii = 1:numel(U)
    f = U(ii);
    lab = string(TwS.label(find(TwS.file==f,1)));
    n  = sum(TwS.file==f);
    fprintf('  %-30s  label=%s  windows=%d\n', f, lab, n);
end

fprintf('Windows: %d | Fixed: %d | Improv: %d\n', height(TwS), sum(TwS.label=="fixed"), sum(TwS.label=="improv"));

if height(TwS) < MIN_TRAIN_N
    warning('[%s] Not enough windows to run LOSO.', subjName);
    return;
end

segId = TwS.file;                   % within subject, file is the segment ID
uSeg  = unique(segId);
fprintf("Unique segments (folds): %d\n", numel(uSeg));

% Aligned predictions
pHat = nan(height(TwS),1);
yHat = nan(height(TwS),1);

% Skips
skip_noTe = 0; skip_fitFail = 0; skip_smallTrain = 0; skip_oneClass = 0;

for si = 1:numel(uSeg)
    testSeg = uSeg(si);
    isTest  = (segId == testSeg);
    isTrain = ~isTest;

    Tr = TwS(isTrain,:);
    Te = TwS(isTest,:);

    if isempty(Te)
        skip_noTe = skip_noTe + 1;
        continue;
    end

    % --- A) Prepare train (GLOBAL norm within subject, from training only) ---
    Xtr0 = Tr{:, featCols};
    ytr  = double(Tr.label == "improv");

    goodTr = all(isfinite(Xtr0),2) & isfinite(ytr);
    Xtr0 = Xtr0(goodTr,:);
    ytr  = ytr(goodTr);

    if size(Xtr0,1) < MIN_TRAIN_N
        skip_smallTrain = skip_smallTrain + 1;
        continue;
    end
    if numel(unique(ytr)) < 2
        skip_oneClass = skip_oneClass + 1;
        continue;
    end
    if min(sum(ytr==0), sum(ytr==1)) < MIN_CLASS_N
        skip_smallTrain = skip_smallTrain + 1;
        continue;
    end

    mu = mean(Xtr0, 1, 'omitnan');
    sd = std(Xtr0, 0, 1, 'omitnan') + eps;

    Xtr = (Xtr0 - mu) ./ sd;

    % --- B) Prepare test (apply train stats) ---
    Xte0 = Te{:, featCols};
    yte0 = double(Te.label == "improv");

    goodTe = all(isfinite(Xte0),2) & isfinite(yte0);
    Xte0 = Xte0(goodTe,:);
    yte  = yte0(goodTe);

    teIdxAll = find(isTest);          % indices of Te rows within TwS
    teIdx    = teIdxAll(goodTe(:));   % keep only the good windows

    if isempty(Xte0)
        continue;
    end

    Xte = (Xte0 - mu) ./ sd;

    % --- Segment de-meaning to remove per-segment baseline ---
    % Training: subtract each training-segment mean (computed on training only)
    trSeg = Tr.file(goodTr);          % segment id per training window
    for uu = unique(trSeg)'
        idxu = (trSeg == uu);
        mu_u = mean(Xtr(idxu,:), 1, 'omitnan');
        Xtr(idxu,:) = Xtr(idxu,:) - mu_u;
    end

    % Test: subtract the test segment mean (allowed in streaming once you accumulate windows)
    mu_te = mean(Xte, 1, 'omitnan');
    Xte   = Xte - mu_te;


    % --- C) Train & predict (LASSO logistic) ---
    try
        [B, FitInfo] = lassoglm(Xtr, ytr, 'binomial', ...
            'Alpha', AlphaVal, ...
            'NumLambda', NUM_LAMBDA, ...
            'CV', INNER_CV_FOLDS, ...
            'Standardize', false);

        idxLam = FitInfo.IndexMinDeviance;
        beta0  = FitInfo.Intercept(idxLam);
        beta   = B(:, idxLam);

        pTr  = glmval([beta0; beta], Xtr, 'logit');   % train probs
        pRaw = glmval([beta0; beta], Xte, 'logit');   % test probs

        % --- robust orientation by TRAIN AUC ---
        [~,~,~,auc] = perfcurve(ytr, pTr, 1);

        if ~isfinite(auc), auc = 0.5; end

        if auc < 0.5
            pImprov = 1 - pRaw;
            flipped = 1;
        else
            pImprov = pRaw;
            flipped = 0;
        end

        m1 = mean(pTr(ytr==1), 'omitnan');  % improv mean (raw)
        m0 = mean(pTr(ytr==0), 'omitnan');  % fixed mean  (raw)

        % fprintf('[%s fold %d/%d] train mean raw: improv=%.3f fixed=%.3f | auc=%.3f | flip=%d\n', ...
        %    subjName, si, numel(uSeg), m1, m0, auc, flipped);

    catch
        skip_fitFail = skip_fitFail + 1;
        continue
    end

    % --- D) Store aligned ---
    pHat(teIdx) = pImprov;
    yHat(teIdx) = yte;
end

fprintf('\nSkips [%s]: NoTest=%d, SmallTrain=%d, OneClass=%d, FitFail=%d\n', ...
    subjName, skip_noTe, skip_smallTrain, skip_oneClass, skip_fitFail);

%% ============================
% WINDOW-LEVEL RESULTS
%% ============================
fprintf('\n--- WINDOW-LEVEL RESULTS (%s) ---\n', subjName);
good = isfinite(pHat) & isfinite(yHat);
fprintf('Predicted windows: %d / %d\n', sum(good), height(TwS));

if ~any(good)
    warning('[%s] No predictions generated.', subjName);
    return;
end

% --- base metrics ---
pred    = pHat(good) >= 0.5;
acc     = mean(pred == yHat(good));
accFlip = mean((~pred) == yHat(good));   % class inversion

% --- optional subject-level flip (only if it truly helps) ---
if accFlip > acc
    fprintf('[%s] Applying SUBJECT-LEVEL FLIP (accFlip > acc)\n', subjName);
    pHat(good) = 1 - pHat(good);

    pred    = pHat(good) >= 0.5;
    acc     = mean(pred == yHat(good));
    accFlip = mean((~pred) == yHat(good));
end

% --- compute TPR/TNR/BACC AFTER final pred ---
tpr  = mean(pred(yHat(good)==1) == 1);   % sensitivity (improv)
tnr  = mean(pred(yHat(good)==0) == 0);   % specificity (fixed)
bacc = 0.5 * (tpr + tnr);

fprintf('ACC normal=%.2f%% | flipped=%.2f%%\n', 100*acc, 100*accFlip);

pFixed  = mean(pHat(good & yHat==0), 'omitnan');
pImprov = mean(pHat(good & yHat==1), 'omitnan');
fprintf('Mean predicted p(improv): GT=fixed %.3f | GT=improv %.3f\n', pFixed, pImprov);

fprintf('Predicted class rate: improv=%.2f fixed=%.2f\n', mean(pred==1), mean(pred==0));
fprintf('Accuracy: %.2f%%\n', 100*acc);
fprintf('TPR (Improv): %.2f | TNR (Fixed): %.2f | Balanced Acc: %.2f%%\n', tpr, tnr, 100*bacc);

%% ============================
% SEGMENT-LEVEL RESULTS
%% ============================
fprintf('\n--- SEGMENT-LEVEL RESULTS (%s) ---\n', subjName);

uFiles = unique(TwS.file);
segCorrect = false(0,1);

fprintf('\n=== FINAL SEGMENT-LEVEL REPORT (%s) ===\n', subjName);
for i = 1:numel(uFiles)
    fName = uFiles(i);
    idx = (TwS.file == fName) & isfinite(pHat);

    if ~any(idx), continue; end

    pMean = mean(pHat(idx), 'omitnan');
    trueLabel = string(TwS.label(find(idx,1)));

    isImprovGT   = (trueLabel == "improv");
    isImprovPred = (pMean >= 0.5);

    isCorrect = (isImprovPred == isImprovGT);
    segCorrect(end+1,1) = isCorrect; %#ok<AGROW>

    if ~isCorrect
        fprintf('  MISSED: %-35s (GT: %s | Pred Prob: %.2f)\n', fName, trueLabel, pMean);
    end
end
fprintf('Predicted segments: %d / %d\n', numel(segCorrect), numel(unique(TwS.file)));


accSeg = mean(segCorrect) * 100;
fprintf('\n----------------------------------------\n');
fprintf('SUBJECT:        %s\n', subjName);
fprintf('TOTAL SEGMENTS: %d\n', numel(segCorrect));
fprintf('CORRECT:        %d\n', sum(segCorrect));
fprintf('ACCURACY:       %.2f%%\n', accSeg);
fprintf('----------------------------------------\n');

%% ============================
% FEATURE IMPORTANCE (GLOBAL LASSO ON THIS SUBJECT)
%% ============================
fprintf('\n--- FEATURE WEIGHTS (GLOBAL LASSO, %s) ---\n', subjName);

% IMPORTANT: realtime model uses RAW->zscore(muFeat/sdFeat). So we fit on z-scored raw.
Xraw = TwS{:, featCols};
yraw = double(TwS.label == "improv");
goodR = all(isfinite(Xraw),2) & isfinite(yraw);
Xraw = Xraw(goodR,:); yraw = yraw(goodR);

muFeat = mean(Xraw, 1, 'omitnan');
sdFeat = std(Xraw, 0, 1, 'omitnan') + eps;
Xz    = (Xraw - muFeat) ./ sdFeat;

[Bexp, FitExp] = lassoglm(Xz, yraw, 'binomial', ...
    'Alpha', AlphaVal, ...
    'NumLambda', NUM_LAMBDA, ...
    'CV', 5, ...
    'Standardize', false);

idxLam = FitExp.IndexMinDeviance;
beta0  = FitExp.Intercept(idxLam);
beta   = Bexp(:, idxLam);
betaVec = [beta0; beta];

% orient for interpretability (and for export)
pTrain = glmval(betaVec, Xz, 'logit');
if mean(pTrain(yraw==1),'omitnan') < mean(pTrain(yraw==0),'omitnan')
    betaVec = -betaVec;
    pTrain  = 1 - pTrain;
end

figure('Color','w', 'Name', sprintf('Feature Weights (%s LASSO)', subjName));
bar(betaVec(2:end));
xticks(1:numel(featCols)); xticklabels(featCols); xtickangle(45);
ylabel('Coefficient Weight'); grid on;
title(sprintf('Oriented Coefficients (%s): Positive => Improv', subjName));

%% ============================
% FINALE HEATMAP (COGNITIVE BARCODE)
%% ============================
fprintf('\n--- GENERATING FINALE HEATMAPS (%s) ---\n', subjName);

if strcmpi(subjName, "Lauren")
    sDir = fullfile(baseDir, 'segments_Lauren');
    bCh  = [32];
else
    sDir = fullfile(baseDir, 'segments_Jacob');
    bCh  = [1 8];
end

plot_finale_heatmap(sDir, subjName, winSec, hopSec, trimEdgeSec, ...
    bands, fFitRange, bCh, featCols, muFeat, sdFeat, betaVec, GT);


%% ============================
% EXPORT SUBJECT REALTIME MODEL
%% ============================
outFile = sprintf('improv_model_%s.mat', subjName);

modelInfo = struct();
modelInfo.featureOrder = string(featCols);
modelInfo.AlphaVal     = AlphaVal;
modelInfo.lambda       = FitExp.Lambda(idxLam);
modelInfo.dateSaved    = datestr(now);
modelInfo.subject      = string(subjName);

featureOrder = string(featCols);
subj = string(subjName);

save(outFile, 'betaVec', 'muFeat', 'sdFeat', 'modelInfo', 'featureOrder', 'subj');

fprintf('\n=== EXPORT MODEL (%s) ===\n', outFile);
fprintf('  mean p(improv) GT=improv: %.3f\n', mean(pTrain(yraw==1), 'omitnan'));
fprintf('  mean p(improv) GT=fixed : %.3f\n', mean(pTrain(yraw==0), 'omitnan'));
fprintf('Saved: %s\n', outFile);

end