function eeg_3d_lightmap_update(vis, rgbCh)
% EEG_3D_LIGHTMAP_UPDATE  Update 3D marker colors.

Nuse = min(numel(vis.h3D), size(rgbCh,1));
for i = 1:Nuse
    set(vis.h3D(i),'MarkerFaceColor', rgbCh(i,:));
end
end
