function eeg_brain_lightmap(band)
% EEG_BRAIN_LIGHTMAP  Live 16-region band-power visualizer (optimized)
% Usage: eeg_brain_lightmap('alpha')

if nargin < 1, band = 'alpha'; end
fprintf('[EEG-Lightmap] Starting real-time visualization (%s band)\n', upper(band));

% --- Connect to BrainVision ---
try, bv_rda_client('close'); end
S = bv_rda_client('open','127.0.0.1',51244,32,500);

% --- Load region map ---
fid = fopen('regions.json'); raw = fread(fid,inf); fclose(fid);
regionsStruct = jsondecode(char(raw'));
fields = fieldnames(regionsStruct);
nR = numel(fields);
regions = cell(nR,2);
for i = 1:nR
    regions{i,1} = fields{i};
    regions{i,2} = regionsStruct.(fields{i});
end

% --- Layout for circles ---
theta = linspace(pi/2+0.3,-pi/2-0.3,8);
ypos  = [0.9,0.4,-0.2,-0.8];
[Xpos,Ypos] = meshgrid(theta,ypos);
Xpos = Xpos(:); Ypos = Ypos(:);
Xpos = Xpos(1:nR); Ypos = Ypos(1:nR);

% --- Figure setup ---
close(findobj('type','figure','name','EEG Brain Lightmap'))
figure('Color','k','Name','EEG Brain Lightmap','MenuBar','none','ToolBar','none');
axis equal off; hold on;
title(sprintf('Real-Time %s Band Power', upper(band)),'Color','w','FontSize',14);
margin = 0.4;
xlim([min(Xpos)-margin, max(Xpos)+margin]);
ylim([min(Ypos)-margin, max(Ypos)+margin]);
set(gca,'Position',[0 0 1 1]);

% --- Draw bubbles ---
h = gobjects(1,nR);
for i = 1:nR
    h(i) = rectangle('Position',[Xpos(i)-0.2,Ypos(i)-0.2,0.4,0.4], ...
        'Curvature',[1 1],'EdgeColor','none','FaceColor',[0 0 0]);
    text(Xpos(i),Ypos(i),num2str(i),'Color','w','HorizontalAlignment','center','FontSize',8);
end

% --- Initialize EEG struct ---
EEG = struct();
EEG.srate = 500;
EEG.data  = zeros(32,500);
chanLabels = { ...
    'Fp1','Fz','F3','F7','FT9','FC5','FC1','C3','T7','TP9','CP5','CP1',...
    'Pz','P3','P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz',...
    'C4','T8','FT10','FC6','FC2','F4','F8','Fp2'};
for i = 1:numel(chanLabels)
    EEG.chanlocs(i).labels = chanLabels{i};
end

fprintf('[Lightmap] Streaming... press Ctrl+C to stop.\n');

% --- Persistent smoothing to stabilize flicker ---
persistent prevVals
alpha = 0.3;

while ishandle(h(1))
    % Pull 250 ms of data
    X = bv_rda_client('pull', 0.25);
    if isempty(X) || all(X(:)==0), pause(0.05); continue; end
    EEG.data = X;

    % Compute regional bandpower
    [regionPower,regionColors] = eeg_region_bandpower(EEG);
    vals = regionPower.(band);
    vals(isnan(vals)) = 0;
    vals = vals / max(vals + eps);

    % Exponential smoothing
    if isempty(prevVals), prevVals = vals;
    else, vals = alpha*vals + (1-alpha)*prevVals; prevVals = vals;
    end

    % Update color bubbles
    for i = 1:nR
        intensity = vals(i);
        hue = 0.66 - 0.66*intensity;
        rgb = hsv2rgb([hue 1 intensity]);
        h(i).FaceColor = rgb;
    end
    drawnow limitrate nocallbacks;

    % --- OPTIONAL: prepare serial-friendly RGB array (for Arduino) ---
    rgbArray = zeros(nR,3);
    for i = 1:nR
        hue = 0.66 - 0.66*vals(i);
        rgbArray(i,:) = hsv2rgb([hue 1 vals(i)]);
    end

    % fprintf(jsonencode(round(255*rgbArray)),'\n',"serialport");  % replace "serialport" with actual port object

end
end
