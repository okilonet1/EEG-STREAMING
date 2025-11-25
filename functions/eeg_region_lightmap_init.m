function vis = eeg_region_lightmap_init(regionNames, band)
% EEG_REGION_LIGHTMAP_INIT  Create 16-region bubble figure.

nR = numel(regionNames);

vis.fig = figure('Color','k','Name','EEG Brain Lightmap',...
                 'MenuBar','none','ToolBar','none');
axis equal off; hold on;
title(sprintf('Real-Time %s Band Power (Regions)', upper(band)),...
    'Color','w','FontSize',14);

thetaReg = linspace(pi/2+0.3,-pi/2-0.3,8);
yposReg  = [0.9,0.4,-0.2,-0.8];
[XposReg,YposReg] = meshgrid(thetaReg,yposReg);
XposReg = XposReg(:); YposReg = YposReg(:);
XposReg = XposReg(1:nR); YposReg = YposReg(1:nR);

margin = 0.4;
xlim([min(XposReg)-margin, max(XposReg)+margin]);
ylim([min(YposReg)-margin, max(YposReg)+margin]);
set(gca,'Position',[0 0 1 1]);

vis.hReg = gobjects(1,nR);
for i = 1:nR
    vis.hReg(i) = rectangle('Position',[XposReg(i)-0.2,YposReg(i)-0.2,0.4,0.4], ...
        'Curvature',[1 1],'EdgeColor','none','FaceColor',[0 0 0]);
    text(XposReg(i),YposReg(i),char(regionNames(i)), ...
        'Color','w','HorizontalAlignment','center','FontSize',8);
end
end
