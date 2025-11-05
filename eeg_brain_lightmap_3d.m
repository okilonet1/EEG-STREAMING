function eeg_brain_lightmap_3d(band)
% EEG_BRAIN_LIGHTMAP_3D  Live per-channel bandpower visualizer in 3D.
% Usage:
%   eeg_brain_lightmap_3d('alpha')

if nargin < 1, band = 'alpha'; end

try, bv_rda_client('close'); end
S = bv_rda_client('open','127.0.0.1',51244,32,500);

% --- Load channel coordinates (.sfp) ---
fid = fopen('channel_locations.sfp','r');
C = textscan(fid, '%s %f %f %f');
fclose(fid);
labels = C{1};
coords = [C{2}, C{3}, C{4}];

% Normalize radius to fit unit sphere
coords = coords ./ max(vecnorm(coords,2,2));

x = coords(:,1);
y = coords(:,2);
z = coords(:,3);

fid = fopen('regions.json');
raw = fread(fid, inf);
str = char(raw');
fclose(fid);

regionsStruct = jsondecode(str);

fields = fieldnames(regionsStruct);
regions = cell(length(fields), 2);

for i = 1:length(fields)
    regions{i,1} = fields{i};
    regions{i,2} = regionsStruct.(fields{i});
end



% --- EEG structure ---
EEG.srate = 500;
EEG.data  = zeros(numel(labels), 500);
EEG.chanlocs = struct('labels', labels, ...
    'X', num2cell(x), 'Y', num2cell(y), 'Z', num2cell(z));

fprintf('[3DLightmap] Streaming... press Ctrl+C to stop.\n');

% --- Create bright 3D figure ---
figure('Color','w','MenuBar','none','ToolBar','none','Name','EEG Brain 3D Lightmap');
ax = axes('Color','w','DataAspectRatio',[1 1 1]);
hold(ax,'on');
axis(ax,'off');
view(40,25);
rotate3d on;

% --- Draw head as semi-transparent sphere ---
[hsX, hsY, hsZ] = sphere(60);
surf(ax, 1.0*hsX, 1.0*hsY, 1.0*hsZ, ...
    'FaceColor',[0.95 0.95 0.95], 'EdgeColor','none', 'FaceAlpha',0.3);

% --- Draw upward triangle nose (front at +Y) ---
nose_base = 0.15;
nose_height = 0.12;
noseY = 1.02;
noseX = [-nose_base/2, 0, nose_base/2];
noseZ = [0.05, 0.1, 0.05];
patch('XData',noseX, 'YData',[noseY, noseY+nose_height, noseY], ...
    'ZData',noseZ, 'FaceColor',[0.3 0.3 0.3], 'EdgeColor','k', 'LineWidth',1.5);

% --- Plot channels as spheres with labels ---
Nch = numel(labels);
h = gobjects(1,Nch);
for i = 1:Nch
    h(i) = plot3(ax, x(i), y(i), z(i), 'o', ...
        'MarkerSize',10, 'MarkerEdgeColor','k', 'MarkerFaceColor',[1 1 1]);
    text(x(i), y(i), z(i)+0.05, labels{i}, 'FontSize',7, ...
        'HorizontalAlignment','center', 'Color','k');
end
title(ax, sprintf('Real-Time %s Band Power (3D)', upper(band)), ...
    'Color','k','FontSize',13,'Units','normalized','Position',[0.5,1.05,0]);

light('Position',[1 1 1],'Style','infinite');
material shiny;

% --- Define band ranges ---
bandRanges = struct('delta',[0.5 4],'theta',[4 8],'alpha',[8 13],'beta',[13 30],'gamma',[30 45]);
freqRange = bandRanges.(band);
fs = EEG.srate;

% --- Live update loop ---
while ishandle(h(1))
    X = bv_rda_client('pull', 1.0);
    if isempty(X) || all(X(:)==0), continue; end
    EEG.data = X;

    % Compute bandpower for each channel
    vals = zeros(1,Nch);
    for c = 1:Nch
        vals(c) = bandpower(EEG.data(c,:), fs, freqRange);
    end

    % Normalize to [0,1]
    vals = vals - min(vals);
    vals = vals ./ max(vals + eps);

    % Update colors (blue → red hue)
    for i = 1:Nch
        intensity = vals(i);
        hue = 0.66 - 0.66*intensity;
        rgb = hsv2rgb([hue 1 intensity]);
        set(h(i),'MarkerFaceColor',rgb);
    end

    drawnow limitrate
end
end
