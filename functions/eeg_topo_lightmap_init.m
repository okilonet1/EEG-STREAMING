function vis = eeg_topo_lightmap_init(chanLabels, x2d, y2d, band)
% EEG_TOPO_LIGHTMAP_INIT  Create 2D head with per-channel markers.

Nch = numel(chanLabels);

vis.fig = figure('Color','w','MenuBar','none','ToolBar','none',...
                 'Name','EEG Channel Lightmap');
hold on; axis equal off;

rHead = 1.0;
tHead = linspace(0,2*pi,300);
fill(rHead*cos(tHead), rHead*sin(tHead), [1 1 1]*0.97, ...
    'EdgeColor','k', 'LineWidth',2);

% Nose
nose_base   = 0.15;
nose_height = 0.12;
noseX = [-nose_base/2, 0, nose_base/2];
noseY = [rHead, rHead+nose_height, rHead];
patch(noseX, noseY, [0.3 0.3 0.3], 'EdgeColor','k', 'LineWidth',1.5);

vis.hTopo = gobjects(1,Nch);
for i = 1:Nch
    vis.hTopo(i) = rectangle('Position',[x2d(i)-0.05, y2d(i)-0.05, 0.1, 0.1], ...
        'Curvature',[1 1],'FaceColor',[1 1 1],'EdgeColor','k');
    text(x2d(i), y2d(i)-0.07, chanLabels{i}, 'Color','k', 'FontSize',7, ...
        'HorizontalAlignment','center');
end

title(sprintf('Real-Time %s Band Power per Channel (Topo)', upper(band)), ...
    'Color','k','FontSize',13,'Units','normalized','Position',[0.5,1.05,0]);
end
