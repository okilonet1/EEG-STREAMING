function eeg_brain_lightmap(band)
% EEG_BRAIN_LIGHTMAP  Live 16-region band-power visualizer.
% Usage: eeg_brain_lightmap('alpha')   % or 'beta','theta','gamma','delta'

if nargin < 1, band = 'alpha'; end

% --- Initialize BrainVision client (adjust if already open) ---
try, bv_rda_client('close'); end
S = bv_rda_client('open','127.0.0.1',51244,32,500);

% --- Region layout (same as before) ---
regions = {
    'Left Frontal',     {'Fp1','F3','F7'}
    'Right Frontal',    {'Fp2','F4','F8'}
    'Midline Frontal',  {'Fz','AFz'}
    'Left Central',     {'FC3','C3','CP3'}
    'Right Central',    {'FC4','C4','CP4'}
    'Midline Central',  {'Cz'}
    'Left Parietal',    {'P3','P7'}
    'Right Parietal',   {'P4','P8'}
    'Midline Parietal', {'Pz'}
    'Left Temporal',    {'T7','FT7'}
    'Right Temporal',   {'T8','FT8'}
    'Left Occipital',   {'O1','PO3'}
    'Right Occipital',  {'O2','PO4'}
    'Midline Occipital',{'Oz'}
    'Left FC',          {'FC5','F5'}
    'Right FC',         {'FC6','F6'}
    };

nR = size(regions,1);

% --- Positions for the 16 circles (rough scalp map layout) ---
theta = linspace(pi/2+0.3, -pi/2-0.3, 8);    % left→right
ypos  = [0.9, 0.4, -0.2, -0.8];              % front→back layers
[Xpos,Ypos] = meshgrid(theta,ypos);
Xpos = Xpos(:); Ypos = Ypos(:);
Xpos = Xpos(1:nR); Ypos = Ypos(1:nR);

% --- Create figure ---
close(findobj('type','figure','name','EEG Brain Lightmap'))
figure('MenuBar','none','ToolBar','none');
set(gcf,'Name','EEG Brain Lightmap','NumberTitle','off');
axis equal off
hold on
title(sprintf('Real-Time %s Band Power',upper(band)),'Color','w','FontSize',14);
h = gobjects(1,nR);
for i = 1:nR
    h(i) = rectangle('Position',[Xpos(i)-0.2,Ypos(i)-0.2,0.4,0.4], ...
        'Curvature',[1 1],'EdgeColor','none','FaceColor',[0 0 0]);
    text(Xpos(i),Ypos(i),num2str(i),'Color','w','HorizontalAlignment','center','FontSize',8);
end
margin = 0.4;
xlim([min(Xpos)-margin, max(Xpos)+margin]);
ylim([min(Ypos)-margin, max(Ypos)+margin]);
axis equal off;
set(gca,'Color','k','Position',[0 0 1 1]);
title(sprintf('Real-Time %s Band Power', upper(band)), ...
    'Color','w','FontSize',14,'Units','normalized','Position',[0.5,1.05,0]);


% --- Initialize dummy EEG structure for analysis ---
EEG = struct();
EEG.srate = 500;
EEG.data  = zeros(32,500);

% Assign typical 32-channel labels (must match your montage)
EEG.chanlocs = struct('labels', {}, 'X', {}, 'Y', {}, 'Z', {});

chanLabels = { ...
    'Fp1','Fz','F3','F7','FT9','FC5','FC1','C3','T7','TP9','CP5','CP1',...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz',...
    'C4','T8','FT10','FC6','FC2','F4','F8','Fp2'};

for i = 1:numel(chanLabels)
    EEG.chanlocs(i).labels = chanLabels{i};
end

fprintf('[Lightmap] Streaming... press Ctrl+C to stop.\n');
while ishandle(h(1))
    % ---- Pull 1-second window ----
    X = bv_rda_client('pull',0.25);
    if isempty(X) || all(X(:)==0), continue; end
    EEG.data = X;

    % ---- Compute band-power per region ----
    [regionPower,~] = eeg_region_bandpower(EEG);
    vals = regionPower.(band);
    vals(isnan(vals)) = 0;
    vals = vals / max(vals + eps);  % normalize

    % ---- Update colours ----
    for i = 1:nR
        intensity = vals(i);
        hue = 0.66 - 0.66*intensity;           % blue→red hue shift
        rgb = hsv2rgb([hue 1 intensity]);      % vivid colour
        h(i).FaceColor = rgb;
    end
    drawnow limitrate
end
end
