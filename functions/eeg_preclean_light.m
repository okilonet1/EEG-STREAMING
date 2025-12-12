function dataOut = eeg_preclean_light(dataIn, fs)
% EEG_PRECLEAN_LIGHT
% Minimal preprocessing pipeline for EEG:
%   - Common Average Reference (CAR)
%   - High-pass 0.5 Hz
%   - Notch 59–61 Hz (60 Hz line)
%   - Low-pass 45 Hz
%
% Usage:
%   dataOut = eeg_preclean_light(dataIn, fs)
%
%   % To reset persistent filters (e.g., when changing sampling rate context)
%   eeg_preclean_light('reset');
%
% Inputs:
%   dataIn : [nChannels x nSamples] double/single
%   fs     : sampling rate (Hz)
%
% Output:
%   dataOut: [nChannels x nSamples] double

persistent hp notch lp lastFs

% -------- Reset persistent filters ----------
if nargin == 1 && ischar(dataIn) && strcmpi(dataIn,'reset')
    clear hp notch lp lastFs
    dataOut = [];
    return
end

if nargin < 2
    error('eeg_preclean_light requires data and sampling rate, or ''reset''.');
end

% Ensure double precision
data = double(dataIn);

% -------- Common Average Reference (CAR) ----------
data = data - mean(data,1);

% -------- Design / reuse filters ----------
if isempty(hp) || isempty(lastFs) || lastFs ~= fs
    hp = designfilt('highpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',0.5,'SampleRate',fs);
    notch = designfilt('bandstopiir','FilterOrder',4, ...
        'HalfPowerFrequency1',59,'HalfPowerFrequency2',61,'SampleRate',fs);
    lp = designfilt('lowpassiir','FilterOrder',4, ...
        'HalfPowerFrequency',45,'SampleRate',fs);
    lastFs = fs;
end

% filtfilt expects [N x T]; we have [ch x T], so transpose
data = filtfilt(hp,    data')';
data = filtfilt(notch, data')';
data = filtfilt(lp,    data')';

dataOut = data;
end
