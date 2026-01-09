function bad = suggest_bad_channels(EEG, varargin)
% bad = suggest_bad_channels(EEG, 'lineHz',60,'rmsZ',3,'corrMin',0.4)
%
% Returns indices of channels likely bad, using robust outlier rules.

p = inputParser;
p.addParameter('lineHz', 60);
p.addParameter('rmsZ', 3.5);        % robust z threshold for RMS outliers
p.addParameter('flatVarFrac', 0.02);% variance < 2% of median variance => flat-ish
p.addParameter('corrMin', 0.35);    % correlation with median signal minimum
p.addParameter('maxHz', 45);        % for PSD computations
p.parse(varargin{:});
opt = p.Results;

X  = double(EEG.data);
fs = EEG.srate;
[nCh, nS] = size(X);

% Demean
X = X - mean(X,2);

% --- 1) RMS outliers ---
rmsCh = sqrt(mean(X.^2,2));
rmsMed = median(rmsCh);
rmsMad = median(abs(rmsCh - rmsMed)) + eps;
rmsRobZ = (rmsCh - rmsMed) / (1.4826*rmsMad);

bad_rms = find(rmsRobZ > opt.rmsZ);

% --- 2) Flatline-ish ---
varCh = var(X,0,2);
bad_flat = find(varCh < opt.flatVarFrac * median(varCh));

% --- 3) Correlation with median channel ---
medSig = median(X,1);
c = zeros(nCh,1);
for k=1:nCh
    cc = corrcoef(X(k,:)', medSig');
    c(k) = cc(1,2);
end
if opt.corrMin <= -0.5
    bad_corr = [];
else
    % compute correlation rule...
    bad_corr = find(c < opt.corrMin);
end



% --- 4) Line noise ratio (near lineHz) ---
% Simple PSD via FFT (not physical units; OK for ratios)
N = size(X,2);
nfft = 2^nextpow2(N);
w = hann(N)';
Y = fft(X.*w, nfft, 2);
P = abs(Y(:,1:floor(nfft/2)+1)).^2;
f = (0:floor(nfft/2))*(fs/nfft);

lineBand = [opt.lineHz-1 opt.lineHz+1];
refBand  = [opt.lineHz-6 opt.lineHz-2];  % nearby lower band as reference

idxLine = (f>=lineBand(1) & f<=lineBand(2));
idxRef  = (f>=refBand(1)  & f<=refBand(2));
if any(idxLine) && any(idxRef)
    ln = mean(P(:,idxLine),2);
    rf = mean(P(:,idxRef),2) + eps;
    lnRatio = ln ./ rf;

    % robust outliers in lnRatio
    m = median(lnRatio);
    madv = median(abs(lnRatio - m)) + eps;
    z = (lnRatio - m) / (1.4826*madv);
    bad_line = find(z > 3.5);
else
    bad_line = [];
end

bad = unique([bad_rms; bad_flat; bad_corr; bad_line]);

% Print a quick report
fprintf('Bad channel suggestions:\n');
fprintf('  RMS outliers:      %s\n', mat2str(bad_rms'));
fprintf('  Flatline-ish:      %s\n', mat2str(bad_flat'));
fprintf('  Low correlation:   %s\n', mat2str(bad_corr'));
fprintf('  Line-noise outlier:%s\n', mat2str(bad_line'));
fprintf('  => Combined bad:   %s\n', mat2str(bad'));
end
