# import scipy.io as sio
# EEG = sio.loadmat('DR NORDIN EEG/05ms.set')

# print(EEG)


import matplotlib.pyplot as plt
from oct2py import octave as eeglab
path2eeglab = 'eeglab2025.1.0'

eeglab.addpath(path2eeglab + '/functions/guifunc')
eeglab.addpath(path2eeglab + '/functions/popfunc')
eeglab.addpath(path2eeglab + '/functions/adminfunc')
eeglab.addpath(path2eeglab + '/functions/sigprocfunc')
eeglab.addpath(path2eeglab + '/functions/miscfunc')
eeglab.addpath(path2eeglab + '/plugins/dipfit')
EEG = eeglab.pop_loadset(path2eeglab + 'DR NORDIN EEG/05ms.set')

# plot first trial of channel 1
plt.plot(EEG.data[0][0])
plt.show()
