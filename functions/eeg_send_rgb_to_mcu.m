function eeg_send_rgb_to_mcu(rgbArray, portName, baud)
% rgbArray: nR x 3 (0–1)
% portName: "COM5" or "/dev/tty.SLAB_USBtoUART"
% baud: e.g., 115200

if nargin < 3, baud = 115200; end

sp = serialport(portName, baud);
rgb255 = uint8(round(255 * rgbArray));
frame  = reshape(rgb255.', 1, []);    % [R1 G1 B1 ... Rn Gn Bn]
write(sp, frame, "uint8");
write(sp, uint8(10), "uint8");        % newline terminator (optional)
end
