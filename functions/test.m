clear; clc;

addpath('functions');   % if stream_out.m lives in functions/

VIS_PORT = 9000;

for k = 1:1000
    data = randn(4, 8);                  % tiny 4×8 test table
    stream_out(data, "tcp_server", "", VIS_PORT);
    fprintf('Sent block %d\n', k);
    pause(0.5);
end
