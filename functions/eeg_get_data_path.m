function fullPath = eeg_get_data_path(relPath)
% EEG_GET_DATA_PATH  Resolve a path inside the /data folder relative to this repo.
%
% Usage:
%   fullPath = eeg_get_data_path('regions.json');
%   fullPath = eeg_get_data_path('channel_locations.sfp');

thisDir = fileparts(mfilename('fullpath'));  % .../functions
rootDir = fileparts(thisDir);                % .../EEG STREAMING
fullPath = fullfile(rootDir, 'data', relPath);
end
