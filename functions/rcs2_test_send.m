function rcs2_test_send(varargin)
% RCS2_TEST_SEND  Minimal BrainVision RCS 2 TCP test client (MATLAB).
%
% What it does:
%   - Connects to RCS 2 over TCP
%   - Sends a few test commands (GETSTATUS, START/STOP optional, MARKER optional)
%   - Prints replies (OK / ERROR / status)
%
% Usage examples:
%   rcs2_test_send()                              % defaults: 127.0.0.1:6700, GETSTATUS only
%   rcs2_test_send("192.168.1.42", 6700)          % GETSTATUS to remote RCS
%   rcs2_test_send("192.168.1.42", 6700, true)    % also try START->MARKER->STOP sequence
%   rcs2_test_send("192.168.1.42", 6700, true, "StimOnset") % custom marker text
%
% Notes:
%   - RCS commands are newline-delimited.
%   - MARKER typically only works while recording (so use START first).
%
% Onyekachi / deepthinkkachi

% -------------------------
% Parse inputs
% -------------------------
host      = "127.0.0.1";
port      = 6700;
doRecord  = false;
markerTxt = "NetworkTest";

if nargin >= 1 && ~isempty(varargin{1}), host = string(varargin{1}); end
if nargin >= 2 && ~isempty(varargin{2}), port = double(varargin{2}); end
if nargin >= 3 && ~isempty(varargin{3}), doRecord = logical(varargin{3}); end
if nargin >= 4 && ~isempty(varargin{4}), markerTxt = string(varargin{4}); end

fprintf("\n=== RCS 2 TEST ===\nHost: %s  Port: %d\n", host, port);

% -------------------------
% Connect
% -------------------------
try
    rcs = tcpclient(host, port, "Timeout", 3);
catch ME
    error("Failed to connect to RCS at %s:%d\n%s", host, port, ME.message);
end

cleanupObj = onCleanup(@() safeClose(rcs)); %#ok<NASGU>

% -------------------------
% Send GETSTATUS
% -------------------------
resp = sendCmd(rcs, "GETSTATUS");
fprintf("[GETSTATUS] %s\n", pretty(resp));

% -------------------------
% Optional: START -> MARKER -> STOP
% -------------------------
if doRecord
    resp = sendCmd(rcs, "START");
    fprintf("[START] %s\n", pretty(resp));

    % Give Recorder a moment to transition to RECORDING
    pause(0.2);

    resp = sendCmd(rcs, "MARKER " + markerTxt);
    fprintf("[MARKER %s] %s\n", markerTxt, pretty(resp));

    pause(0.1);

    resp = sendCmd(rcs, "STOP");
    fprintf("[STOP] %s\n", pretty(resp));
end

fprintf("=== Done ===\n\n");

end

% =========================
% Helpers
% =========================
function out = sendCmd(rcs, cmd)
% Send one command (adds newline) and read response (best-effort).
cmd = string(cmd);
write(rcs, cmd + newline, "string");

% Wait briefly for response to arrive
t0 = tic;
out = "";
while toc(t0) < 1.0
    n = rcs.NumBytesAvailable;
    if n > 0
        out = out + string(read(rcs, n, "string"));
        % small extra wait to capture trailing bytes
        pause(0.05);
        n2 = rcs.NumBytesAvailable;
        if n2 > 0
            out = out + string(read(rcs, n2, "string"));
        end
        break
    end
    pause(0.02);
end

% If RCS doesn't respond to a command, return empty string
out = strtrim(out);
end

function s = pretty(resp)
if strlength(resp) == 0
    s = "(no response)";
else
    s = resp;
end
end

function safeClose(rcs)
% tcpclient objects close automatically when cleared, but keep this explicit.
try %#ok<TRYNC>
    clear rcs
end
end
