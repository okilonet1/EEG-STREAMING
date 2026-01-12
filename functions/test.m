%% rcs2_record_strict.m
% BrainVision RCS2 – STRICT order script
% Metadata is ALWAYS sent before starting recording.
%
% Protocol (CR-terminated ASCII):
%   M                  -> start monitoring
%   2:<num>            -> experiment number
%   3:<subject>        -> subject id
%   SN:<serial>        -> LiveAmp serial
%   S                  -> start recording
%   AN:<tag>;<type>    -> marker
%   Q                  -> stop recording

clear; clc;

%% ========= CONFIG =========
RCS_IP   = "192.168.50.209";
RCS_PORT = 6700;

EXP_NUM    = 1;
SUBJECT_ID = "Jacob";
LIVEAMP_SN = "0599";

MARKERS = ["improv", "fixed"];   % example markers

%% ========= CONNECT =========
fprintf("Connecting to RCS at %s:%d\n", RCS_IP, RCS_PORT);
rcs = tcpclient(RCS_IP, RCS_PORT, "Timeout", 3);
configureTerminator(rcs, "CR");   % IMPORTANT: CR, not LF

drain(rcs, 0.5);

%% ========= START MONITORING =========
send(rcs, "M");
expectOK(rcs, "M");

%% ========= SEND METADATA (REQUIRED BEFORE S) =========
send(rcs, "2:" + EXP_NUM);
expectOK(rcs, "2:" + EXP_NUM);

send(rcs, "3:" + SUBJECT_ID);
expectOK(rcs, "3:" + SUBJECT_ID);

send(rcs, "SN:" + LIVEAMP_SN);
expectOK(rcs, "SN:" + LIVEAMP_SN);

fprintf("All metadata accepted.\n");

%% ========= START RECORDING =========
send(rcs, "S");
expectOK(rcs, "S");

fprintf("Recording started.\n");

%% ========= SEND MARKERS =========
pause(0.2); % guard
for m = MARKERS
    send(rcs, "AN:" + m + ";Comment");
    expectOK(rcs, "AN");
    pause(0.2);
end

%% ========= STOP RECORDING =========
send(rcs, "Q");
expectOK(rcs, "Q");

fprintf("Recording stopped.\n");

%% ================= LOCAL FUNCTIONS =================
function send(rcs, cmd)
% Send CR-terminated ASCII command
    bytes = uint8([char(string(cmd)) 13]); % 13 = '\r'
    write(rcs, bytes, "uint8");
    fprintf("[SENT] %s\\r\n", cmd);
end

function expectOK(rcs, tag)
% Read responses until "<tag>:OK" is seen or timeout
    t0 = tic;
    while toc(t0) < 2.0
        if rcs.NumBytesAvailable > 0
            line = strtrim(string(readline(rcs)));
            fprintf("  [RCS] %s\n", line);
            if contains(line, tag + ":OK")
                return
            end
        else
            pause(0.02);
        end
    end
    error("Timeout waiting for %s:OK", tag);
end

function drain(rcs, maxSec)
% Drain and print any initial lines (e.g., RS:1)
    t0 = tic;
    while toc(t0) < maxSec
        if rcs.NumBytesAvailable > 0
            try
                fprintf("  [RCS] %s\n", strtrim(string(readline(rcs))));
            catch
            end
        else
            pause(0.02);
        end
    end
end
