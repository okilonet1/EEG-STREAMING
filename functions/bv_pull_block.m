function Y = bv_pull_block(winSec)
% Returns [Nsamples x Nchannels], centered, normalized, stacked
X = bv_rda_client('pull', winSec);   % [Nc x Ns] in µV
if isempty(X), Y = zeros(1,1); return; end

Y = double(X)';                      % [Ns x Nc]
[~, Nc] = size(Y);

% de-mean and robust normalize
Y = Y - mean(Y,1,'omitnan');
s = prctile(abs(Y(:)),99); if ~isfinite(s) || s==0, s = max(1,std(Y(:))); end
Y = Y * (50/s);

% vertical offsets so 64 traces don't overlap
step = 8; offsets = ((0:Nc-1)*step) - ((Nc-1)*step/2);
Y = Y + offsets;

Y(~isfinite(Y)) = 0;
end


