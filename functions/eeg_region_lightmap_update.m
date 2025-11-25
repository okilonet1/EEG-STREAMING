function eeg_region_lightmap_update(vis, rgbRegion)
% EEG_REGION_LIGHTMAP_UPDATE  Update bubble colors from RGB array.

for i = 1:numel(vis.hReg)
    vis.hReg(i).FaceColor = rgbRegion(i,:);
end
end
