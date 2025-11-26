function send_to_mcu(ioObj, rgbArray)
    if ~isnumeric(rgbArray) || size(rgbArray,2) ~= 3
        error('rgbArray must be an N×3 numeric array of RGB values in [0,1].');
    end

    rgbArray(rgbArray < 0) = 0;
    rgbArray(rgbArray > 1) = 1;

    rgb255 = uint8(round(255 * rgbArray));
    frame  = reshape(rgb255.', 1, []);   % [R1 G1 B1 ... RN GN BN]

    write(ioObj, frame, "uint8");
    write(ioObj, uint8(10), "uint8");    % newline terminator
end
