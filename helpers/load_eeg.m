clear; close all; clc;
addpath('functions');
addpath("eeglab2025.1.0")

[ALLEEG, EEG, CURRENTSET] = eeglab;

dataDir = eeg_get_data_path('FREE REIN REHEARSAL DATA');

vhdr    = '2026_1_6_1_10_J.vhdr';

EEG = pop_loadbv(dataDir, vhdr);
EEG = eeg_checkset(EEG);

% ---- Basic sanity checks ----
fprintf('Loaded: %d chans, %.1f Hz, %.1f sec\n', EEG.nbchan, EEG.srate, EEG.xmax);
if EEG.srate ~= 500
    warning('Sampling rate is %.1f (expected 500).', EEG.srate);
end

% ---- 3) (Optional but recommended) add channel locations ----
% If your channels already have locations, this does nothing harmful.
EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
EEG = eeg_checkset(EEG);

% ---- 4) Visual inspection ----
pop_eegplot(EEG, 1, 1, 1);

% ---- 5) Filter for ICA ----
% Common ICA-friendly band: 1–40 Hz
EEG = pop_eegfiltnew(EEG, 1, 40);

% Optional: notch if you clearly see 60 Hz line noise
EEG = pop_eegfiltnew(EEG, 58, 62, [], 1);

% ---- 6) Re-reference (common default: average) ----
EEG = pop_reref(EEG, []);

% ---- 7) (Optional) Remove non-EEG channels before ICA ----
% If your file includes AUX/Trigger/EOG channels, ICA gets worse.
% Keep only EEG scalp channels if needed:
EEG = pop_select(EEG, 'channel', 1:32);   % <-- use your EEG channel indices

% ---- 8) (Optional but very helpful) Remove gross bad segments ----
% You can do this manually with eegplot:
% In the plot window: "Reject" -> "Reject data (continuous)" and mark junk.
% Then:
EEG = eeg_rejsuperpose(EEG, 1, 1, 1, 1, 1, 1, 1, 1);
EEG = pop_rejcont(EEG);

% ---- 9) Run ICA ----
EEG = pop_runica(EEG, 'icatype', 'runica', 'extended', 1);
EEG = eeg_checkset(EEG);

% ---- 10) Inspect components & remove artifacts ----
% View component properties (maps + spectra + time series)
pop_topoplot(EEG, 0, 1:32 , 'IC maps', 0 , 'electrodes','on');
pop_viewprops(EEG, 0, 1:min(32,size(EEG.icaweights,1)));

% After deciding which ICs are artifacts (eye/muscle/line noise):
% compsToRemove = [1 3 7];  % <-- change
% EEG = pop_subcomp(EEG, compsToRemove, 0);

% ---- 11) Save dataset ----
EEG = pop_saveset(EEG, 'filename', 'clean_2026_1_6_1_10_J.set', 'filepath', dataDir);