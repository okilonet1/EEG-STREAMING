function eeg_topo_lightmap_update(vis, rgbCh)
% EEG_TOPO_LIGHTMAP_UPDATE  Update 2D head marker colors.

Nuse = min(numel(vis.hTopo), size(rgbCh,1));
for i = 1:Nuse
    vis.hTopo(i).FaceColor = rgbCh(i,:);
end
end
