function rgb = eeg_vals_to_hsv(vals)
% EEG_VALS_TO_HSV  Map normalized [0,1] values to RGB using a blue→red hue.
%
% vals: 1 x N or N x 1 vector, assumed already in [0,1]
% rgb:  N x 3 double, each row [R G B] in [0,1]

vals = vals(:); % column
N = numel(vals);

% Clamp just in case
vals(vals < 0) = 0;
vals(vals > 1) = 1;

% Hue: 0.66 (blue) → 0 (red) as intensity increases
hue = 0.66 - 0.66*vals;
sat = ones(N,1);
val = vals;  % brightness = intensity

rgb = hsv2rgb([hue sat val]);
end
