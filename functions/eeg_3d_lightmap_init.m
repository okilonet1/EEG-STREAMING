function vis = eeg_3d_lightmap_init(chanLabels, x3d, y3d, z3d, band)
% EEG_3D_LIGHTMAP_INIT  Create 3D head with per-channel markers.

Nch = numel(chanLabels);

vis.fig = figure('Color','w','MenuBar','none','ToolBar','none', ...
                 'Name','EEG Brain 3D Lightmap');
vis.ax = axes('Color','w','DataAspectRatio',[1 1 1]);
hold(vis.ax,'on');
axis(vis.ax,'off');
view(vis.ax, 40, 25);
rotate3d(vis.ax,'on');

% Head sphere
[hsX, hsY, hsZ] = sphere(60);
surf(vis.ax, 1.0*hsX, 1.0*hsY, 1.0*hsZ, ...
    'FaceColor',[0.95 0.95 0.95], 'EdgeColor','none', 'FaceAlpha',0.3);

% Nose
nose_base   = 0.15;
nose_height = 0.12;
noseY = 1.02;
noseX = [-nose_base/2, 0, nose_base/2];
noseZ = [0.05, 0.1, 0.05];
patch('XData',noseX, ...
      'YData',[noseY, noseY+nose_height, noseY], ...
      'ZData',noseZ, ...
      'FaceColor',[0.3 0.3 0.3], 'EdgeColor','k', 'LineWidth',1.5);

vis.h3D = gobjects(1,Nch);
for i = 1:Nch
    vis.h3D(i) = plot3(vis.ax, x3d(i), y3d(i), z3d(i), 'o', ...
        'MarkerSize',10, 'MarkerEdgeColor','k', 'MarkerFaceColor',[1 1 1]);
    text(x3d(i), y3d(i), z3d(i)+0.05, chanLabels{i}, 'FontSize',7, ...
        'HorizontalAlignment','center', 'Color','k');
end

title(vis.ax, sprintf('Real-Time %s Band Power (3D)', upper(band)), ...
    'Color','k','FontSize',13,'Units','normalized','Position',[0.5,1.05,0]);

light(vis.ax,'Position',[1 1 1],'Style','infinite');
material(vis.ax,'shiny');
end
