% ============================================================
% improv_realtime_pipeline.m
% ============================================================
% Better improv-vs-fixed model + realtime probability stream.
%
% WHAT YOU GET:
%  1) Stronger features aligned with alpha/internal-processing literature
%     + motor/beta signatures + variability + simple causal baseline removal
%  2) Subject-specific models saved to .mat:
%        improv_model_Jacob.mat
%        improv_model_Lauren.mat
%     Each contains: betaVec, muFeat, sdFeat, featureOrder, roiDefs, cfg
%  3) Realtime streaming of p(improv) over TCP as JSON (TouchDesigner-friendly)
%     or simply print/log.
%
% ASSUMPTIONS:
%  - You have EEGLAB on path for loading .set segments.
%  - For realtime: you have BrainVision Recorder RDA streaming enabled.
%  - You already have/used bv_rda_client (from earlier). This script calls it.
%
% CHANNEL LABELS EXPECTED (your list):
%   1 Fp1, 2 Fp2, 3 F3, 4 F4, 5 C3, 6 C4, 7 P3, 8 P4, 9 O1, 10 O2,
%   11 F7, 12 F8, 13 T7, 14 T8, 15 P7, 16 P8, 17 Fz, 18 Cz, 19 Pz,
%   20 FC1, 21 FC2, 22 CP1, 23 CP2, 24 FC5, 25 FC6, 26 CP5, 27 CP6,
%   28 TP9, 29 TP10, 30 Eog, 31 Ekg1, 32 Ekg2
%
% NOTES ON THE "JACOB FAIL / LAUREN WORK" PATTERN:
%  - This pipeline is robust to "strategy reversal" by:
%     (a) subject-specific models
%     (b) features that capture BOTH alpha/internal and beta/motor signatures
%     (c) realtime baseline removal (causal) to reduce segment bias
%
% ------------------------------------------------------------
clear; clc; close all;

%% ============================
% CONFIG
%% ============================
cfg = struct();

% Data paths
cfg.baseDir   = eeg_get_data_path('FREE REIN REHEARSAL DATA');
cfg.dirLauren = fullfile(cfg.baseDir, 'segments_Lauren');
cfg.dirJacob  = fullfile(cfg.baseDir, 'segments_Jacob');

% Windowing
cfg.winSec = 1.0;
cfg.hopSec = 0.5;
cfg.trimEdgeSec = 0.0;

% Bands
cfg.bands.theta = [4 7];
cfg.bands.alpha = [8 12];
cfg.bands.beta  = [13 30];
cfg.bands.gamma = [30 45];      % optional, often motion-noisy
cfg.fFitRange   = [2 40];       % for spectral slope

% Bad channels for offline (you said earlier)
cfg.badChLauren = [32];         % (if you want to drop Ekg2 only, keep as is)
cfg.badChJacob  = [1 8];        % (example you used earlier)
% NOTE: In *this* pipeline we will always drop EOG/EKG by label anyway.

% LASSO logistic
cfg.AlphaVal     = 1.0;   % 1=LASSO, 0.5=elastic net
cfg.NUM_LAMBDA   = 60;
cfg.CV_FOLDS     = 5;

% Realtime baseline removal (causal)
% baseline_t = (1-alphaBaseline)*baseline + alphaBaseline*current
cfg.alphaBaseline = 0.02;   % smaller => slower baseline drift removal
cfg.alphaSmoothP  = 0.20;   % prob smoothing for visualization

% RDA realtime config
rt = struct();
rt.host    = '127.0.0.1';
rt.port    = 51244;         % BrainVision RDA default
rt.fs      = 500;           % set to your actual
rt.nCh     = 32;            % your cap
rt.pullDur = 0.05;          % seconds per pull
rt.outMode = "tcp";         % "tcp" | "print" | "none"
rt.tcpIP   = "127.0.0.1";
rt.tcpPort = 7006;          % TouchDesigner listening port (example)

% Subject models to train/export
subjects = ["Jacob","Lauren"];

%% ============================
% ROI DEFINITIONS (by label)
%% ============================
roiDefs = default_roi_defs();

%% ============================
% 1) TRAIN + EXPORT SUBJECT MODELS
%% ============================
fprintf('=== TRAINING & EXPORTING SUBJECT MODELS ===\n');

for s = subjects
    subj = char(s);

    if strcmpi(subj,'Lauren'), segDir = cfg.dirLauren; else, segDir = cfg.dirJacob; end

    fprintf('\n--- Extract windows for %s ---\n', subj);
    Tw = extract_windows_from_dir_v2(segDir, subj, cfg, roiDefs);

    % keep only fixed/improv and exclude finale
    Tw = Tw(ismember(lower(Tw.label), ["fixed","improv"]), :);
    Tw = Tw(~contains(lower(Tw.file), "finale"), :);

    fprintf('[%s] Windows=%d | Fixed=%d | Improv=%d\n', subj, height(Tw), sum(Tw.label=="fixed"), sum(Tw.label=="improv"));

    % train + export
    outFile = sprintf('improv_model_%s.mat', subj);
    model = train_export_subject_model(Tw, subj, cfg, roiDefs, outFile);

    % quick LOSO sanity (optional but recommended)
    fprintf('[%s] Running LOSO sanity...\n', subj);
    loso_subject_sanity(Tw, subj, cfg, model);

    fprintf('[%s] Done.\n', subj);
end

fprintf('\n=== DONE EXPORTING MODELS ===\n');
fprintf('Saved: improv_model_Jacob.mat, improv_model_Lauren.mat\n');

%% ============================
% 2) REALTIME STREAM (pick one subject model)
%% ============================
% Choose which model to run in realtime:
%   realtime_improv_stream('Jacob', rt);
%   realtime_improv_stream('Lauren', rt);

% Uncomment to run:
% realtime_improv_stream('Lauren', rt);

%% ============================================================
% FUNCTIONS
%% ============================================================

function roiDefs = default_roi_defs()
% ROI definitions using YOUR channel labels.
% We drop Eog/Ekg in feature computations.
roiDefs = struct();

roiDefs.Frontal = ["Fp1","Fp2","F3","F4","F7","F8","Fz","FC1","FC2","FC5","FC6"];
roiDefs.Central = ["C3","C4","Cz"];
roiDefs.Parietal = ["P3","P4","P7","P8","Pz","CP1","CP2","CP5","CP6"];
roiDefs.Occipital = ["O1","O2"];
roiDefs.Temporal = ["T7","T8","TP9","TP10"];

roiDefs.ALL_EEG = unique([roiDefs.Frontal, roiDefs.Central, roiDefs.Parietal, roiDefs.Occipital, roiDefs.Temporal]);
roiDefs.NON_EEG = ["Eog","Ekg1","Ekg2"];
end

function Tw = extract_windows_from_dir_v2(segDir, subj, cfg, roiDefs)
% Loads .set segments, makes sliding windows, computes ROI features designed for improv detection.

files = dir(fullfile(segDir,'*.set'));
rows = [];

for i = 1:numel(files)
    fname = files(i).name;
    [label, segname] = parse_label_from_filename(fname);

    EEG = pop_loadset('filename', fname, 'filepath', files(i).folder);
    EEG = eeg_checkset(EEG);
    if EEG.trials > 1, EEG = eeg_epoch2continuous(EEG); end

    labels = upper(string({EEG.chanlocs.labels}));
    X = double(EEG.data);
    fs = EEG.srate;

    % --- drop non-EEG channels by label (EOG/EKG) ---
    keep = ~ismember(upper(labels), upper(roiDefs.NON_EEG));
    X = X(keep,:);
    labels = labels(keep);

    % --- optional offline subject-specific bad channels (index-based) ---
    if strcmpi(subj,"Lauren")
        badCh = cfg.badChLauren;
    else
        badCh = cfg.badChJacob;
    end
    % badCh given in original 32ch indexing; map to remaining channels if possible
    % simplest: ignore index-based removal here because we already removed EOG/EKG and label sets vary.
    % If you REALLY want index-based removal, do it before label-based drop.

    % demean channels
    X = X - mean(X,2);

    winN = max(8, round(cfg.winSec * fs));
    hopN = max(1, round(cfg.hopSec * fs));
    startSamp = 1 + round(cfg.trimEdgeSec*fs);
    endSamp   = size(X,2) - round(cfg.trimEdgeSec*fs);

    if endSamp - startSamp + 1 < winN, continue; end
    wStarts = startSamp : hopN : (endSamp - winN + 1);

    for w = 1:numel(wStarts)
        a = wStarts(w);
        b = a + winN - 1;
        Xw = X(:,a:b);

        feats = compute_features_roi_v2(Xw, labels, fs, cfg.bands, cfg.fFitRange, roiDefs);

        t0 = (a-1)/fs;
        t1 = (b-1)/fs;

        rows = [rows; {string(subj), string(label), string(fname), string(segname), ...
            t0, t1, ...
            feats.alphaP, feats.betaP, feats.thetaP, ...
            feats.alphaFrac, feats.betaFrac, feats.betaAlpha, ...
            feats.alphaPar, feats.alphaFro, feats.betaCen, ...
            feats.alphaVarPar, feats.alphaVarFro, feats.betaVarCen, ...
            feats.specSlope, feats.rmsMed, feats.timeKurtMed ...
            }]; %#ok<AGROW>
    end
end

Tw = cell2table(rows, 'VariableNames', ...
    {'subject','label','file','segmentName','t0','t1', ...
    'alphaPow','betaPow','thetaPow', ...
    'alphaFraction','betaFraction','betaAlphaRatio', ...
    'alphaPar','alphaFro','betaCen', ...
    'alphaVarPar','alphaVarFro','betaVarCen', ...
    'spectralSlope','rms','timeKurtosis'});
end

function feats = compute_features_roi_v2(X, labels, fs, bands, fFitRange, roiDefs)
% ROI band powers + fractions + variability (across channels within ROI).
% Uses Welch PSD for robustness.

labels = upper(string(labels));
X = double(X);

% --- compute PSD per channel ---
% pwelch over each channel (fast enough for 1s windows)
nwin = size(X,2);
nfft = 2^nextpow2(nwin);
w = hann(nwin);
P = zeros(size(X,1), floor(nfft/2)+1);
for ch = 1:size(X,1)
    [Pch, f] = pwelch(X(ch,:), w, 0, nfft, fs);
    P(ch,:) = Pch(:)';
end
f = f(:)';

% helpers
bandpow = @(idx,f1,f2) mean(P(idx, (f>=f1 & f<=f2)), 2, 'omitnan'); % mean across freq -> per channel
safeMedian = @(v) median(v, 'omitnan');

% indices by ROI
idxAll = ismember(labels, upper(roiDefs.ALL_EEG));
idxFro = ismember(labels, upper(roiDefs.Frontal));
idxPar = ismember(labels, upper(roiDefs.Parietal));
idxCen = ismember(labels, upper(roiDefs.Central));

% band power per-channel
th = bandpow(idxAll, bands.theta(1), bands.theta(2));
al = bandpow(idxAll, bands.alpha(1), bands.alpha(2));
be = bandpow(idxAll, bands.beta(1), bands.beta(2));

% total 4-30 band for fractions (per channel)
base = bandpow(idxAll, 4, 30) + eps;

% global robust medians
feats.thetaP = safeMedian(th);
feats.alphaP = safeMedian(al);
feats.betaP  = safeMedian(be);

feats.alphaFrac = safeMedian(al ./ base);
feats.betaFrac  = safeMedian(be ./ base);

feats.betaAlpha = log10(safeMedian(be ./ (al + eps)) + eps);

% ROI-specific alpha/beta
if any(idxPar)
    alPar = bandpow(idxPar, bands.alpha(1), bands.alpha(2));
    feats.alphaPar = safeMedian(alPar);
    feats.alphaVarPar = std(alPar, 0, 'omitnan'); % across channels
else
    feats.alphaPar = 0; feats.alphaVarPar = 0;
end

if any(idxFro)
    alFro = bandpow(idxFro, bands.alpha(1), bands.alpha(2));
    feats.alphaFro = safeMedian(alFro);
    feats.alphaVarFro = std(alFro, 0, 'omitnan');
else
    feats.alphaFro = 0; feats.alphaVarFro = 0;
end

if any(idxCen)
    beCen = bandpow(idxCen, bands.beta(1), bands.beta(2));
    feats.betaCen = safeMedian(beCen);
    feats.betaVarCen = std(beCen, 0, 'omitnan');
else
    feats.betaCen = 0; feats.betaVarCen = 0;
end

% spectral slope (median PSD across channels)
feats.specSlope = spectral_slope_from_psd(P(idxAll,:), f, fFitRange);

% time-domain robustness features (median across channels)
rmsCh = sqrt(mean(X.^2, 2));
feats.rmsMed = safeMedian(rmsCh);

kCh = kurtosis(X, 0, 2);
feats.timeKurtMed = safeMedian(kCh);

end

function s = spectral_slope_from_psd(P, f, fr)
idx = (f >= fr(1)) & (f <= fr(2));
ff = f(idx);
if numel(ff) < 8
    s = 0;
    return;
end
ps = median(P(:,idx), 1, 'omitnan');
c = polyfit(log10(ff(:)+eps), log10(ps(:)+eps), 1);
s = c(1);
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

function model = train_export_subject_model(Tw, subj, cfg, roiDefs, outFile)
% Train LASSO-logistic on all windows for the subject and export realtime-ready .mat

% Features used by model (order matters)
featCols = { ...
    'alphaPow','betaPow','thetaPow', ...
    'alphaFraction','betaFraction','betaAlphaRatio', ...
    'alphaPar','alphaFro','betaCen', ...
    'alphaVarPar','alphaVarFro','betaVarCen', ...
    'spectralSlope','rms','timeKurtosis' ...
    };

Xraw = Tw{:, featCols};
yraw = double(Tw.label == "improv");

good = all(isfinite(Xraw),2) & isfinite(yraw);
Xraw = Xraw(good,:);
yraw = yraw(good);

muFeat = mean(Xraw, 1, 'omitnan');
sdFeat = std(Xraw, 0, 1, 'omitnan') + eps;
Xz = (Xraw - muFeat) ./ sdFeat;

[B, Fit] = lassoglm(Xz, yraw, 'binomial', ...
    'Alpha', cfg.AlphaVal, ...
    'NumLambda', cfg.NUM_LAMBDA, ...
    'CV', cfg.CV_FOLDS, ...
    'Standardize', false);

idxLam = Fit.IndexMinDeviance;
beta0  = Fit.Intercept(idxLam);
beta   = B(:, idxLam);

betaVec = [beta0; beta];

% orient so higher p = improv
pTrain = glmval(betaVec, Xz, 'logit');
if mean(pTrain(yraw==1), 'omitnan') < mean(pTrain(yraw==0), 'omitnan')
    betaVec = -betaVec;
    pTrain  = 1 - pTrain;
end

model = struct();
model.subj         = string(subj);
model.betaVec      = betaVec;
model.muFeat       = muFeat;
model.sdFeat       = sdFeat;
model.featureOrder = string(featCols);
model.roiDefs      = roiDefs;
model.cfg          = cfg;

fprintf('[%s] Export sanity: mean p(improv) GT=improv=%.3f | GT=fixed=%.3f | N=%d\n', ...
    subj, mean(pTrain(yraw==1),'omitnan'), mean(pTrain(yraw==0),'omitnan'), numel(yraw));

save(outFile, '-struct', 'model');
fprintf('[%s] Saved model -> %s\n', subj, outFile);
end

function loso_subject_sanity(Tw, subj, cfg, model)
% quick LOSO segment-wise evaluation (no fancy baseline removal here)
featCols = cellstr(model.featureOrder);

segId = Tw.file;
uSeg = unique(segId);

pHat = nan(height(Tw),1);
yHat = nan(height(Tw),1);

for i = 1:numel(uSeg)
    testSeg = uSeg(i);
    isTe = (segId == testSeg);
    isTr = ~isTe;

    Tr = Tw(isTr,:);
    Te = Tw(isTe,:);

    Xtr0 = Tr{:, featCols};
    ytr  = double(Tr.label == "improv");
    gtr = all(isfinite(Xtr0),2) & isfinite(ytr);
    Xtr0 = Xtr0(gtr,:); ytr = ytr(gtr);

    Xte0 = Te{:, featCols};
    yte0 = double(Te.label == "improv");
    gte = all(isfinite(Xte0),2) & isfinite(yte0);
    Xte0 = Xte0(gte,:); yte = yte0(gte);

    if numel(ytr) < 100 || numel(unique(ytr)) < 2 || isempty(yte), continue; end

    mu = mean(Xtr0,1,'omitnan');
    sd = std(Xtr0,0,1,'omitnan') + eps;
    Xtr = (Xtr0 - mu)./sd;
    Xte = (Xte0 - mu)./sd;

    [B, Fit] = lassoglm(Xtr, ytr, 'binomial', ...
        'Alpha', cfg.AlphaVal, ...
        'NumLambda', cfg.NUM_LAMBDA, ...
        'CV', cfg.CV_FOLDS, ...
        'Standardize', false);

    idxLam = Fit.IndexMinDeviance;
    beta0  = Fit.Intercept(idxLam);
    beta   = B(:, idxLam);
    betaVec = [beta0; beta];

    pTr = glmval(betaVec, Xtr, 'logit');
    pTe = glmval(betaVec, Xte, 'logit');

    if mean(pTr(ytr==1),'omitnan') < mean(pTr(ytr==0),'omitnan')
        pTe = 1 - pTe;
    end

    teIdxAll = find(isTe);
    teIdx = teIdxAll(gte(:));
    pHat(teIdx) = pTe;
    yHat(teIdx) = yte;
end

good = isfinite(pHat) & isfinite(yHat);
if ~any(good)
    fprintf('[%s LOSO] No preds.\n', subj);
    return;
end

pred = pHat(good) >= 0.5;
acc = mean(pred == yHat(good));
tpr = mean(pred(yHat(good)==1)==1);
tnr = mean(pred(yHat(good)==0)==0);
bacc = 0.5*(tpr+tnr);

fprintf('[%s LOSO] ACC=%.2f%% | BACC=%.2f%% | mean p: fixed=%.3f improv=%.3f\n', ...
    subj, 100*acc, 100*bacc, mean(pHat(good & yHat==0),'omitnan'), mean(pHat(good & yHat==1),'omitnan'));

% segment-level
uFiles = unique(Tw.file);
corr = [];
for k = 1:numel(uFiles)
    f = uFiles(k);
    idx = (Tw.file==f) & isfinite(pHat);
    if ~any(idx), continue; end
    pm = mean(pHat(idx),'omitnan');
    gt = string(Tw.label(find(idx,1)));
    corr(end+1,1) = ( (pm>=0.5) == (gt=="improv") ); %#ok<AGROW>
end
fprintf('[%s LOSO] Segment ACC=%.2f%% (%d seg)\n', subj, 100*mean(corr), numel(corr));
end

function realtime_improv_stream(subj, rt)
% REALTIME: reads from BrainVision RDA, computes sliding-window features, outputs p(improv).
%
% Requires:
%   bv_rda_client('open', host, port, nCh, fs)
%   X = bv_rda_client(host, port, 'pull', pullDur)  -> returns [nCh x nSamp] double
%
% Output:
%   - TCP JSON message with time, p, label
%
% Usage:
%   rt = struct(...); realtime_improv_stream('Lauren', rt);

modelFile = sprintf('improv_model_%s.mat', subj);
M = load(modelFile);

fprintf('=== REALTIME IMPROV STREAM (%s) ===\n', subj);
fprintf('Loaded model: %s\n', modelFile);

% open TCP if needed
tcpObj = [];
if string(rt.outMode) == "tcp"
    tcpObj = tcpclient(char(rt.tcpIP), rt.tcpPort, 'Timeout', 1);
    fprintf('TCP connected -> %s:%d\n', rt.tcpIP, rt.tcpPort);
end

% open RDA
bv_rda_client('open', rt.host, rt.port, rt.nCh, rt.fs);
cleanupObj = onCleanup(@() cleanup_realtime(rt, tcpObj));

% buffer
buf = zeros(rt.nCh, 0);
t0 = tic;

winN = round(M.cfg.winSec * rt.fs);
hopN = round(M.cfg.hopSec * rt.fs);

% baseline state for causal drift removal in feature space
featN = numel(M.featureOrder);
featBaseline = zeros(1, featN);
baselineInit = false;

pSmooth = 0.5;

% channel labels for ROI (must match your cap order)
capLabels = upper(string(["Fp1","Fp2","F3","F4","C3","C4","P3","P4","O1","O2","F7","F8","T7","T8","P7","P8","Fz","Cz","Pz","FC1","FC2","CP1","CP2","FC5","FC6","CP5","CP6","TP9","TP10","Eog","Ekg1","Ekg2"]));

% drop non-EEG channels
keep = ~ismember(capLabels, upper(M.roiDefs.NON_EEG));
useLabels = capLabels(keep);

fprintf('Realtime: win=%ds (%d samp), hop=%ds (%d samp)\n', M.cfg.winSec, winN, M.cfg.hopSec, hopN);

nProcessed = 0;

while true
    Xpull = bv_rda_client(rt.host, rt.port, 'pull', rt.pullDur);
    if isempty(Xpull)
        pause(0.01);
        continue;
    end

    % keep only non-EOG/EKG channels (match training)
    Xpull = double(Xpull);
    Xpull = Xpull(keep,:);

    % append to buffer
    buf = [buf, Xpull]; %#ok<AGROW>

    % process as many hops as possible
    while size(buf,2) >= winN
        Xw = buf(:, 1:winN);

        % compute realtime features (same as training)
        feats = compute_features_roi_v2(Xw, useLabels, rt.fs, M.cfg.bands, M.cfg.fFitRange, M.roiDefs);

        % pack in the exact feature order used at training
        fvec = pack_features_in_order(feats, M.featureOrder);

        % zscore
        fz = (fvec - M.muFeat) ./ (M.sdFeat + eps);

        % causal baseline removal in feature space (optional but helps drift / segment bias)
        if ~baselineInit
            featBaseline = fz;
            baselineInit = true;
        else
            featBaseline = (1 - M.cfg.alphaBaseline) * featBaseline + M.cfg.alphaBaseline * fz;
        end
        fz_detrend = fz - featBaseline;

        % predict
        p = glmval(M.betaVec, fz_detrend, 'logit');

        % smooth probability for nicer visualization
        pSmooth = (1 - M.cfg.alphaSmoothP)*pSmooth + M.cfg.alphaSmoothP*p;

        % timestamp
        tSec = toc(t0);

        % output
        if string(rt.outMode) == "print"
            fprintf('[%7.2fs] p(improv)=%.3f (smooth=%.3f)\n', tSec, p, pSmooth);
        elseif string(rt.outMode) == "tcp"
            msg = sprintf('{"t":%.3f,"p":%.4f,"p_smooth":%.4f,"subj":"%s"}', tSec, p, pSmooth, subj);
            write(tcpObj, uint8([msg char(10)]));
        end

        nProcessed = nProcessed + 1;

        % slide buffer by hop
        if size(buf,2) > hopN
            buf = buf(:, hopN+1:end);
        else
            buf = zeros(size(buf,1),0);
        end
    end
end
end

function fvec = pack_features_in_order(feats, featureOrder)
% featureOrder is string array; feats has fields
fvec = zeros(1, numel(featureOrder));
for i = 1:numel(featureOrder)
    key = char(featureOrder(i));
    switch key
        case 'alphaPow',       fvec(i) = feats.alphaP;
        case 'betaPow',        fvec(i) = feats.betaP;
        case 'thetaPow',       fvec(i) = feats.thetaP;
        case 'alphaFraction',  fvec(i) = feats.alphaFrac;
        case 'betaFraction',   fvec(i) = feats.betaFrac;
        case 'betaAlphaRatio', fvec(i) = feats.betaAlpha;
        case 'alphaPar',       fvec(i) = feats.alphaPar;
        case 'alphaFro',       fvec(i) = feats.alphaFro;
        case 'betaCen',        fvec(i) = feats.betaCen;
        case 'alphaVarPar',    fvec(i) = feats.alphaVarPar;
        case 'alphaVarFro',    fvec(i) = feats.alphaVarFro;
        case 'betaVarCen',     fvec(i) = feats.betaVarCen;
        case 'spectralSlope',  fvec(i) = feats.specSlope;
        case 'rms',            fvec(i) = feats.rmsMed;
        case 'timeKurtosis',   fvec(i) = feats.timeKurtMed;
        otherwise
            error('Unknown feature key: %s', key);
    end
end
end

function cleanup_realtime(rt, tcpObj)
try
    bv_rda_client(rt.host, rt.port, 'close');
catch
end
try
    if ~isempty(tcpObj)
        clear tcpObj;
    end
catch
end
fprintf('\nRealtime stopped. Connections closed.\n');
end
