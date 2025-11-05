% EEGLAB history file generated on the 29-Oct-2025
% ------------------------------------------------
EEG = pop_loadset('filename','20ms.set','filepath','/Users/kachi/Documents/MATLAB/EEG_LEARNING/DR NORDIN EEG/');
[ALLEEG, EEG, CURRENTSET] = eeg_store( ALLEEG, EEG, 0 );
figure; pop_spectopo(EEG, 1, [0  998], 'EEG' , 'freq', [6 10 20 22], 'freqrange',[2 25],'electrodes','off');
figure; topoplot([],EEG.chanlocs, 'style', 'blank',  'electrodes', 'numpoint', 'chaninfo', EEG.chaninfo);
figure; topoplot([],EEG.chanlocs, 'style', 'blank',  'electrodes', 'labelpoint', 'chaninfo', EEG.chaninfo);
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, 2,'retrieve',1,'study',0); 
figure; topoplot([],EEG.chanlocs, 'style', 'blank',  'electrodes', 'labelpoint', 'chaninfo', EEG.chaninfo);
eeglab('redraw');
EEG = pop_loadset('filename','20ms.set','filepath','/Users/kachi/Documents/MATLAB/EEG_LEARNING/DR NORDIN EEG/');
[ALLEEG, EEG, CURRENTSET] = eeg_store( ALLEEG, EEG, 0 );
figure; topoplot([],EEG.chanlocs, 'style', 'blank',  'electrodes', 'labelpoint', 'chaninfo', EEG.chaninfo);
eeglab('redraw');
figure; topoplot([],EEG.chanlocs, 'style', 'blank',  'electrodes', 'labelpoint', 'chaninfo', EEG.chaninfo);
eeglab redraw;
