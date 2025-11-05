function eeg_brain_lightmap_topo(band)
% EEG_BRAIN_LIGHTMAP_TOPO  Live per-channel bandpower visualizer (2D flattened head)
% Usage: eeg_brain_lightmap_topo('alpha')

if nargin < 1, band = 'alpha'; end

try, bv_rda_client('close'); end
S = bv_rda_client('open','169.254.230.22',51244,32,500);

% --- Load channel coordinates (.sfp file) ---
fid = fopen('channel_locations.sfp','r');
C = textscan(fid, '%s %f %f %f');
fclose(fid);
labels = C{1};
coords = [C{2}, C{3}, C{4}];

x = coords(:,1); % Extract the x-coordinates for 2D projection
y = coords(:,2); % Extract the y-coordinates for 2D projection


% --- 2D flattening projection (azimuthal-like) ---
theta  = atan2(coords(:,2), coords(:,1));   % azimuth
radius = 0.5 + 0.5*coords(:,3);             % compress height into radius
x = radius .* cos(theta);
y = radius .* sin(theta);

% --- Normalize so the head fits within a unit circle ---
x = x / max(abs(x));
y = y / max(abs(y));

% --- EEG structure ---
EEG.srate = 500;
EEG.data  = zeros(numel(labels), 500);
EEG.chanlocs = struct('labels', labels, ...
    'X', num2cell(x), 'Y', num2cell(y), 'Z', num2cell(coords(:,3)));

fprintf('[ChannelLightmap] Streaming... press Ctrl+C to stop.\n');

% --- Create bright circular head figure ---
close(findobj('type','figure','name','EEG Channel Lightmap'))
figure('Color','w','MenuBar','none','ToolBar','none','Name','EEG Channel Lightmap');
hold on; axis equal off;
r = 1.0;
t = linspace(0,2*pi,300);
fill(r*cos(t), r*sin(t), [1 1 1]*0.97, 'EdgeColor','k', 'LineWidth',2);

% --- Nose (upward triangle) ---
nose_base = 0.15;
nose_height = 0.12;
noseX = [-nose_base/2, 0, nose_base/2];
noseY = [r, r+nose_height, r];
patch(noseX, noseY, [0.3 0.3 0.3], 'EdgeColor','k', 'LineWidth',1.5);

% --- Plot channel markers and labels ---
Nch = numel(labels);
h = gobjects(1,Nch);
for i = 1:Nch
    h(i) = rectangle('Position',[x(i)-0.05, y(i)-0.05, 0.1, 0.1], ...
        'Curvature',[1 1],'FaceColor',[1 1 1],'EdgeColor','k');
    text(x(i), y(i)-0.07, labels{i}, 'Color','k', 'FontSize',7, ...
        'HorizontalAlignment','center');
end

title(sprintf('Real-Time %s Band Power per Channel', upper(band)), ...
    'Color','k','FontSize',13,'Units','normalized','Position',[0.5,1.05,0]);

% --- Live update loop ---
while ishandle(h(1))
    X = bv_rda_client('pull', 1.0);
    if isempty(X) || all(X(:)==0), continue; end
    EEG.data = X;

    % Compute bandpower for each channel
    bandRanges = struct('delta',[0.5 4],'theta',[4 8],'alpha',[8 13],'beta',[13 30],'gamma',[30 45]);
    freqRange = bandRanges.(band);
    fs = EEG.srate;

    vals = zeros(1,Nch);
    for c = 1:Nch
        vals(c) = bandpower(EEG.data(c,:), fs, freqRange);
    end

    % Normalize to [0,1]
    vals = vals - min(vals);
    vals = vals ./ max(vals + eps);

    % Update color (blue→red)
    for i = 1:Nch
        intensity = vals(i);
        hue = 0.66 - 0.66*intensity;
        rgb = hsv2rgb([hue 1 intensity]);
        h(i).FaceColor = rgb;
    end

    drawnow limitrate
end
end
